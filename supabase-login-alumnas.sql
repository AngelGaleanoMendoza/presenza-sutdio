-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Acceso de alumnas ("Mis clases")
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  QUÉ RESUELVE
--  La alumna entra con su teléfono y un PIN de 4 dígitos que ella misma
--  elige, y ve únicamente SUS clases y SU plan.
--
--  POR QUÉ ASÍ Y NO CON UN FILTRO EN JAVASCRIPT
--  La llave anon está a la vista en el código de la página. Un filtro en
--  el navegador es una cortina: la alumna ve lo suyo, pero cualquiera que
--  abra el código sigue pudiendo pedir todo. Acá el aislamiento lo hace
--  la base: estas tablas NO son legibles con la llave anon, y lo único
--  que se puede llamar son las funciones de abajo, que devuelven las
--  filas de una sola persona.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;


-- ═══════════════════════════════════════════════════════════════════
--  HELPERS · misma normalización que ya usa el sitio
-- ═══════════════════════════════════════════════════════════════════

-- Espejo de normTel() del index.html: deja 8 dígitos limpios.
--   '8431 7983' · '+505 8431-7983' · '00505 84317983'  →  '84317983'
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

-- Espejo de normNombre(): minúsculas, sin tildes, sin espacios de más.
-- Además quita puntuación: el estudio tiene fichas cargadas como
-- "Ma. Carmen", y el punto hacía que el nombre nunca coincidiera.
create or replace function norm_nombre(n text)
returns text language sql immutable as $$
  select regexp_replace(
           regexp_replace(
             translate(lower(trim(coalesce(n, ''))), 'áéíóúüñ', 'aeiouun'),
             '[^a-z0-9 ]', '', 'g'),
           '\s+', ' ', 'g');
$$;

-- ¿El nombre que escribió corresponde al que tiene el estudio?
-- No se compara palabra por palabra en orden: basta que compartan UNA
-- palabra de 3 letras o más. Así "Ma. Carmen Rodríguez" reconoce a quien
-- escribe "María del Carmen", pero un "Pedro" cualquiera no pasa.
create or replace function nombre_coincide(a text, b text)
returns boolean language sql immutable as $$
  select exists (
    select 1
      from unnest(string_to_array(norm_nombre(a), ' ')) w1
      join unnest(string_to_array(norm_nombre(b), ' ')) w2 on w1 = w2
     where length(w1) >= 3
  );
$$;

-- El día de hoy EN NICARAGUA. Postgres corre en UTC: a partir de las 6pm
-- locales el date de UTC ya cambió, y una clase de hoy se vería "pasada".
create or replace function hoy_ni()
returns date language sql stable as $$
  select (now() at time zone 'America/Managua')::date;
$$;


-- ═══════════════════════════════════════════════════════════════════
--  TABLAS
-- ═══════════════════════════════════════════════════════════════════

create table if not exists alumnas (
  id              uuid primary key default gen_random_uuid(),
  nombre_completo text not null,
  tel             text not null,               -- como lo escribió ella
  email           text,                        -- se completa si tiene ficha
  pin_hash        text,                        -- cifrado con bcrypt, NUNCA en claro
  sub_id          text references suscriptoras(id) on delete set null,
  creada          timestamptz not null default now(),
  ultimo_acceso   timestamptz
);

-- Un acceso por número. Es la razón por la que el usuario es el teléfono
-- y no el nombre: dos alumnas se pueden llamar igual, el número no.
create unique index if not exists alumnas_tel_unico on alumnas (norm_tel(tel));

create table if not exists sesiones_alumna (
  token     uuid primary key default gen_random_uuid(),
  alumna_id uuid not null references alumnas(id) on delete cascade,
  creada    timestamptz not null default now(),
  expira    timestamptz not null default now() + interval '30 days'
);
create index if not exists sesiones_alumna_idx on sesiones_alumna (alumna_id);

