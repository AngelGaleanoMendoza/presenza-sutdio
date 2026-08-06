-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Cerrar la lectura pública de datos de alumnas
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  EL PROBLEMA
--  La llave "anon" está escrita en el código de la página (cualquiera la ve
--  con "ver código fuente"). Hoy, con esa llave sola, cualquiera puede pedir:
--
--    https://TU-PROYECTO.supabase.co/rest/v1/suscriptoras?select=*
--    https://TU-PROYECTO.supabase.co/rest/v1/reservas?select=*
--
--  y Supabase responde con la tabla ENTERA: nombre, teléfono, correo, plan,
--  clases restantes, si pagó o no. De cada alumna, sin loguearse en ningún
--  lado y sin dejar rastro.
--
--  LA SOLUCIÓN
--  De aquí en adelante, leer esas tablas completas requiere haber iniciado
--  sesión de verdad (Supabase Auth) como el estudio o una coach. La página
--  pública sigue funcionando para cualquier visitante, pero a través de
--  funciones angostas que devuelven solo lo mínimo necesario:
--
--    cupos_del_dia          cuántos cupos hay y qué mats están tomados,
--                            sin nombres ni teléfonos (ya existía).
--    mi_suscripcion_activa  el plan de UNA alumna, dando su propio correo
--                            o teléfono — no la lista completa.
--    cobrar_clase_publica    descuenta 1 clase de su paquete al reservar,
--                            verificando que el correo/teléfono es dueño
--                            de esa suscripción antes de tocarla.
--    devolver_clase_publica  la devuelve si la reserva no se pudo guardar.
--    solicitar_plan_publico  registra una solicitud de plan nuevo.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  1. LECTURA: cerrada para el público, abierta para quien inició sesión
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists reservas_select on reservas;
create policy reservas_select on reservas for select
  using (auth.role() = 'authenticated');

drop policy if exists suscriptoras_select on suscriptoras;
create policy suscriptoras_select on suscriptoras for select
  using (auth.role() = 'authenticated');

drop policy if exists asistencias_select on asistencias;
create policy asistencias_select on asistencias for select
  using (auth.role() = 'authenticated');

-- horarios/eventos/clases_especiales/clases_canceladas SIGUEN públicas para
-- lectura: son el horario semanal, los eventos y los avisos de clases
-- libres o canceladas que cualquier visitante necesita ver para reservar.
-- No tienen nombres ni teléfonos de nadie, así que no hace falta cerrarlas.


-- ═══════════════════════════════════════════════════════════════════
--  2. ESCRITURA: solo el estudio y las coaches pueden modificar
--     reservas, suscriptoras, asistencias, horarios, eventos y clases
--     especiales/canceladas directamente.
--
--  El público sigue pudiendo RESERVAR (insertar en `reservas`) sin iniciar
--  sesión — eso no cambia. Lo que ya no puede es leer, actualizar ni
--  borrar filas directamente. Para lo poco que antes necesitaba tocar
--  `suscriptoras` (cobrar su clase, pedir un plan nuevo), ahora usa las
--  funciones angostas de la sección 4, que hacen ese trabajo por dentro
--  sin exponer la tabla.
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists reservas_update on reservas;
create policy reservas_update on reservas for update
  using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists reservas_delete on reservas;
create policy reservas_delete on reservas for delete
  using (auth.role() = 'authenticated');
-- reservas_insert se queda como estaba (with check (true)): así se sigue
-- pudiendo reservar sin iniciar sesión.

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
--  3. CINTURÓN Y TIRANTES: además de las políticas, se retira el permiso
--     de tabla en sí a la llave pública. Aunque alguien agregara sin
--     querer una política permisiva mañana, la llave anon seguiría sin
--     poder tocar estas tablas: hacen falta las dos cosas a la vez.
--     Mismo criterio que ya se usó con `alumnas`.
-- ═══════════════════════════════════════════════════════════════════
do $$
begin
  -- El estudio y las coaches necesitan poder leer y modificar estas tablas
  -- una vez logueadas. Supabase normalmente ya le da esto a "authenticated"
  -- por defecto en el esquema public, pero se deja explícito acá: así el
  -- archivo no depende de qué grants traiga tu proyecto de fábrica ni de
  -- si alguna vez se tocó ese permiso a mano.
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete
      on reservas, suscriptoras, asistencias, horarios, eventos,
         clases_especiales, clases_canceladas
      to authenticated;
    grant usage, select on all sequences in schema public to authenticated;
  end if;

  if exists (select 1 from pg_roles where rolname = 'anon') then
    -- reservas: se retira todo y se regresa SOLO insert (reservar sin login).
    -- El id es bigserial: sin usage sobre su secuencia, el insert falla
    -- igual aunque el grant de la tabla esté bien. Se detectó probando esto
    -- de verdad, no se ve a simple vista leyendo la política.
    revoke all on reservas from anon;
    grant insert on reservas to anon;
    grant usage on sequence reservas_id_seq to anon;

    -- suscriptoras y asistencias: cerradas del todo a la llave pública.
    -- Todo lo que el público necesitaba hacer ahí pasa por las funciones
    -- de la sección 4, que no dependen de este permiso (corren como dueñas).
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
  clave    text not null,          -- el correo o teléfono consultado
  momento  timestamptz not null default now()
);
create index if not exists intentos_consulta_plan_idx
  on intentos_consulta_plan (clave, momento desc);
