-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Horario nuevo (con Milena) + sábado
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  POR QUÉ HACE FALTA CORRERLO
--  El horario vive en dos lados: el del código (index.html) es solo el
--  de fábrica, y la tabla `horarios` es la que manda. Si la tabla tiene
--  filas, cada dispositivo la baja al abrir la página y pisa el del
--  código —incluso el que ya tenga guardada una copia vieja—. Así que
--  cambiar el código no basta: hay que dejar la tabla igual, y con esto
--  todos los teléfonos y la tablet del estudio quedan sincronizados
--  solos la próxima vez que abran el sitio.
--
--  QUÉ DEJA
--  28 clases, de lunes a sábado, exactamente como el horario que pasó
--  Jimena. Milena entra los martes 7:30 pm y viernes 6:30 pm (Barre Burn).
--
--  OJO CON LAS RESERVAS YA HECHAS
--  Esto cambia el horario, no las reservas. Las que ya estén tomadas para
--  clases que cambiaron de hora o de coach siguen guardadas como estaban
--  (por ejemplo una de lunes 6:30 am, que ya no existe). Conviene mirar
--  las reservas de esta semana en el panel antes de correrlo.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════

begin;

delete from horarios;

insert into horarios (dia, clase, hora, instructor, orden) values
  -- Lunes
  (1, 'burn',    '07:30', 'Gladys',    0),
  (1, 'burn',    '08:30', 'Gladys',    1),
  (1, 'pilates', '18:30', 'Jimena',    2),
  (1, 'essenza', '19:30', 'Alejandra', 3),
  -- Martes
  (2, 'essenza', '06:30', 'M. Carmen', 0),
  (2, 'essenza', '07:30', 'M. Carmen', 1),
  (2, 'pilates', '08:30', 'Jimena',    2),
  (2, 'essenza', '17:30', 'M. Carmen', 3),
  (2, 'pilates', '18:30', 'Jimena',    4),
  (2, 'burn',    '19:30', 'Milena',    5),
  -- Miércoles
  (3, 'burn',    '06:30', 'Gladys',    0),
  (3, 'burn',    '07:30', 'Gladys',    1),
  (3, 'essenza', '08:30', 'M. Carmen', 2),
  (3, 'yoga',    '18:30', 'Yeni',      3),
  (3, 'essenza', '19:30', 'Alejandra', 4),
  -- Jueves
  (4, 'essenza', '06:30', 'M. Carmen', 0),
  (4, 'essenza', '07:30', 'M. Carmen', 1),
  (4, 'pilates', '08:30', 'Jimena',    2),
  (4, 'essenza', '17:30', 'M. Carmen', 3),
  (4, 'pilates', '18:30', 'Jimena',    4),
  -- Viernes
  (5, 'burn',    '06:30', 'Alejandra', 0),
  (5, 'burn',    '07:30', 'Alejandra', 1),
  (5, 'burn',    '08:30', 'Gladys',    2),
  (5, 'burn',    '09:30', 'Gladys',    3),
  (5, 'burn',    '18:30', 'Milena',    4),
  -- Sábado
  (6, 'essenza', '08:30', 'M. Carmen', 0),
  (6, 'pilates', '09:30', 'Jimena',    1),
  (6, 'yoga',    '10:30', 'Yeni',      2);

commit;

-- Para confirmar que quedaron las 28:
-- select dia, hora, clase, instructor from horarios order by dia, hora;
