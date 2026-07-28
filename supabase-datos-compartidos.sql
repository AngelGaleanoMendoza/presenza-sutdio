-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Datos compartidos entre dispositivos (parte 2)
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  La parte 1 (supabase-reservas.sql) ya movió las RESERVAS a la nube.
--  Esto mueve lo que todavía vive en el localStorage de cada celular:
--
--    suscriptoras       membresías, clases restantes, pagos pendientes
--    asistencias        quién asistió a cada clase (descuenta clases)
--    clases_especiales  clases de un día con link único (la clase gratis)
--    horarios           el horario semanal editable desde el admin
--    eventos            Open House, paquete cumpleaños, etc.
--
--  Es seguro correrlo más de una vez: todo usa "if not exists" y las
--  siembras no duplican filas.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  1. SUSCRIPTORAS  (membresías)
--
--  Hoy cada teléfono guarda su propia lista, así que una membresía
--  activada desde un celular no existe para los demás. Con esta tabla
--  la membresía es una sola, la vean desde donde la vean.
-- ═══════════════════════════════════════════════════════════════════
create table if not exists suscriptoras (
  id                text primary key,          -- SUB-XXXXXX, el que ya genera la app
  nombre            text    not null,
  email             text    not null,
  tel               text,
  notas             text,                      -- el campo "nivel" del formulario

  -- Plan vigente. Códigos: singular · plan5 · plan10 · ilimit1 · ilimit3 · ilimit6
  plan              text,
  clases_total      int     not null default 0,
  clases_restantes  int     not null default 0 check (clases_restantes >= 0),
  clases_usadas     int     not null default 0 check (clases_usadas    >= 0),
  activa            boolean not null default false,
  fecha_inicio      date,
  fecha_vence       date,

  -- Plan solicitado que todavía espera confirmación de pago del estudio.
  -- Mientras pendiente_plan no sea null, la membresía NO da clases.
  pendiente_plan    text,
  pendiente_fecha   date,

  -- [{ fecha, clase, hora, ts }]  · una entrada por asistencia registrada
  historial         jsonb   not null default '[]'::jsonb,
  -- [{ fecha, plan, clases }]     · una entrada por alta o renovación
  renovaciones      jsonb   not null default '[]'::jsonb,

  creado            timestamptz not null default now(),
  actualizado       timestamptz not null default now()
);

comment on column suscriptoras.clases_restantes is
  'Los planes ilimitados usan 1000 como convención (la app muestra ∞ y no descuenta).';

-- Anti-duplicados, el mismo criterio que ya aplica la app: primero por
-- correo y, si no hay, por teléfono normalizado a puros dígitos.
create unique index if not exists suscriptoras_email_unico
  on suscriptoras (lower(email));

create unique index if not exists suscriptoras_tel_unico
  on suscriptoras (regexp_replace(coalesce(tel,''), '\D', '', 'g'))
  where length(regexp_replace(coalesce(tel,''), '\D', '', 'g')) >= 8;

create index if not exists suscriptoras_activa_idx on suscriptoras (activa);
create index if not exists suscriptoras_vence_idx  on suscriptoras (fecha_vence);

-- Mantiene "actualizado" al día sin que la app tenga que acordarse.
create or replace function tocar_actualizado() returns trigger
  language plpgsql as $$
begin
  new.actualizado = now();
  return new;
end $$;

drop trigger if exists suscriptoras_tocar on suscriptoras;
create trigger suscriptoras_tocar before update on suscriptoras
  for each row execute function tocar_actualizado();


-- ═══════════════════════════════════════════════════════════════════
--  2. ASISTENCIAS
--
--  Reemplaza las claves pras_* del localStorage. Es lo que hace que el
--  botón "Marcar ✓" no se pueda apretar dos veces y que la clase se
--  descuente una sola vez, aunque se marque desde otro teléfono.
-- ═══════════════════════════════════════════════════════════════════
create table if not exists asistencias (
  id      bigserial primary key,
  clase   text   not null,
  fecha   date   not null,
  hora    text   not null,               -- '18:30'
  email   text   not null,
  sub_id  text   references suscriptoras(id) on delete set null,
  creado  timestamptz not null default now()
);

-- Una asistencia por alumna y clase: la segunda marca la rechaza la base.
create unique index if not exists asistencias_unica
  on asistencias (clase, fecha, hora, lower(email));

create index if not exists asistencias_fecha_idx on asistencias (fecha);
create index if not exists asistencias_sub_idx   on asistencias (sub_id);