alter table intentos_consulta_plan enable row level security;
-- Sin policies y sin grant a anon: nadie la lee directo, solo las funciones.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on intentos_consulta_plan from anon;
  end if;
end $$;


-- ── 4.1 · ¿Tiene esta alumna una suscripción? ──
-- Da SOLO la fila de quien pregunta por su propio correo o teléfono, en
-- las mismas columnas que ya usa el sitio (rowToSub las lee tal cual).
-- No es lectura libre: 15 intentos por clave y 15 minutos de espera.
--
-- p_nombre es para las fichas que el estudio cargó a mano: todavía no
-- tienen correo ni teléfono real (@pendiente.presenza, tel vacío), así que
-- ni email ni tel las pueden identificar. Se reconocen por nombre, pero
-- SOLO mientras sigan sin reclamar: nunca contra una ficha que ya tiene
-- correo real, porque dos alumnas distintas pueden llamarse igual.
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
  -- OJO: norm_tel(null) da '' (cadena vacía), no NULL. Encadenar coalesce()
  -- con eso se queda pegado en el '' del teléfono vacío y nunca llega a
  -- probar el nombre: hay que revisar explícitamente que cada dato SIRVA
  -- (tenga contenido real), no solo que no sea NULL.
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
-- Antes esto lo hacía el navegador: bajaba toda la fila, restaba 1 y subía
-- la fila entera con un UPSERT. Cualquiera con la llave anon podía mandar
-- ese mismo POST con cualquier id y cualquier número de clases. Acá el
-- descuento lo hace la base, verificando primero que el correo o teléfono
-- que llega es realmente dueño de esa suscripción.
-- De paso hace lo que hacía vincularFicha(): si la ficha era de una alumna
-- cargada a mano (sin correo real), le pega el correo/teléfono con los que
-- se identificó, para que de ahí en adelante se reconozca como todas.
-- OJO con los nombres de los OUT (returns table): "clases_restantes" como
-- salida choca con la columna real de la tabla del mismo nombre, y dentro
-- de la función Postgres ya no sabe si un "clases_restantes" suelto es la
-- variable de salida o la columna — el UPDATE fallaba con "ambiguous" y no
-- descontaba nada. Por eso el de salida se llama "restantes", distinto.
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

  -- Dueña verificada por correo, por teléfono, o por nombre SOLO si la
  -- ficha sigue sin reclamar (cargada a mano, todavía sin correo real).
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

  -- Ahora que el OUT ya no se llama "clases_restantes" (es "restantes"),
  -- no hace falta calificar nada acá: no queda ningún nombre en conflicto.
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
-- El mismo cuido de identidad que el cobro; sin esto una reserva que falla
-- a mitad de camino le dejaría la clase descontada sin haber reservado nada.
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
-- Antes de tocar nada, revisa si ya existe una ficha de esa persona por
-- correo, y si no, por teléfono + nombre (mismo criterio que ya usa el
-- resto del sitio, vía nombre_coincide). Si existe, solo marca pendiente
-- de pago; si no, crea la ficha.
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
    -- Mismo formato que ya genera el sitio (SUB-XXXXXX), sin depender de
    -- ninguna extensión: random()+timestamp es de sobra para un identificador
    -- que no es secreto, solo tiene que no repetirse.
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
-- ═══════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function mi_suscripcion_activa(text, text, text)            to anon;
    grant execute on function cobrar_clase_publica(text, text, text, text)       to anon;
    grant execute on function devolver_clase_publica(text, text, text)           to anon;
    grant execute on function solicitar_plan_publico(text, text, text, text, text) to anon;
  end if;
end $$;
