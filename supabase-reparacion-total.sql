-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · REPARACIÓN TOTAL de permisos y funciones
--  Pegar TODO esto en Supabase → SQL Editor → Run  (una sola vez alcanza,
--  pero es seguro correrlo las veces que haga falta)
--
--  POR QUÉ EXISTE ESTE ARCHIVO
--  El candado de seguridad quedó aplicado a medias: las políticas que
--  CIERRAN las tablas sí entraron, pero faltaron piezas que las ABREN por
--  el camino correcto (la función cupos_del_dia para la página pública y
--  los permisos del rol `authenticated` para el panel). Resultado: las
--  reservas SIGUEN INTACTAS en la base, pero ni la web ni el panel las
--  podían leer — se veía todo en 0 y daba "permission denied".
--
--  Este archivo NO depende de ningún otro: trae adentro todo lo que
--  necesita (funciones de apoyo incluidas). Al terminar muestra una tabla
--  de chequeos con ✓ / ✗ para confirmar que todo quedó bien.
--
--  IMPORTANTE: no borra ni modifica ninguna reserva, suscriptora ni
--  asistencia. Solo toca permisos, políticas y funciones.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  0. FUNCIONES DE APOYO · por si supabase-login-alumnas.sql nunca se
--     corrió (o quedó en una versión vieja). Son las mismas de siempre.
-- ═══════════════════════════════════════════════════════════════════

-- Deja 8 dígitos limpios: '+505 8431-7983' → '84317983'
create or replace function norm_tel(t text)
returns text language sql immutable as $$
  select case
           when length(d) > 8 and left(d, 3) = '505' then substr(d, 4)
           else d
         end
  from (
    select regexp_replace(regexp_replace(coalesce(t, ''), '\D', '', 'g'), '^0+', '') as d
  ) s;
$$;

-- Minúsculas, sin tildes, sin puntuación, sin espacios de más.
create or replace function norm_nombre(n text)
returns text language sql immutable as $$
  select regexp_replace(
           regexp_replace(
             translate(lower(trim(coalesce(n, ''))), 'áéíóúüñ', 'aeiouun'),
             '[^a-z0-9 ]', '', 'g'),
           '\s+', ' ', 'g');
$$;

-- ¿Comparten al menos una palabra de 3 letras o más?
create or replace function nombre_coincide(a text, b text)
returns boolean language sql immutable as $$
  select exists (
    select 1
      from unnest(string_to_array(norm_nombre(a), ' ')) w1
      join unnest(string_to_array(norm_nombre(b), ' ')) w2 on w1 = w2
     where length(w1) >= 3
  );
$$;

-- El día de hoy EN NICARAGUA (Postgres corre en UTC).
create or replace function hoy_ni()
returns date language sql stable as $$
  select (now() at time zone 'America/Managua')::date;
$$;


-- ═══════════════════════════════════════════════════════════════════
--  1. cupos_del_dia · LA PIEZA QUE HACÍA VER LA WEB "EN 0"
--
--  La página pública ya no lee la tabla `reservas` (está cerrada al
--  público, y así debe quedarse). En su lugar llama a esta función, que
--  dice cuántos cupos hay y qué mats están tomados SIN entregar nombres
--  ni teléfonos. Si esta función no existe, la página no tiene de dónde
--  sacar los cupos y pinta todo vacío.
-- ═══════════════════════════════════════════════════════════════════
drop function if exists cupos_del_dia(date);          -- versión vieja de un solo día
drop function if exists cupos_del_dia(date, date);

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
   group by r.clase, r.fecha, r.hora;
$$;


-- ═══════════════════════════════════════════════════════════════════
--  2. POLÍTICAS · lectura y escritura de datos de alumnas solo con
--     sesión iniciada; el público puede reservar y ver el horario.
-- ═══════════════════════════════════════════════════════════════════
alter table reservas     enable row level security;
alter table suscriptoras enable row level security;
alter table asistencias  enable row level security;

-- Lectura: cerrada al público, abierta a quien inició sesión.
drop policy if exists reservas_select on reservas;
create policy reservas_select on reservas for select
  using (auth.role() = 'authenticated');

drop policy if exists suscriptoras_select on suscriptoras;
create policy suscriptoras_select on suscriptoras for select
  using (auth.role() = 'authenticated');

drop policy if exists asistencias_select on asistencias;
create policy asistencias_select on asistencias for select
  using (auth.role() = 'authenticated');

-- Reservar SIN iniciar sesión sigue permitido: es la página pública.
drop policy if exists reservas_insert on reservas;
create policy reservas_insert on reservas for insert
  with check (true);

