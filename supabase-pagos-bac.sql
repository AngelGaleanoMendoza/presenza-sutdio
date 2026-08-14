-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Preparar el terreno para los links de pago BAC
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  QUÉ PROBLEMA RESUELVE
--  Hoy una solicitud de plan solo tiene dos estados posibles: existe
--  (pendiente) o no existe (ya la confirmaste a mano en el panel). Eso
--  alcanzaba mientras el pago se coordinaba entero por WhatsApp.
--
--  Con un link de pago aparece un tercer estado que hoy no se puede
--  guardar en ningún lado: "la alumna ya pasó por la pantalla de pago y
--  dice que pagó, pero nadie lo verificó todavía". Es distinto de las
--  otras dos y merece verse distinto en el panel.
--
--  LO QUE HACE ESTE ARCHIVO
--    pendiente_estado   espera · dice_pago · verificado
--    pendiente_ref      el número de referencia que devuelve el banco
--    marcar_pago_dicho  la puerta que usa la página al volver del pago
--
--  LA REGLA DE SEGURIDAD, que es lo importante de todo esto:
--  marcar_pago_dicho() NO activa ningún plan, NO suma clases y NO toca
--  saldos. Lo único que hace es mover una etiqueta. Aunque alguien llame
--  esa función a mano mil veces desde la consola del navegador, no se
--  regala ni una clase: sigue haciendo falta que el estudio confirme.
--  Un navegador nunca es prueba de que un pago ocurrió.
--
--  La puerta que SÍ activa el plan automáticamente no está en este
--  archivo a propósito: se escribe junto con el puente que lea las
--  confirmaciones reales de BAC, cuando sepamos qué manda BAC y en qué
--  formato. Escribirla antes sería adivinar.
--
--  Necesita que ya se haya corrido supabase-reparacion-total.sql: de ahí
--  sale norm_tel(), que es lo que hace que "+505 8431-7983" y "84317983"
--  se reconozcan como el mismo teléfono.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  1. LOS DOS CAMPOS NUEVOS
--
--  Las solicitudes que ya existen quedan en 'espera', que es exactamente
--  lo que son: pidieron plan y todavía nadie confirmó el pago.
-- ═══════════════════════════════════════════════════════════════════
alter table suscriptoras
  add column if not exists pendiente_estado text not null default 'espera';

alter table suscriptoras
  add column if not exists pendiente_ref text;

comment on column suscriptoras.pendiente_estado is
  'espera = pidió el plan y no ha pagado · dice_pago = volvió de la pantalla '
  'de pago pero NADIE lo verificó · verificado = el pago está confirmado. '
  'Solo el estudio (o el puente con BAC) puede poner verificado.';

comment on column suscriptoras.pendiente_ref is
  'Número de referencia del banco, para poder cuadrar el pago después.';

-- Que no se cuele un estado escrito a mano con un typo.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'suscriptoras_pendiente_estado_ok') then
    alter table suscriptoras
      add constraint suscriptoras_pendiente_estado_ok
      check (pendiente_estado in ('espera', 'dice_pago', 'verificado'));
  end if;
end $$;

-- Para que el panel encuentre rápido lo que está esperando revisión.
create index if not exists suscriptoras_pendiente_estado_idx
  on suscriptoras (pendiente_estado)
  where pendiente_plan is not null;


-- ═══════════════════════════════════════════════════════════════════
--  2. EL ESTADO SE REINICIA SOLO AL PEDIR OTRO PLAN
--
--  Si una alumna pidió el paquete de 5, dijo que pagó, y después cambia
--  de opinión y pide el de 10, el "dice_pago" del anterior no se puede
--  quedar pegado: se estaría arrastrando el aviso de un pago que era por
--  otro monto.
--
--  Va como trigger y no dentro de solicitar_plan_publico() a propósito:
--  así vale para TODOS los que escriben esa columna —el panel, la función
--  pública, o una corrida futura de supabase-reparacion-total.sql, que
--  vuelve a crear solicitar_plan_publico() y borraría el arreglo si
--  estuviera ahí adentro.
-- ═══════════════════════════════════════════════════════════════════
create or replace function pendiente_estado_reset() returns trigger
language plpgsql as $$
begin
  if new.pendiente_plan is distinct from old.pendiente_plan then
    new.pendiente_estado := 'espera';
    new.pendiente_ref    := null;
  end if;
  return new;
end $$;

