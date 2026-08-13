-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Marcar quién NO llegó a clase
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  Hasta ahora la tabla `asistencias` solo podía guardar una cosa: que
--  la alumna sí llegó. Si no llegaba, la fila simplemente no existía, y
--  eso se confunde con "todavía no le pasaron lista".
--
--  Con esta columna la fila pasa a decir cuál de las dos cosas fue:
--
--    asistio = true    llegó a la clase           (lo de siempre)
--    asistio = false   estaba inscrita y no llegó (lo nuevo)
--    sin fila          nadie le pasó lista todavía
--
--  OJO, lo importante: esto NO toca el saldo de nadie. Las clases se
--  descuentan AL RESERVAR, no al pasar lista, así que marcar "no llegó"
--  no le quita ni le devuelve nada a su paquete: queda igual que estaba,
--  con su plan activo y sus clases donde estaban. Solo deja el registro.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════

-- Las filas que ya existen son todas asistencias de verdad (antes no
-- había otra opción), así que el default true las deja bien sin tocarlas.
alter table asistencias
  add column if not exists asistio boolean not null default true;

comment on column asistencias.asistio is
  'true = llegó · false = estaba inscrita y no llegó. No afecta el saldo de '
  'clases: el descuento ocurre al reservar, no al pasar lista.';

-- Para contar rápido las inasistencias de un rango de fechas.
create index if not exists asistencias_asistio_idx
  on asistencias (asistio, fecha);


-- ═══════════════════════════════════════════════════════════════════
--  CHEQUEO · las tres filas deben salir con ✓
-- ═══════════════════════════════════════════════════════════════════
select 1 as n,
       'La columna asistio existe' as revision,
       case when exists (
              select 1 from information_schema.columns
               where table_name = 'asistencias' and column_name = 'asistio')
            then '✓ sí' else '✗ NO — algo falló arriba' end as resultado

union all
select 2, 'Las asistencias que ya estaban quedaron como "llegó"',
       case when not exists (select 1 from asistencias where asistio is not true)
            then '✓ sí, las ' || (select count(*) from asistencias)::text || ' que había'
            else '— ya hay ' || (select count(*) from asistencias where asistio is false)::text
                 || ' marcada(s) como que no llegó' end

union all
select 3, 'El estudio puede escribir la columna',
       case when has_column_privilege('authenticated', 'asistencias', 'asistio', 'insert')
            then '✓ sí' else '✗ NO — corré supabase-reparacion-total.sql' end
 where exists (select 1 from pg_roles where rolname = 'authenticated')

 order by n;
