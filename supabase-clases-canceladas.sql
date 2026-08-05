-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Cancelar una clase en una fecha puntual
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  QUÉ RESUELVE
--  Si un miércoles no se puede dar Presenza Sculpt, hoy hay que borrarla
--  del horario semanal… y entonces desaparece TODOS los miércoles.
--
--  Esta tabla marca una sesión suelta como cancelada: esa clase deja de
--  aparecer solo ese día. El horario semanal queda intacto y la semana
--  siguiente vuelve a estar disponible.
--
--  Es el espejo de `clases_especiales`: aquella AGREGA una clase suelta,
--  esta QUITA una.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists clases_canceladas (
  id     bigserial primary key,
  clase  text not null,               -- burn | essenza | pilates | yoga
  fecha  date not null,
  hora   text not null,               -- '18:30'
  motivo text,                        -- opcional, para saber por qué
  creada timestamptz not null default now()
);

-- Una sesión no se puede cancelar dos veces.
create unique index if not exists clases_canceladas_slot
  on clases_canceladas (clase, fecha, hora);

create index if not exists clases_canceladas_fecha_idx
  on clases_canceladas (fecha);

-- Mismo criterio que el resto de las tablas del sitio.
alter table clases_canceladas enable row level security;

drop policy if exists clases_canceladas_select on clases_canceladas;
drop policy if exists clases_canceladas_write  on clases_canceladas;
create policy clases_canceladas_select on clases_canceladas for select using (true);
create policy clases_canceladas_write  on clases_canceladas for all    using (true) with check (true);
