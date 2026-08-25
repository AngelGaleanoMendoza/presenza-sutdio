-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Reserva doble, cancelar sola, y avisar lo cancelado
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  QUÉ RESUELVE (los tres pedidos de Jimena)
--
--  1) Una alumna podía reservar DOS VECES la misma clase.
--     El sitio ya lo revisaba… pero comparando correos contra una lista
--     que, para quien no ha iniciado sesión, viene SIN correos: cupos_del_dia()
--     devuelve cuántos lugares hay tomados y cuáles mats, nunca de quién.
--     La comparación siempre daba "no coincide" y la segunda reserva pasaba.
--     Acá va ya_reservada(): la pregunta la contesta la base, que sí ve los
--     datos, sin devolverle a nadie el nombre ni el teléfono de otra alumna.
--
--  2) Que la alumna pueda cancelar sola si faltan MÁS DE 6 HORAS.
--     cancelar_mi_reserva() valida que la reserva sea suya, que falte tiempo
--     suficiente, libera el mat y le devuelve la clase a su paquete si se la
--     habían descontado. Con menos de 6 horas no deja: tiene que escribir.
--
--  3) Cuando el estudio cancela una clase, que a ella le APAREZCA.
--     Hasta hoy cancelar borraba las reservas: la clase desaparecía de "Mis
--     clases" sin dejar rastro y la alumna se enteraba llegando al estudio.
--     Ahora la reserva se MARCA como cancelada en vez de borrarse, y sale en
--     su panel con el motivo. El mat se libera igual (lugar = null), así que
--     si la clase se reactiva el lugar vuelve a estar disponible.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  1. LA MARCA DE CANCELADA
--
--  `cancelada` es la fecha y hora en que se canceló (null = vigente).
--  Se usa como filtro en todos lados: una reserva cancelada no ocupa
--  cupo, no ocupa mat y no sale en las listas del panel — pero SÍ sigue
--  existiendo, que es justamente lo que le permite verla a la alumna.
-- ═══════════════════════════════════════════════════════════════════
alter table reservas add column if not exists cancelada        timestamptz;
alter table reservas add column if not exists cancelada_por    text;   -- 'estudio' | 'alumna'
alter table reservas add column if not exists cancelada_motivo text;

-- Viene de supabase-descuento-al-reservar.sql. Se repite acá porque las
-- funciones de abajo la leen: si ese archivo todavía no se corrió, sin esta
-- línea el Run entero fallaría con un "column does not exist" confuso.
alter table reservas add column if not exists clase_descontada boolean not null default false;

-- Las consultas de cupos filtran por esta columna en cada carga del sitio.
create index if not exists reservas_vigentes_idx
  on reservas (fecha) where cancelada is null;


-- ═══════════════════════════════════════════════════════════════════
--  2. ¿YA TIENE RESERVA EN ESTA CLASE?
--
--  Devuelve solo true/false. No dice quién ni cuántas: una visitante
--  cualquiera podría llamarla con el teléfono de otra persona, y lo único
--  que averiguaría es que esa persona va a esa clase — que es lo mismo que
--  ya sabe quien esté sentada al lado. Ningún dato personal sale de acá.
--
--  Compara igual que el resto del sitio: teléfono normalizado (que es la
--  identidad real, con la que la alumna inicia sesión) O correo en
--  minúsculas. Basta que uno de los dos coincida.
-- ═══════════════════════════════════════════════════════════════════
create or replace function ya_reservada(
  p_clase text, p_fecha date, p_hora text, p_tel text, p_email text
)
returns boolean
language sql security definer set search_path = public as $$
  select exists (
    select 1
      from reservas r
     where r.clase = p_clase
       and r.fecha = p_fecha
       and r.hora  = p_hora
       and r.cancelada is null
       and (
         (length(norm_tel(p_tel)) >= 8 and norm_tel(r.tel) = norm_tel(p_tel))
         or (nullif(trim(lower(p_email)), '') is not null
             and lower(coalesce(r.email, '')) = trim(lower(p_email)))
       )
  );
$$;