drop trigger if exists suscriptoras_pendiente_reset on suscriptoras;
create trigger suscriptoras_pendiente_reset
  before update on suscriptoras
  for each row execute function pendiente_estado_reset();


-- ═══════════════════════════════════════════════════════════════════
--  3. LA PUERTA ANGOSTA · "volví de pagar"
--
--  La llama la página cuando la alumna regresa del link de pago. Busca
--  su solicitud por correo o por teléfono y le cambia la etiqueta.
--
--  Lo que NO puede hacer, por cómo está escrita:
--    · crear una suscriptora que no existía
--    · activar un plan (no toca activa)
--    · sumar clases (no toca clases_restantes ni clases_total)
--    · pasar algo a 'verificado'
--    · tocar una solicitud que el estudio ya verificó
--
--  O sea: el peor abuso posible es que aparezca en el panel un "dice que
--  pagó" de alguien que no pagó. Eso lo agarra la verificación, que es
--  justamente el paso que sigue existiendo.
-- ═══════════════════════════════════════════════════════════════════
drop function if exists marcar_pago_dicho(text, text, text);

create or replace function marcar_pago_dicho(
  p_email text, p_tel text, p_ref text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_em text := trim(lower(coalesce(p_email, '')));
begin
  -- Igual que solicitar_plan_publico: primero por correo, después por
  -- teléfono normalizado, que es como la gente se identifica de verdad.
  select id into v_id from suscriptoras
   where lower(email) = v_em and v_em <> '' and pendiente_plan is not null
   limit 1;

  if v_id is null and length(norm_tel(p_tel)) >= 8 then
    select id into v_id from suscriptoras
     where norm_tel(tel) = norm_tel(p_tel) and pendiente_plan is not null
     limit 1;
  end if;

  if v_id is null then return false; end if;

  update suscriptoras
     set pendiente_estado = 'dice_pago',
         -- Se guarda como pista para cuadrar después, recortada: viene de
         -- un navegador, así que no se le cree el largo ni el contenido.
         pendiente_ref    = nullif(left(trim(coalesce(p_ref, '')), 40), '')
   where id = v_id
     -- Lo ya verificado no se puede "des-verificar" desde la web.
     and pendiente_estado = 'espera';

  return found;
end $$;

comment on function marcar_pago_dicho(text, text, text) is
  'Marca que la alumna volvió de la pantalla de pago. NO activa planes ni '
  'suma clases: solo cambia la etiqueta para que el panel lo muestre aparte.';

do $$
declare r text;
begin
  revoke all on function marcar_pago_dicho(text, text, text) from public;
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function marcar_pago_dicho(text, text, text) to %I', r);
    end if;
  end loop;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  4. CHEQUEO · las cinco filas deben salir con ✓
-- ═══════════════════════════════════════════════════════════════════
select 1 as n,
       'Las columnas nuevas existen' as revision,
       case when (select count(*) from information_schema.columns
                   where table_name = 'suscriptoras'
                     and column_name in ('pendiente_estado', 'pendiente_ref')) = 2
            then '✓ sí' else '✗ NO — algo falló arriba' end as resultado

union all
select 2, 'Las solicitudes que ya estaban quedaron en espera',
       case when not exists (select 1 from suscriptoras
                              where pendiente_plan is not null
                                and pendiente_estado <> 'espera')
            then '✓ sí, las ' || (select count(*) from suscriptoras
                                   where pendiente_plan is not null)::text || ' que había'
            else '— ya hay ' || (select count(*) from suscriptoras
                                  where pendiente_plan is not null
                                    and pendiente_estado <> 'espera')::text
                 || ' con pago dicho o verificado' end

union all
select 3, 'El reinicio automático está puesto',
       case when exists (select 1 from pg_trigger
                          where tgname = 'suscriptoras_pendiente_reset')
            then '✓ sí' else '✗ NO — el estado se va a quedar pegado' end

union all
select 4, 'La página puede avisar que volvió de pagar',
       case when has_function_privilege('anon', 'marcar_pago_dicho(text, text, text)', 'execute')
            then '✓ sí' else '✗ NO — el aviso no va a llegar al panel' end
 where exists (select 1 from pg_roles where rolname = 'anon')

union all
select 5, 'El público NO puede activar planes por su cuenta',
       case when has_table_privilege('anon', 'suscriptoras', 'update')
            then '✗ PUEDE — corré supabase-seguridad-cerrar-acceso.sql'
            else '✓ cerrado, solo puede mover la etiqueta' end
 where exists (select 1 from pg_roles where rolname = 'anon')

 order by n;