-- ═══════════════════════════════════════════════════════════════════
--  3. CLASES_ESPECIALES  (clases de un día con link único)
--
--  Hoy la clase gratis está escrita dentro del index.html, así que
--  cambiarle la fecha o cerrarla obliga a publicar el sitio de nuevo.
--  Acá se administra sin tocar código.
--
--  OJO con el id: es el token del link (presenzastudioni.com/#<id>).
--  Quien lo tiene, entra. Ver la nota de seguridad al final del archivo.
-- ═══════════════════════════════════════════════════════════════════
create table if not exists clases_especiales (
  id          text primary key,                 -- token del link único
  clase       text    not null,                 -- burn | essenza | pilates | yoga
  fecha       date    not null,
  hora        text    not null,
  instructor  text,
  cupos       int     not null default 11 check (cupos > 0),
  precio      int     not null default 0  check (precio >= 0),  -- 0 = gratis
  titulo      text,
  activa      boolean not null default true,    -- en false, el link deja de servir
  creado      timestamptz not null default now()
);

-- No puede haber dos especiales en la misma clase, día y hora.
create unique index if not exists clases_especiales_slot
  on clases_especiales (clase, fecha, hora);

create index if not exists clases_especiales_fecha_idx on clases_especiales (fecha);

-- Siembra la clase gratis que ya está publicada, con su token actual.
insert into clases_especiales (id, clase, fecha, hora, instructor, cupos, precio, titulo)
values ('naytn5h25g', 'pilates', '2026-07-29', '10:30', 'Jimena', 11, 0,
        'Clase gratis · Presenza Sculpt')
on conflict (id) do nothing;


-- ═══════════════════════════════════════════════════════════════════
--  4. HORARIOS  (el horario semanal)
--
--  El admin ya puede editarlo, pero el cambio se queda en ese teléfono.
--  Acá el horario es uno solo para todos.
-- ═══════════════════════════════════════════════════════════════════
create table if not exists horarios (
  id          bigserial primary key,
  dia         int  not null check (dia between 0 and 6),  -- 0=Dom, 1=Lun … 6=Sáb
  clase       text not null,
  hora        text not null,
  instructor  text,
  orden       int  not null default 0            -- posición dentro del día
);

create unique index if not exists horarios_unico on horarios (dia, clase, hora);
create index        if not exists horarios_dia_idx on horarios (dia, orden);

-- Siembra el horario que hoy está en el código (29 clases, Lun a Vie).
insert into horarios (dia, clase, hora, instructor, orden) values
  (1, 'burn', '06:30', 'Alejandra', 0),
  (1, 'burn', '07:30', 'Alejandra', 1),
  (1, 'essenza', '08:30', 'M. Carmen', 2),
  (1, 'essenza', '17:30', 'Jimena', 3),
  (1, 'burn', '18:30', 'Jimena', 4),
  (1, 'burn', '19:30', 'Jimena', 5),
  (2, 'essenza', '06:30', 'Jimena', 0),
  (2, 'burn', '07:30', 'Jimena', 1),
  (2, 'essenza', '08:30', 'M. Carmen', 2),
  (2, 'essenza', '17:30', 'M. Carmen', 3),
  (2, 'pilates', '18:30', 'Jimena', 4),
  (2, 'burn', '19:30', 'Alejandra', 5),
  (3, 'burn', '06:30', 'Jimena', 0),
  (3, 'essenza', '07:30', 'M. Carmen', 1),
  (3, 'essenza', '08:30', 'M. Carmen', 2),
  (3, 'burn', '09:30', 'Jimena', 3),
  (3, 'burn', '17:30', 'Jimena', 4),
  (3, 'yoga', '18:30', 'Yeni', 5),
  (3, 'burn', '19:30', 'Alejandra', 6),
  (4, 'burn', '06:30', 'Jimena', 0),
  (4, 'essenza', '07:30', 'M. Carmen', 1),
  (4, 'essenza', '08:30', 'M. Carmen', 2),
  (4, 'yoga', '17:00', 'Yeni', 3),
  (4, 'pilates', '18:30', 'Jimena', 4),
  (4, 'burn', '19:30', 'Alejandra', 5),
  (5, 'burn', '06:30', 'Alejandra', 0),
  (5, 'essenza', '07:30', 'Jimena', 1),
  (5, 'essenza', '08:30', 'M. Carmen', 2),
  (5, 'burn', '17:30', 'Jimena', 3)
on conflict (dia, clase, hora) do nothing;


-- ═══════════════════════════════════════════════════════════════════
--  5. EVENTOS  (Open House, paquete cumpleaños…)
-- ═══════════════════════════════════════════════════════════════════
create table if not exists eventos (
  id      bigserial primary key,
  titulo  text not null,
  emoji   text,
  tipo    text,                       -- 'cumple' para el paquete de cumpleaños
  fecha   date,
  hora    text,                       -- puede ser texto libre: 'A coordinar'
  precio  int  not null default 0,
  cupos   int,
  descr   text,
  activo  boolean not null default true,
  orden   int  not null default 0,
  creado  timestamptz not null default now()
);

create index if not exists eventos_activo_idx on eventos (activo, orden);


-- ═══════════════════════════════════════════════════════════════════
--  PERMISOS (RLS)
--
--  Se sigue el mismo criterio que ya tiene la tabla `reservas`: la app
--  no tiene inicio de sesión, todo entra con la llave pública (anon),
--  así que las tablas quedan abiertas para que el sitio funcione.
--
--  ⚠️ LEER LA NOTA DE SEGURIDAD AL FINAL antes de dar esto por cerrado.
-- ═══════════════════════════════════════════════════════════════════
alter table suscriptoras      enable row level security;
alter table asistencias       enable row level security;
alter table clases_especiales enable row level security;
alter table horarios          enable row level security;
alter table eventos           enable row level security;

-- suscriptoras
drop policy if exists suscriptoras_select on suscriptoras;
drop policy if exists suscriptoras_insert on suscriptoras;
drop policy if exists suscriptoras_update on suscriptoras;
drop policy if exists suscriptoras_delete on suscriptoras;
create policy suscriptoras_select on suscriptoras for select using (true);
create policy suscriptoras_insert on suscriptoras for insert with check (true);
create policy suscriptoras_update on suscriptoras for update using (true) with check (true);
create policy suscriptoras_delete on suscriptoras for delete using (true);

-- asistencias
drop policy if exists asistencias_select on asistencias;
drop policy if exists asistencias_insert on asistencias;
drop policy if exists asistencias_delete on asistencias;
create policy asistencias_select on asistencias for select using (true);
create policy asistencias_insert on asistencias for insert with check (true);
create policy asistencias_delete on asistencias for delete using (true);

-- clases_especiales
drop policy if exists clases_especiales_select on clases_especiales;
drop policy if exists clases_especiales_insert on clases_especiales;
drop policy if exists clases_especiales_update on clases_especiales;
drop policy if exists clases_especiales_delete on clases_especiales;
create policy clases_especiales_select on clases_especiales for select using (true);
create policy clases_especiales_insert on clases_especiales for insert with check (true);
create policy clases_especiales_update on clases_especiales for update using (true) with check (true);
create policy clases_especiales_delete on clases_especiales for delete using (true);

-- horarios
drop policy if exists horarios_select on horarios;
drop policy if exists horarios_write  on horarios;
create policy horarios_select on horarios for select using (true);
create policy horarios_write  on horarios for all using (true) with check (true);

-- eventos
drop policy if exists eventos_select on eventos;
drop policy if exists eventos_write  on eventos;
create policy eventos_select on eventos for select using (true);
create policy eventos_write  on eventos for all using (true) with check (true);


-- ═══════════════════════════════════════════════════════════════════
--  ⚠️ NOTA DE SEGURIDAD — leer antes de cargar datos reales
--
--  La llave anon está a la vista en el código de la página (cualquiera
--  puede verla con "ver código fuente"). Con las políticas de arriba,
--  esa llave permite LEER TODAS LAS FILAS de estas tablas, incluyendo
--  las de `reservas`. En la práctica eso significa que los nombres,
--  correos y teléfonos de las alumnas —y en `suscriptoras`, además su
--  plan y estado de pago— quedan accesibles para quien sepa buscarlos.
--
--  Esto NO es un error de este archivo: es la consecuencia de que la
--  app no tenga inicio de sesión y de que el Super Admin sea una clave
--  revisada en el navegador. Se documenta acá para que sea una decisión
--  tomada a conciencia y no una sorpresa.
--
--  Para cerrarlo hace falta Supabase Auth: el estudio inicia sesión de
--  verdad, las políticas de lectura pasan a exigir un usuario
--  autenticado, y lo único que queda abierto al público es insertar
--  una reserva. Es un cambio de tamaño mediano y toca el index.html.
--  Decime y lo armo.
-- ═══════════════════════════════════════════════════════════════════
