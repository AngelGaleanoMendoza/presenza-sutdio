-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Ajustes manuales de suscriptora
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  Agrega dos columnas a `suscriptoras`. Son para los botones nuevos del
--  panel — 🔓 Reactivar / 🔒 Quitar reactivación y 🗓 Vencimiento — y
--  también quedan usadas por ✏️ Corregir clases y ✏️ Editar datos, que ya
--  existían pero hasta hoy no dejaban ningún rastro de qué se cambió.
--
--  1) ajustes (jsonb) — el historial de correcciones que hace el estudio
--     a mano: reactivar un plan vencido, mover una fecha de vencimiento,
--     corregir el número de clases, editar nombre o celular. Sin esto esas
--     acciones se pueden seguir haciendo igual, solo que no queda registro
--     de quién y por qué — "Ficha completa" no tiene de dónde imprimirlo.
--
--  2) gracia_original_vence (date) — cuando se reactiva un plan vencido
--     "por gracia" (sin cobrar), acá se guarda la fecha de vencimiento
--     real que tenía ANTES de la reactivación. Es lo que permite
--     deshacerla con el botón "Quitar reactivación": vuelve a esa fecha
--     exacta en vez de adivinar. Se borra sola en cuanto la alumna
--     renueva de verdad (con cobro) o alguien corrige la fecha a mano.
--
--  Mientras no se corra esto, los botones nuevos y las correcciones
--  siguen funcionando —la página detecta que faltan las columnas y deja
--  de mandarlas— solo que no queda nada guardado para verlo después.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════

alter table suscriptoras add column if not exists ajustes jsonb not null default '[]'::jsonb;
alter table suscriptoras add column if not exists gracia_original_vence date;


-- ═══════════════════════════════════════════════════════════════════
--  REVISIÓN · que se vea de un vistazo si quedó bien
-- ═══════════════════════════════════════════════════════════════════
select 1 as paso, 'Columna suscriptoras.ajustes' as que,
       case when exists (select 1 from information_schema.columns
                          where table_name = 'suscriptoras' and column_name = 'ajustes')
            then '✅ lista' else '❌ falta' end as estado
union all
select 2, 'Columna suscriptoras.gracia_original_vence',
       case when exists (select 1 from information_schema.columns
                          where table_name = 'suscriptoras' and column_name = 'gracia_original_vence')
            then '✅ lista' else '❌ falta' end
order by paso;