-- Modificar o borrar reservas: solo con sesión.
drop policy if exists reservas_update on reservas;
create policy reservas_update on reservas for update
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists reservas_delete on reservas;
create policy reservas_delete on reservas for delete
  using (auth.role() = 'authenticated');

drop policy if exists suscriptoras_insert on suscriptoras;
create policy suscriptoras_insert on suscriptoras for insert
  with check (auth.role() = 'authenticated');

drop policy if exists suscriptoras_update on suscriptoras;
create policy suscriptoras_update on suscriptoras for update
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists suscriptoras_delete on suscriptoras;
create policy suscriptoras_delete on suscriptoras for delete
  using (auth.role() = 'authenticated');

drop policy if exists asistencias_insert on asistencias;
create policy asistencias_insert on asistencias for insert
  with check (auth.role() = 'authenticated');

drop policy if exists asistencias_delete on asistencias;
create policy asistencias_delete on asistencias for delete
  using (auth.role() = 'authenticated');

drop policy if exists horarios_write on horarios;
create policy horarios_write on horarios for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists eventos_write on eventos;
create policy eventos_write on eventos for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists clases_especiales_insert on clases_especiales;
create policy clases_especiales_insert on clases_especiales for insert
  with check (auth.role() = 'authenticated');
drop policy if exists clases_especiales_update on clases_especiales;
create policy clases_especiales_update on clases_especiales for update
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
drop policy if exists clases_especiales_delete on clases_especiales;
create policy clases_especiales_delete on clases_especiales for delete
  using (auth.role() = 'authenticated');

drop policy if exists clases_canceladas_write on clases_canceladas;
create policy clases_canceladas_write on clases_canceladas for all
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');


-- ═══════════════════════════════════════════════════════════════════
--  3. PERMISOS DE TABLA · la pieza que hacía fallar el PANEL
--
--  Las políticas de arriba no bastan solas: además el ROL con el que
--  llega cada llamada necesita el permiso de tabla. `authenticated` (el
--  estudio y las coaches ya logueadas) necesita los cuatro; `anon` (el
--  público) solo insertar reservas y leer el horario.
-- ═══════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete
      on reservas, suscriptoras, asistencias, horarios, eventos,
         clases_especiales, clases_canceladas
      to authenticated;
    grant usage, select on all sequences in schema public to authenticated;
  end if;

  if exists (select 1 from pg_roles where rolname = 'anon') then
    -- reservas: solo insertar (reservar sin login). El id es bigserial:
    -- sin usage sobre su secuencia el insert falla aunque el grant esté.
    revoke all on reservas from anon;
    grant insert on reservas to anon;
    grant usage on sequence reservas_id_seq to anon;

    -- suscriptoras y asistencias: cerradas del todo a la llave pública.
    revoke all on suscriptoras from anon;
    revoke all on asistencias  from anon;

    -- horarios/eventos/especiales/canceladas: solo lectura pública.
    revoke all on horarios, eventos, clases_especiales, clases_canceladas from anon;
    grant select on horarios, eventos, clases_especiales, clases_canceladas to anon;
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  4. FUNCIONES PARA EL PÚBLICO · lo mínimo necesario, nada más
-- ═══════════════════════════════════════════════════════════════════

drop function if exists mi_suscripcion_activa(text, text);
drop function if exists mi_suscripcion_activa(text, text, text);
drop function if exists cobrar_clase_publica(text, text, text);
drop function if exists cobrar_clase_publica(text, text, text, text);
drop function if exists devolver_clase_publica(text, text, text);
drop function if exists solicitar_plan_publico(text, text, text, text, text);

-- Freno contra probar números/correos al voleo para ver quién tiene plan.
create table if not exists intentos_consulta_plan (
  id       bigserial primary key,
  clave    text not null,
  momento  timestamptz not null default now()
);
create index if not exists intentos_consulta_plan_idx
  on intentos_consulta_plan (clave, momento desc);
alter table intentos_consulta_plan enable row level security;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on intentos_consulta_plan from anon;
  end if;
end $$;

-- ── 4.1 · ¿Tiene esta alumna una suscripción? ──
create or replace function mi_suscripcion_activa(p_email text, p_tel text, p_nombre text default null)
returns table (
  id text, email text, nombre text, tel text, plan text,
  clases_total int, clases_restantes int, clases_usadas int,
  activa boolean, fecha_inicio date, fecha_vence date,
  pendiente_plan text, pendiente_fecha date
)
language plpgsql security definer set search_path = public as $$
declare
  v_clave text;
  v_fall  int;
