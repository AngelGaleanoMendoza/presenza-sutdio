-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Descuento de clases al momento de reservar
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  Antes la clase se descontaba cuando marcabas "✓ Asistió". Ahora se
--  descuenta al reservar, así que hay que recordar CUÁLES reservas ya
--  cobraron una clase — si no, al eliminar una reserva no se sabría si
--  hay que devolverle la clase a la alumna o no.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════

alter table reservas
  add column if not exists clase_descontada boolean not null default false;

comment on column reservas.clase_descontada is
  'true = esta reserva ya consumió una clase del paquete de la alumna. Al '
  'eliminarla o rechazarla, se le devuelve. Las ilimitadas y los pagos por '
  'transferencia o clase única siempre quedan en false.';

-- Para encontrar rápido lo que consumió cada alumna
create index if not exists reservas_descuento_idx
  on reservas (email, clase_descontada) where clase_descontada;


-- ═══════════════════════════════════════════════════════════════════
--  Teléfono: mismo criterio que la app
--
--  Nicaragua usa 8 dígitos, pero cada quien lo escribe distinto:
--  8431 7983 · +505 8431-7983 · 00505 84317983. El índice anterior
--  comparaba los dígitos tal cual, así que la misma alumna con su número
--  escrito de dos formas podía crear DOS registros y quedarse sin plan.
-- ═══════════════════════════════════════════════════════════════════

create or replace function tel_local(t text) returns text
language sql immutable as $$
  with d as (select ltrim(regexp_replace(coalesce(t,''), '\D', '', 'g'), '0') as n)
  select case when length(n) > 8 and n like '505%' then substr(n, 4) else n end from d
$$;

drop index if exists suscriptoras_tel_unico;
create unique index suscriptoras_tel_unico
  on suscriptoras (tel_local(tel))
  where length(tel_local(tel)) >= 8;