-- ═══════════════════════════════════════════════════════════════════
--  3. CANCELAR SOLA · con más de 6 horas de anticipación
--
--  La hora de la clase es hora de Nicaragua, no de UTC. Postgres corre en
--  UTC: sin el `at time zone` una clase de las 6am se compararía contra un
--  reloj corrido seis horas y la ventana daría cualquier cosa.
--
--  Devuelve (ok, mensaje, devuelta) en vez de tirar excepción: así el sitio
--  puede mostrarle el motivo exacto sin depender de cómo viene el error.
-- ═══════════════════════════════════════════════════════════════════
create or replace function cancelar_mi_reserva(p_token uuid, p_ts bigint)
returns table (ok boolean, mensaje text, devuelta boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tel     text;
  v_email   text;
  v_res     reservas%rowtype;
  v_inicio  timestamptz;
  v_sub_id  text;
  v_devuelta boolean := false;
begin
  select norm_tel(a.tel), lower(coalesce(a.email, ''))
    into v_tel, v_email
    from alumnas a
    join sesiones_alumna s on s.alumna_id = a.id
   where s.token = p_token and s.expira > now();

  if v_tel is null then
    return query select false, 'Tu sesión expiró. Vuelve a entrar.', false; return;
  end if;

  -- La reserva tiene que ser SUYA: el ts por sí solo no alcanza.
  select * into v_res
    from reservas r
   where r.ts = p_ts
     and (norm_tel(r.tel) = v_tel
          or (v_email <> '' and lower(coalesce(r.email, '')) = v_email))
   limit 1;

  if not found then
    return query select false, 'No encontramos esa reserva a tu nombre.', false; return;
  end if;

  if v_res.cancelada is not null then
    return query select false, 'Esa reserva ya estaba cancelada.', false; return;
  end if;

  v_inicio := (v_res.fecha + v_res.hora::time) at time zone 'America/Managua';

  if v_inicio <= now() then
    return query select false, 'Esa clase ya pasó.', false; return;
  end if;

  if v_inicio - now() < interval '6 hours' then
    return query select false,
      'Faltan menos de 6 horas para tu clase: ya no se puede cancelar desde la app. Escríbenos por WhatsApp ✧',
      false; return;
  end if;

  -- Se le devuelve la clase al paquete solo si esta reserva se la descontó.
  if coalesce(v_res.clase_descontada, false) then
    select s.id into v_sub_id
      from suscriptoras s
     where (nullif(lower(coalesce(v_res.email, '')), '') is not null
            and lower(s.email) = lower(v_res.email))
        or (length(norm_tel(v_res.tel)) >= 8 and norm_tel(s.tel) = norm_tel(v_res.tel))
     limit 1;

    if v_sub_id is not null then
      update suscriptoras
         set clases_restantes = clases_restantes + 1,
             clases_usadas    = greatest(0, coalesce(clases_usadas, 0) - 1)
       where id = v_sub_id
         and clases_restantes < 1000;      -- a una ilimitada no hay qué devolverle
      v_devuelta := found;
    end if;
  end if;

  -- Cancelada por ella: se borra de verdad. Ya sabe que canceló —no necesita
  -- verlo en su panel— y así el mat queda libre sin arrastrar una fila muerta.
  delete from reservas where ts = p_ts;

  return query select true, 'Tu reserva quedó cancelada.', v_devuelta;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  4. CANCELAR UNA SESIÓN COMPLETA (lo hace el estudio)
--
--  Marca todas las reservas vigentes de esa clase como canceladas y suelta
--  el mat. No borra: la fila es lo único que le va a contar a la alumna que
--  su clase se cayó.
--
--  Devuelve a cuántas alumnas les tocaba y a cuántas se les devolvió clase,
--  para que el panel pueda decirlo en el aviso.
-- ═══════════════════════════════════════════════════════════════════
create or replace function cancelar_sesion_estudio(
  p_clase text, p_fecha date, p_hora text, p_motivo text
)
returns table (afectadas int, devueltas int)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_res       reservas%rowtype;
  v_sub_id    text;
  v_afectadas int := 0;
  v_devueltas int := 0;
begin
  for v_res in
    select * from reservas
     where clase = p_clase and fecha = p_fecha and hora = p_hora and cancelada is null
  loop
    v_afectadas := v_afectadas + 1;

    if coalesce(v_res.clase_descontada, false) then
      select s.id into v_sub_id
        from suscriptoras s
       where (nullif(lower(coalesce(v_res.email, '')), '') is not null
              and lower(s.email) = lower(v_res.email))
          or (length(norm_tel(v_res.tel)) >= 8 and norm_tel(s.tel) = norm_tel(v_res.tel))
       limit 1;

      if v_sub_id is not null then
        update suscriptoras
           set clases_restantes = clases_restantes + 1,
               clases_usadas    = greatest(0, coalesce(clases_usadas, 0) - 1)
         where id = v_sub_id and clases_restantes < 1000;
        if found then v_devueltas := v_devueltas + 1; end if;
      end if;
    end if;

    -- lugar = null suelta el mat: el índice único (slot_key, lugar) no lo
    -- deja reservado para siempre si la clase después se reactiva.
    update reservas
       set cancelada        = now(),
           cancelada_por    = 'estudio',
           cancelada_motivo = nullif(trim(coalesce(p_motivo, '')), ''),
           lugar            = null
     where ts = v_res.ts;
  end loop;

  return query select v_afectadas, v_devueltas;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  5. MIS CLASES · ahora con las canceladas y con el ts para cancelar
--
--  Cambia respecto a la versión de supabase-login-alumnas.sql:
--    · devuelve `ts` (lo necesita el botón de cancelar)
--    · devuelve `cancelada_motivo`
--    · estado suma 'cancelada'
--    · devuelve `puede_cancelar`: la ventana de 6 horas se calcula acá,
--      con el reloj del servidor. Si se calculara en el celular, bastaría
--      con atrasar la hora del teléfono para cancelar a destiempo.
--
--  Va con DROP: `create or replace` no puede cambiarle las columnas de
--  salida a una función que ya existe, y esta versión devuelve cuatro más.
-- ═══════════════════════════════════════════════════════════════════
drop function if exists mis_clases(uuid);
create or replace function mis_clases(p_token uuid)
returns table (
  fecha           date,
  hora            text,
  clase           text,
  instructor      text,
  lugar           int,
  metodo          text,
  pago_ok         boolean,
  ts              bigint,
  motivo          text,
  puede_cancelar  boolean,
  estado          text          -- 'proxima' | 'pasada' | 'cancelada'
)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tel   text;
  v_email text;
begin
  select norm_tel(a.tel), lower(coalesce(a.email, ''))
    into v_tel, v_email
    from alumnas a
    join sesiones_alumna s on s.alumna_id = a.id
   where s.token = p_token and s.expira > now();

  if v_tel is null then
    raise exception 'Tu sesión expiró. Vuelve a entrar.' using errcode = 'P0001';
  end if;

  return query
    select r.fecha, r.hora, r.clase, r.instructor, r.lugar, r.metodo, r.pago_ok,
           r.ts,
           r.cancelada_motivo,
           (r.cancelada is null
             and ((r.fecha + r.hora::time) at time zone 'America/Managua')
                 - now() >= interval '6 hours'),
           case when r.cancelada is not null then 'cancelada'
                when r.fecha >= hoy_ni()     then 'proxima'
                else 'pasada' end
      from reservas r
     where norm_tel(r.tel) = v_tel
        or (v_email <> '' and lower(coalesce(r.email, '')) = v_email)
     order by r.fecha desc, r.hora desc;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  6. CUPOS · una reserva cancelada no ocupa lugar
-- ═══════════════════════════════════════════════════════════════════
create or replace function cupos_del_dia(p_desde date, p_hasta date)
returns table (
  clase         text,
  fecha         date,
  hora          text,
  ocupados      bigint,
  mats_ocupados int[]
)
language sql security definer set search_path = public as $$
  select r.clase, r.fecha, r.hora,
         count(*),
         coalesce(array_agg(r.lugar order by r.lugar) filter (where r.lugar is not null),
                  '{}'::int[])
    from reservas r
   where r.fecha between p_desde and p_hasta
     and r.cancelada is null
   group by r.clase, r.fecha, r.hora;
$$;


-- ═══════════════════════════════════════════════════════════════════
--  QUIÉN PUEDE LLAMAR QUÉ
--
--  ya_reservada y cancelar_mi_reserva las llama una alumna sin cuenta de
--  Supabase (llave pública). cancelar_sesion_estudio NO: esa la llama el
--  panel, que sí inicia sesión.
-- ═══════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function ya_reservada(text, date, text, text, text) to anon;
    grant execute on function cancelar_mi_reserva(uuid, bigint)          to anon;
    grant execute on function mis_clases(uuid)                           to anon;
    grant execute on function cupos_del_dia(date, date)                  to anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant execute on function ya_reservada(text, date, text, text, text) to authenticated;
    grant execute on function cancelar_sesion_estudio(text, date, text, text) to authenticated;
    grant execute on function mis_clases(uuid)                           to authenticated;
    grant execute on function cupos_del_dia(date, date)                  to authenticated;
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  REVISIÓN · que se vea de un vistazo si quedó bien
-- ═══════════════════════════════════════════════════════════════════
select 1 as paso, 'Columna reservas.cancelada' as que,
       case when exists (select 1 from information_schema.columns
                          where table_name = 'reservas' and column_name = 'cancelada')
            then '✅ lista' else '❌ falta' end as estado
union all
select 2, 'Función ya_reservada',
       case when to_regprocedure('ya_reservada(text,date,text,text,text)') is not null
            then '✅ lista' else '❌ falta' end
union all
select 3, 'Función cancelar_mi_reserva',
       case when to_regprocedure('cancelar_mi_reserva(uuid,bigint)') is not null
            then '✅ lista' else '❌ falta' end
union all
select 4, 'Función cancelar_sesion_estudio',
       case when to_regprocedure('cancelar_sesion_estudio(text,date,text,text)') is not null
            then '✅ lista' else '❌ falta' end
order by paso;