-- Sin esto, 3.000 combinaciones de PIN se prueban en minutos.
create table if not exists intentos_login (
  id      bigserial primary key,
  tel     text not null,
  exito   boolean not null,
  momento timestamptz not null default now()
);
create index if not exists intentos_login_idx on intentos_login (tel, momento desc);


-- ═══════════════════════════════════════════════════════════════════
--  PERMISOS · las tablas quedan CERRADAS
--
--  RLS activo y sin una sola policy = la llave anon no puede leer ni
--  escribir nada acá directamente. El único camino son las funciones,
--  que corren como dueño y sí ven las tablas.
-- ═══════════════════════════════════════════════════════════════════
alter table alumnas         enable row level security;
alter table sesiones_alumna enable row level security;
alter table intentos_login  enable row level security;


-- ═══════════════════════════════════════════════════════════════════
--  Se borran antes de recrearlas: `create or replace` falla si cambia el
--  tipo de retorno ("Row type defined by OUT parameters is different"),
--  y sin esto volver a correr el archivo daría error.
-- ═══════════════════════════════════════════════════════════════════
drop function if exists registrar_alumna(text, text, text);
drop function if exists login_alumna(text, text);
drop function if exists mis_clases(uuid);
drop function if exists mi_perfil(uuid);
drop function if exists cambiar_pin(uuid, text, text);
drop function if exists cerrar_sesion(uuid);
drop function if exists cupos_del_dia(date, date);