begin
  -- OJO: norm_tel(null) da '' (cadena vacía), no NULL: hay que revisar
  -- explícitamente que cada dato tenga contenido real.
  v_clave := case
    when nullif(trim(lower(p_email)), '') is not null then trim(lower(p_email))
    when length(norm_tel(p_tel)) >= 8                 then norm_tel(p_tel)
    when nullif(trim(p_nombre), '') is not null        then 'nombre:'||norm_nombre(p_nombre)
    else null
  end;
  if v_clave is null then return; end if;

  select count(*) into v_fall from intentos_consulta_plan
   where clave = v_clave and momento > now() - interval '15 minutes';
  if v_fall >= 15 then
    raise exception 'Demasiadas consultas. Espera unos minutos e intenta de nuevo.'
      using errcode = 'P0001';
  end if;
  insert into intentos_consulta_plan (clave) values (v_clave);

  return query
    select s.id, s.email, s.nombre, s.tel, s.plan,
           s.clases_total, s.clases_restantes, s.clases_usadas,
           s.activa, s.fecha_inicio, s.fecha_vence,
           s.pendiente_plan, s.pendiente_fecha
      from suscriptoras s
     where (nullif(trim(lower(p_email)), '') is not null
              and lower(s.email) = trim(lower(p_email)))
        or (length(norm_tel(p_tel)) >= 8 and norm_tel(s.tel) = norm_tel(p_tel))
        or (nullif(trim(p_nombre), '') is not null
              and s.email ilike '%@pendiente.presenza'
              and nombre_coincide(s.nombre, p_nombre))
     limit 1;
end $$;

-- ── 4.2 · Cobrar 1 clase al reservar ──
-- OJO con los OUT: "clases_restantes" como salida chocaría con la columna
-- real del mismo nombre y el UPDATE fallaría con "ambiguous". Por eso la
-- salida se llama "restantes".
create or replace function cobrar_clase_publica(
  p_sub_id text, p_email text, p_tel text, p_nombre text default null
)
returns table (ok boolean, restantes int, mensaje text)
language plpgsql security definer set search_path = public as $$
declare
  v_sub    suscriptoras%rowtype;
  v_quedan int;
begin
  select * into v_sub from suscriptoras where id = p_sub_id;
  if not found then
    return query select false, 0, 'Suscripción no encontrada.'; return;
  end if;

  if not (
    (nullif(trim(lower(p_email)), '') is not null and lower(v_sub.email) = trim(lower(p_email)))
    or (length(norm_tel(p_tel)) >= 8 and norm_tel(v_sub.tel) = norm_tel(p_tel))
    or (nullif(trim(p_nombre), '') is not null
          and v_sub.email ilike '%@pendiente.presenza'
          and nombre_coincide(v_sub.nombre, p_nombre))
  ) then
    return query select false, 0, 'No coincide con esa suscripción.'; return;
  end if;

  if v_sub.clases_restantes >= 1000 then           -- ilimitada: no descuenta
    return query select true, v_sub.clases_restantes, 'Plan ilimitado.'; return;
  end if;
  if v_sub.clases_restantes <= 0 then
    return query select false, 0, 'No tienes clases disponibles en tu paquete.'; return;
  end if;

  update suscriptoras
     set clases_restantes = clases_restantes - 1,
         clases_usadas    = coalesce(clases_usadas, 0) + 1,
         email = case when v_sub.email ilike '%@pendiente.presenza'
                         and nullif(trim(p_email), '') is not null
                      then trim(lower(p_email)) else email end,
         tel   = case when nullif(trim(p_tel), '') is not null
                      then trim(p_tel) else tel end
   where id = p_sub_id
   returning clases_restantes into v_quedan;

  return query select true, v_quedan, 'ok';
end $$;

