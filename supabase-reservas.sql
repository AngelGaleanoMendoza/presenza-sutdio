-- ═══════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Reservas compartidas entre dispositivos
--  Pegar TODO esto en Supabase → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════

create table if not exists reservas (
  id         bigserial primary key,
  slot_key   text    not null,   -- presenza_pilates_2026-07-29_1030
  clase      text    not null,   -- burn | essenza | pilates | yoga
  fecha      date    not null,
  hora       text    not null,   -- '10:30'
  ts         bigint  not null,   -- identificador de la reserva dentro de su clase
  nombre     text    not null,
  email      text,
  tel        text,
  nivel      text,
  notas      text,
  lugar      int,                -- número de mat (solo Presenza Sculpt)
  metodo     text,               -- 🏦 Transferencia · 💎 Suscripción · 🎁 Clase gratis
  instructor text,
  pago_ok    boolean not null default true,  -- false = transferencia por confirmar
  creado     timestamptz not null default now()
);

-- Un mismo mat no puede reservarse dos veces en la misma clase.
-- Este índice es el que impide que dos alumnas tomen el lugar 5 desde
-- celulares distintos: la segunda inserción es rechazada por la base.
create unique index if not exists reservas_mat_unico
  on reservas (slot_key, lugar) where lugar is not null;

-- Identificador estable de cada reserva (se usa para borrar y confirmar pagos)
create unique index if not exists reservas_ts_unico
  on reservas (slot_key, ts);

create index if not exists reservas_fecha_idx on reservas (fecha);

-- ── Permisos ────────────────────────────────────────────────
-- Las alumnas reservan sin iniciar sesión, así que la tabla queda abierta
-- con la llave pública (anon key). Es la misma decisión que toma cualquier
-- formulario público. El control real está en el Super Admin: ninguna
-- suscripción se activa ni ningún pago se da por bueno sin tu confirmación.
alter table reservas enable row level security;

drop policy if exists reservas_select on reservas;
drop policy if exists reservas_insert on reservas;
drop policy if exists reservas_update on reservas;
drop policy if exists reservas_delete on reservas;

create policy reservas_select on reservas for select using (true);
create policy reservas_insert on reservas for insert with check (true);
create policy reservas_update on reservas for update using (true) with check (true);
create policy reservas_delete on reservas for delete using (true);
