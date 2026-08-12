-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Que el link de una clase libre vuelva a ser secreto
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  EL PROBLEMA
--  En clases_especiales, el campo `id` NO es un número cualquiera: es el
--  token del link único (presenzastudioni.com/#naytn5h25g). Quien lo tiene,
--  entra. Por eso se genera al azar con crypto, para que nadie lo adivine.
--
--  Pero la tabla estaba abierta al público, así que cualquiera podía leer
--  de un solo golpe los tokens de TODAS las clases libres activas —desde
--  "Inspeccionar" en el navegador, o pidiéndole la tabla a la base con la
--  llave que está a la vista en el código— y meterse a una clase gratis
--  pensada para un grupo puntual. La cerradura estaba bien; lo que fallaba
--  es que la llave estaba publicada al lado.
--
--  LA SOLUCIÓN, la misma que ya usan los cupos y las suscripciones:
--  la tabla se cierra al público y se abre una sola puerta angosta, que
--  recibe UN token y devuelve UNA clase. Sin token no hay respuesta, y
--  adivinarlo es inviable (10 caracteres de un alfabeto de 32).
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  1. LA PUERTA ANGOSTA
--
--  security definer: corre con los permisos del dueño, así puede leer la
--  tabla aunque el público ya no pueda. Devuelve solo la fila cuyo id sea
--  EXACTAMENTE el token pedido. No hay comodines ni búsquedas parciales:
--  no se puede pedir "todas las que empiecen con a".
--
--  Devuelve también las clases que ya pasaron: así la página puede decir
--  "esta clase gratis ya pasó" en vez de un "link inválido" confuso.
-- ═══════════════════════════════════════════════════════════════════
drop function if exists clase_especial_por_token(text);

create or replace function clase_especial_por_token(p_id text)
returns table (
  id text, clase text, fecha date, hora text,
  instructor text, cupos int, precio int, titulo text
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.clase, e.fecha, e.hora, e.instructor, e.cupos, e.precio, e.titulo
    from clases_especiales e
   where e.activa is true
     and e.id = p_id
     -- Un token de verdad tiene 10 caracteres. Esto corta de raíz que
     -- alguien pruebe con '' o con un id corto puesto a mano.
     and length(p_id) >= 8;
$$;

comment on function clase_especial_por_token(text) is
  'Devuelve UNA clase libre a partir del token de su link. Es la única vía '
  'del público a clases_especiales: la tabla completa exige sesión.';

-- Que la puedan llamar el público y el estudio. `authenticated` también,
-- porque si Jimena abre el link estando logueada, la llamada va con SU
-- sesión y sin este permiso le fallaría solo a ella.
do $$
declare r text;
begin
  revoke all on function clase_especial_por_token(text) from public;
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function clase_especial_por_token(text) to %I', r);
    end if;
  end loop;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  2. CERRAR LA TABLA AL PÚBLICO
--
--  Leer la lista completa pasa a exigir sesión: el panel la sigue viendo
--  entera, el público ya no. Los permisos de escribir (crear, editar y
--  desactivar clases libres) ya exigían sesión y no se tocan.
-- ═══════════════════════════════════════════════════════════════════
alter table clases_especiales enable row level security;

drop policy if exists clases_especiales_select on clases_especiales;
create policy clases_especiales_select on clases_especiales for select
  using (auth.role() = 'authenticated');

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    -- Se le quita el select. La función de arriba es su única entrada.
    revoke select on clases_especiales from anon;
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete on clases_especiales to authenticated;
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  3. CHEQUEO FINAL · esto es lo que vas a ver al darle Run.
--     Las cuatro filas deben salir con ✓.
-- ═══════════════════════════════════════════════════════════════════
select 1 as n,
       'La puerta angosta existe' as revision,
       case when to_regprocedure('clase_especial_por_token(text)') is not null
            then '✓ sí' else '✗ NO — algo falló arriba' end as resultado

union all
select 2, 'El público YA NO puede leer la tabla completa',
       case when has_table_privilege('anon', 'clases_especiales', 'select')
            then '✗ TODAVÍA PUEDE — revisá que el rol anon exista'
            else '✓ cerrada' end
 where exists (select 1 from pg_roles where rolname = 'anon')

union all
select 3, 'El público SÍ puede usar la puerta angosta',
       case when has_function_privilege('anon', 'clase_especial_por_token(text)', 'execute')
            then '✓ sí' else '✗ NO — los links no van a abrir' end
 where exists (select 1 from pg_roles where rolname = 'anon')

union all
select 4, 'El estudio sigue viendo la lista completa',
       case when has_table_privilege('authenticated', 'clases_especiales', 'select')
            then '✓ sí' else '✗ NO — el panel no va a ver las clases libres' end
 where exists (select 1 from pg_roles where rolname = 'authenticated')

 order by n;