-- ═══════════════════════════════════════════════════════════════════
--  1. CREAR ACCESO (primera vez)
--
--  Solo puede crearlo quien YA aparece en el estudio: su número tiene que
--  estar en una reserva o en una ficha de suscriptora. Además el primer
--  nombre debe coincidir, para que tener el número de alguien no alcance
--  para reclamar su cuenta.
-- ═══════════════════════════════════════════════════════════════════
create or replace function registrar_alumna(p_tel text, p_nombre text, p_pin text)
returns table (sesion uuid, alumna text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tel      text := norm_tel(p_tel);
  v_registro text;
  v_email    text;
  v_sub      text;
  v_id       uuid;
  v_tok      uuid;
begin
  if length(v_tel) <> 8 then
    raise exception 'Escribe tu número de celular (8 dígitos).' using errcode = 'P0001';
  end if;
  if p_pin !~ '^\d{4}$' then
    raise exception 'El PIN debe ser de 4 dígitos.' using errcode = 'P0001';
  end if;

  select a.id into v_id from alumnas a where norm_tel(a.tel) = v_tel;
  if v_id is not null and (select pin_hash from alumnas where id = v_id) is not null then
    raise exception 'Ya tienes acceso creado con este número. Inicia sesión.' using errcode = 'P0001';
  end if;

  -- ¿Existe en el estudio? Primero ficha de suscriptora, luego reservas.
  select s.nombre, s.email, s.id into v_registro, v_email, v_sub
    from suscriptoras s where norm_tel(s.tel) = v_tel limit 1;

  if v_registro is null then
    select r.nombre, r.email into v_registro, v_email
      from reservas r where norm_tel(r.tel) = v_tel
      order by r.creado desc limit 1;
  end if;

  if v_registro is null then
    raise exception 'No encontramos clases con ese número. Reserva tu primera clase y luego crea tu acceso.'
      using errcode = 'P0001';
  end if;

  -- El nombre tiene que corresponder al que el estudio ya tiene.
  if not nombre_coincide(v_registro, p_nombre) then
    raise exception 'El nombre no coincide con el registrado para ese número.' using errcode = 'P0001';
  end if;

  if v_id is null then
    -- Se guarda el nombre COMPLETO que ya tiene el estudio, no el que ella
    -- escribió: así la cuenta queda enlazada al registro real y no a un
    -- "Mari" suelto que después nadie reconoce en el panel.
    insert into alumnas (nombre_completo, tel, email, pin_hash, sub_id)
    values (v_registro, p_tel, v_email,
            extensions.crypt(p_pin, extensions.gen_salt('bf')), v_sub)
    returning id into v_id;
  else
    update alumnas
       set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf')),
           email    = coalesce(email, v_email),
           sub_id   = coalesce(sub_id, v_sub)
     where id = v_id;
  end if;

  insert into sesiones_alumna (alumna_id) values (v_id) returning token into v_tok;
  update alumnas set ultimo_acceso = now() where id = v_id;

  return query select v_tok, (select nombre_completo from alumnas where id = v_id);
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  2. INICIAR SESIÓN
-- ═══════════════════════════════════════════════════════════════════
--  OJO con el diseño: esta función NO lanza excepción cuando el PIN está
--  mal, devuelve el error como texto. Es a propósito: `raise exception`
--  revierte la transacción, y con ella el `insert` que anota el intento
--  fallido. Los intentos nunca quedaban registrados y el bloqueo por
--  fuerza bruta no llegaba a activarse jamás.
create or replace function login_alumna(p_tel text, p_pin text)
returns table (sesion uuid, alumna text, error text)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tel  text := norm_tel(p_tel);
  v_id   uuid;
  v_hash text;
  v_nom  text;
  v_tok  uuid;
  v_fall int;
begin
  -- Freno de fuerza bruta: 5 fallos en 15 minutos y el número se bloquea.
  select count(*) into v_fall from intentos_login
   where tel = v_tel and not exito and momento > now() - interval '15 minutes';
  if v_fall >= 5 then
    return query select null::uuid, null::text,
                        'Demasiados intentos fallidos. Espera 15 minutos.'::text;
    return;
  end if;

  select a.id, a.pin_hash, a.nombre_completo into v_id, v_hash, v_nom
    from alumnas a where norm_tel(a.tel) = v_tel;

  -- Mismo mensaje para "no existe" y "PIN malo": si fueran distintos, se
  -- podría averiguar qué números están registrados probando uno por uno.
  if v_id is null or v_hash is null
     or v_hash <> extensions.crypt(p_pin, v_hash) then
    insert into intentos_login (tel, exito) values (v_tel, false);
    return query select null::uuid, null::text, 'Número o PIN incorrecto.'::text;
    return;
  end if;

  insert into intentos_login (tel, exito) values (v_tel, true);
  insert into sesiones_alumna (alumna_id) values (v_id) returning token into v_tok;
  update alumnas set ultimo_acceso = now() where id = v_id;

  return query select v_tok, v_nom, null::text;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  3. MIS CLASES  ·  el corazón del asunto
--
--  Devuelve SOLO las reservas de la dueña del token. No recibe ningún
--  filtro de quién: la propia función resuelve la identidad desde la
--  sesión, así que no hay forma de pedir las de otra persona.
-- ═══════════════════════════════════════════════════════════════════
create or replace function mis_clases(p_token uuid)
returns table (
  fecha       date,
  hora        text,
  clase       text,
  instructor  text,
  lugar       int,
  metodo      text,
  pago_ok     boolean,
  estado      text          -- 'proxima' | 'pasada'
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
           case when r.fecha >= hoy_ni() then 'proxima' else 'pasada' end
      from reservas r
     where norm_tel(r.tel) = v_tel
        or (v_email <> '' and lower(coalesce(r.email, '')) = v_email)
     order by r.fecha desc, r.hora desc;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  4. MI PLAN  ·  cuántas clases le quedan y hasta cuándo
-- ═══════════════════════════════════════════════════════════════════
create or replace function mi_perfil(p_token uuid)
returns table (
  nombre           text,
  tel              text,
  plan             text,
  clases_restantes int,
  ilimitado        boolean,
  fecha_vence      date,
  vencido          boolean,
  activa           boolean
)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tel text;
  v_nom text;
begin
  select norm_tel(a.tel), a.nombre_completo into v_tel, v_nom
    from alumnas a
    join sesiones_alumna s on s.alumna_id = a.id
   where s.token = p_token and s.expira > now();

  if v_tel is null then
    raise exception 'Tu sesión expiró. Vuelve a entrar.' using errcode = 'P0001';
  end if;

  return query
    select v_nom, v_tel, su.plan,
           su.clases_restantes,
           su.clases_restantes >= 1000,                    -- convención de ilimitado
           su.fecha_vence,
           (su.fecha_vence is not null and su.fecha_vence < hoy_ni()),
           coalesce(su.activa, false)
      from suscriptoras su
     where norm_tel(su.tel) = v_tel
     limit 1;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  5. CAMBIAR PIN / CERRAR SESIÓN
-- ═══════════════════════════════════════════════════════════════════
create or replace function cambiar_pin(p_token uuid, p_pin_actual text, p_pin_nuevo text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid; v_hash text;
begin
  if p_pin_nuevo !~ '^\d{4}$' then
    raise exception 'El PIN nuevo debe ser de 4 dígitos.' using errcode = 'P0001';
  end if;

  select a.id, a.pin_hash into v_id, v_hash
    from alumnas a join sesiones_alumna s on s.alumna_id = a.id
   where s.token = p_token and s.expira > now();

  if v_id is null then
    raise exception 'Tu sesión expiró. Vuelve a entrar.' using errcode = 'P0001';
  end if;
  if v_hash <> extensions.crypt(p_pin_actual, v_hash) then
    raise exception 'El PIN actual no es correcto.' using errcode = 'P0001';
  end if;

  update alumnas
     set pin_hash = extensions.crypt(p_pin_nuevo, extensions.gen_salt('bf'))
   where id = v_id;

  -- Cierra las demás sesiones: si alguien más había entrado, queda fuera.
  delete from sesiones_alumna where alumna_id = v_id and token <> p_token;
  return true;
end $$;

create or replace function cerrar_sesion(p_token uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  delete from sesiones_alumna where token = p_token;
  return true;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  6. CUPOS DEL DÍA  ·  lo que el sitio público necesita, sin datos personales
--
--  Hoy la página descarga TODAS las reservas (con nombres y teléfonos)
--  solo para pintar "quedan 3 cupos" y saber qué mats están tomados.
--  Esta función entrega exactamente eso y nada más. Es el paso previo
--  para poder cerrar la lectura pública de `reservas`.
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
   group by r.clase, r.fecha, r.hora;
$$;


-- ═══════════════════════════════════════════════════════════════════
--  QUIÉN PUEDE LLAMAR QUÉ
--  Las funciones quedan disponibles para la llave pública; las tablas no.
-- ═══════════════════════════════════════════════════════════════════
do $$
begin
  -- Supabase le da permiso de tabla a anon/authenticated por defecto en el
  -- esquema public. Sin este revoke, lo único que frena la lectura de
  -- `alumnas` (que guarda los PIN cifrados) sería el RLS: si alguien
  -- desactiva RLS o agrega una policy permisiva sin querer, quedaría
  -- expuesta. Con el revoke hacen falta las dos cosas para abrirla.
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on alumnas, sesiones_alumna, intentos_login from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on alumnas, sesiones_alumna, intentos_login from authenticated;
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function registrar_alumna(text, text, text) to anon;
    grant execute on function login_alumna(text, text)           to anon;
    grant execute on function mis_clases(uuid)                   to anon;
    grant execute on function mi_perfil(uuid)                    to anon;
    grant execute on function cambiar_pin(uuid, text, text)      to anon;
    grant execute on function cerrar_sesion(uuid)                to anon;
    grant execute on function cupos_del_dia(date, date)          to anon;
  end if;
end $$;

-- Limpieza de sesiones vencidas (opcional: correr de vez en cuando)
--   delete from sesiones_alumna where expira < now();
