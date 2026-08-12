-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Sacar a las alumnas del mat 3 en Presenza Sculpt
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  En Sculpt el mat 3 pasó a ser el de la instructora, así que ya no se
--  puede reservar. Las alumnas que lo hayan tomado ANTES de ese cambio
--  siguen guardadas ahí: cuentan para el cupo, pero su mat ya no se
--  dibuja en la grilla.
--
--  Esto las mueve al mat siguiente que esté libre en su misma clase
--  (4, 5, 6 … 11 y, si no queda ninguno, 1 o 2).
--
--  Solo toca clases de Sculpt de HOY EN ADELANTE. El historial de clases
--  que ya pasaron se deja intacto: es el registro de lo que ocurrió.
--
--  Es seguro correrlo más de una vez: la segunda vez no encuentra nada
--  que mover y no hace nada.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  1. ANTES · quiénes están en el mat 3 y a dónde irían
--
--  Esta consulta NO cambia nada, solo muestra. Si sale vacía, no hay
--  nada que reubicar y ya terminaste.
-- ═══════════════════════════════════════════════════════════════════
with en_mat3 as (
  select id, slot_key, fecha, hora, nombre, email
    from reservas
   where clase = 'pilates' and lugar = 3 and fecha >= hoy_ni()
),
destino as (
  select m.id, m.fecha, m.hora, m.nombre, m.email,
         -- El primero libre siguiendo el orden 4,5,…,11 y después 1,2
         (select t.n from unnest(array[4,5,6,7,8,9,10,11,1,2]) with ordinality as t(n, ord)
           where not exists (select 1 from reservas r
                              where r.slot_key = m.slot_key and r.lugar = t.n)
           order by t.ord limit 1) as mat_nuevo
    from en_mat3 m
)
select fecha, hora, nombre, coalesce(email,'—') as email,
       3 as mat_actual,
       coalesce(mat_nuevo::text, '⚠️ clase llena, no se mueve') as mat_nuevo
  from destino
 order by fecha, hora;


-- ═══════════════════════════════════════════════════════════════════
--  2. MOVERLAS
--
--  Se hace una por una y en orden de fecha, así dos alumnas de la misma
--  clase nunca terminan peleando el mismo mat: cada vez se vuelve a ver
--  qué quedó libre. Si una clase estuviera tan llena que no hay ningún
--  mat disponible, esa se deja donde está y aparece en el paso 3.
-- ═══════════════════════════════════════════════════════════════════
do $$
declare
  r        record;
  v_nuevo  int;
  v_movidas int := 0;
begin
  for r in
    select id, slot_key, fecha, hora, nombre
      from reservas
     where clase = 'pilates' and lugar = 3 and fecha >= hoy_ni()
     order by fecha, hora, id
  loop
    select t.n into v_nuevo
      from unnest(array[4,5,6,7,8,9,10,11,1,2]) with ordinality as t(n, ord)
     where not exists (select 1 from reservas x
                        where x.slot_key = r.slot_key and x.lugar = t.n)
     order by t.ord
     limit 1;

    if v_nuevo is null then
      raise notice 'SIN CUPO · % % · % se queda en el mat 3', r.fecha, r.hora, r.nombre;
    else
      update reservas set lugar = v_nuevo where id = r.id;
      v_movidas := v_movidas + 1;
      raise notice 'MOVIDA · % % · % : mat 3 → mat %', r.fecha, r.hora, r.nombre, v_nuevo;
    end if;
  end loop;

  raise notice '───────────── % reserva(s) reubicada(s) ─────────────', v_movidas;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  3. DESPUÉS · comprobación
--
--  Lee la columna "qué significa" de cada fila. Las dos últimas pueden
--  dar distinto de cero sin que nada esté roto: son avisos, no errores.
-- ═══════════════════════════════════════════════════════════════════
select 1 as n,
       'Sculpt futuros que siguen en el mat 3' as revision,
       count(*)::text as resultado,
       case when count(*) = 0 then '✓ listo, ninguna quedó en el mat de la coach'
            else '⚠️ esas clases no tenían ningún mat libre. Muévelas de '
                 || 'horario a mano desde el panel o libera un cupo.' end as que_significa
  from reservas
 where clase = 'pilates' and lugar = 3 and fecha >= hoy_ni()

union all
select 2, 'Sculpt futuros sin mat asignado',
       count(*)::text,
       case when count(*) = 0 then '✓ todas tienen su mat'
            else '⚠️ agéndalas de nuevo desde el panel para darles mat' end
  from reservas
 where clase = 'pilates' and fecha >= hoy_ni() and lugar is null

union all
select 3, 'Clases de Sculpt con más de 10 inscritas',
       count(*)::text,
       case when count(*) = 0 then '✓ ninguna pasa del cupo nuevo'
            else 'Se llenaron cuando Sculpt tenía 11 cupos. Nadie pierde su '
                 || 'lugar: el panel las va a mostrar como 11/10 hasta que pasen.' end
  from (select slot_key from reservas
         where clase = 'pilates' and fecha >= hoy_ni()
         group by slot_key having count(*) > 10) t

union all
select 4, 'Sculpt futuros en total', count(*)::text, 'Solo de referencia'
  from reservas
 where clase = 'pilates' and fecha >= hoy_ni()

 order by n;