-- ── 4.3 · Devolver la clase si la reserva no se pudo guardar ──
create or replace function devolver_clase_publica(p_sub_id text, p_email text, p_tel text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_sub suscriptoras%rowtype;
begin
  select * into v_sub from suscriptoras where id = p_sub_id;
  if not found then return false; end if;

  if not (
    (nullif(trim(lower(p_email)), '') is not null and lower(v_sub.email) = trim(lower(p_email)))
    or (length(norm_tel(p_tel)) >= 8 and norm_tel(v_sub.tel) = norm_tel(p_tel))
  ) then
    return false;
  end if;

  if v_sub.clases_restantes < 1000 then
    update suscriptoras
       set clases_restantes = clases_restantes + 1,
           clases_usadas    = greatest(0, coalesce(clases_usadas, 0) - 1)
     where id = p_sub_id;
  end if;
  return true;
end $$;

-- ── 4.4 · Solicitar un plan nuevo (o renovación) ──
create or replace function solicitar_plan_publico(
  p_nombre text, p_email text, p_tel text, p_nivel text, p_plan text
)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_id  text;
  v_em  text := trim(lower(p_email));
begin
  select id into v_id from suscriptoras where lower(email) = v_em;

  if v_id is null and length(norm_tel(p_tel)) >= 8 then
    select id into v_id from suscriptoras
     where norm_tel(tel) = norm_tel(p_tel) and nombre_coincide(nombre, p_nombre)
     limit 1;
  end if;

  if v_id is not null then
    update suscriptoras
       set pendiente_plan  = p_plan,
           pendiente_fecha = hoy_ni(),
           nombre = coalesce(nullif(p_nombre, ''), nombre),
           tel    = coalesce(nullif(p_tel, ''), tel),
           email  = case when email ilike '%@pendiente.presenza' and v_em <> ''
                         then v_em else email end
     where id = v_id;
  else
    v_id := 'SUB-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    insert into suscriptoras
      (id, nombre, email, tel, notas, plan, clases_total, clases_restantes,
       clases_usadas, activa, pendiente_plan, pendiente_fecha)
    values
      (v_id, p_nombre, p_email, coalesce(p_tel, ''), coalesce(p_nivel, ''), p_plan,
       0, 0, 0, false, p_plan, hoy_ni());
  end if;

  return v_id;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  5. QUIÉN PUEDE LLAMAR QUÉ
--     También `authenticated`: si Jimena reserva estando logueada, sus
--     llamadas van con SU sesión, no con la llave anon, y sin este grant
--     esas mismas funciones le fallarían solo a ella.
-- ═══════════════════════════════════════════════════════════════════
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function cupos_del_dia(date, date) to %I', r);
      execute format('grant execute on function mi_suscripcion_activa(text, text, text) to %I', r);
      execute format('grant execute on function cobrar_clase_publica(text, text, text, text) to %I', r);
      execute format('grant execute on function devolver_clase_publica(text, text, text) to %I', r);
      execute format('grant execute on function solicitar_plan_publico(text, text, text, text, text) to %I', r);
    end if;
  end loop;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  6. CHEQUEO FINAL · esto es lo que vas a ver al darle Run.
--     Todo debe salir con ✓. Si algo sale con ✗, mándale una foto de
--     esta tabla a quien te está ayudando.
-- ═══════════════════════════════════════════════════════════════════
select * from (
  select 1 as orden, 'Reservas guardadas en total' as chequeo,
         (select count(*) from reservas)::text as resultado
  union all
  select 2, 'Reservas de HOY (' || hoy_ni() || ')',
         (select count(*) from reservas where fecha = hoy_ni())::text
  union all
  select 3, 'Función cupos_del_dia (los cupos de la web pública)',
         case when to_regprocedure('cupos_del_dia(date,date)') is not null
              then '✓ existe' else '✗ FALTA' end
  union all
  select 4, 'Función mi_suscripcion_activa',
         case when to_regprocedure('mi_suscripcion_activa(text,text,text)') is not null
              then '✓ existe' else '✗ FALTA' end
  union all
  select 5, 'Función cobrar_clase_publica',
         case when to_regprocedure('cobrar_clase_publica(text,text,text,text)') is not null
              then '✓ existe' else '✗ FALTA' end
  union all
  select 6, 'El público NO puede leer reservas',
         case when has_table_privilege('anon', 'reservas', 'select')
              then '✗ ABIERTA (mal)' else '✓ cerrada' end
  union all
  select 7, 'El público NO puede leer suscriptoras',
         case when has_table_privilege('anon', 'suscriptoras', 'select')
              then '✗ ABIERTA (mal)' else '✓ cerrada' end
  union all
  select 8, 'El público SÍ puede reservar',
         case when has_table_privilege('anon', 'reservas', 'insert')
              then '✓ puede' else '✗ NO PUEDE (mal)' end
  union all
  select 9, 'El panel (con sesión) puede leer reservas',
         case when has_table_privilege('authenticated', 'reservas', 'select')
              then '✓ puede' else '✗ NO PUEDE (mal)' end
  union all
  select 10, 'El panel (con sesión) puede eliminar reservas',
         case when has_table_privilege('authenticated', 'reservas', 'delete')
              then '✓ puede' else '✗ NO PUEDE (mal)' end
) t order by orden;
