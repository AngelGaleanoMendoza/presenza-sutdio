-- ═══════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Suscriptoras compartidas entre dispositivos
--  Pegar TODO esto en Supabase → SQL Editor → Run
--  (la tabla `reservas` se creó aparte, con supabase-reservas.sql)
-- ═══════════════════════════════════════════════════════════

create table if not exists suscriptoras (
  email            text primary key,     -- siempre en minúsculas: identifica a la alumna
  id               text,                 -- SUB-XXXXXX (número de suscriptora que ve la alumna)
  nombre           text not null,
  tel              text,
  notas            text,
  plan             text,                 -- singular | plan5 | plan10 | ilimit1 | ilimit3 | ilimit6
  clases_total     int  not null default 0,
  clases_restantes int  not null default 0,
  clases_usadas    int  not null default 0,
  activa           boolean not null default false,
  fecha_inicio     date,
  fecha_vence      date,
  pendiente        jsonb,                -- {plan, fecha} mientras espera tu confirmación de pago
  historial        jsonb not null default '[]',   -- asistencias
  renovaciones     jsonb not null default '[]',
  actualizado      timestamptz not null default now()
);

-- Buscar por teléfono (identificador secundario junto al nombre)
create index if not exists suscriptoras_tel_idx on suscriptoras (tel);

-- ── Permisos ────────────────────────────────────────────────
-- Igual que en reservas: las alumnas solicitan su plan sin iniciar sesión.
-- Ninguna suscripción se activa sola: queda en `pendiente` hasta que la
-- confirmes desde el Super Admin.
alter table suscriptoras enable row level security;

drop policy if exists suscriptoras_select on suscriptoras;
drop policy if exists suscriptoras_insert on suscriptoras;
drop policy if exists suscriptoras_update on suscriptoras;
drop policy if exists suscriptoras_delete on suscriptoras;

create policy suscriptoras_select on suscriptoras for select using (true);
create policy suscriptoras_insert on suscriptoras for insert with check (true);
create policy suscriptoras_update on suscriptoras for update using (true) with check (true);
create policy suscriptoras_delete on suscriptoras for delete using (true);
