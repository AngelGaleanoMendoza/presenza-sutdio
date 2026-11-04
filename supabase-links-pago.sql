-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Links de pago editables desde el panel
--  Pegar TODO esto en Supabase → SQL Editor → Run
--
--  QUÉ RESUELVE
--  Hasta hoy, cambiar un link de BAC era tocar el código y volver a
--  publicar el sitio. Con esta tabla los links viven en la base y se
--  editan desde el panel → pestaña Pagos, como ya pasa con el horario.
--
--  CÓMO CONVIVE CON EL CÓDIGO
--  La página arranca con los links que trae escritos y, apenas carga,
--  los reemplaza por los de esta tabla. Si la tabla está vacía o no se
--  puede leer, se queda con los del código: nunca se queda sin link.
--
--  PERMISOS · acá sí importa quién escribe
--  Estos links deciden a qué cuenta le entra la plata. Por eso, a
--  diferencia de `horarios`, escribir queda SOLO para quien inició
--  sesión en el panel (`authenticated`). La llave pública apenas puede
--  leerlos —que es lo que necesita la alumna para pagar— y no los puede
--  cambiar. Si alguien pudiera escribirlos con la llave pública, podría
--  apuntar el botón de pagar a su propia cuenta de BAC.
--
--  Es seguro correrlo más de una vez: los links que ya estén guardados
--  no se pisan (la siembra de abajo usa "on conflict do nothing").
-- ═══════════════════════════════════════════════════════════════════

create table if not exists links_pago (
  plan        text primary key,          -- singular · plan5 · plan10 · ilimit1 · ilimit3
  url         text not null default '',
  actualizado timestamptz not null default now()
);

alter table links_pago enable row level security;

drop policy if exists links_pago_select on links_pago;
drop policy if exists links_pago_write  on links_pago;

-- Leer: cualquiera. La alumna necesita el link para poder pagar.
create policy links_pago_select on links_pago
  for select using (true);

-- Escribir: solo con sesión del estudio.
create policy links_pago_write on links_pago
  for all to authenticated using (true) with check (true);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete on links_pago to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all  on links_pago from anon;
    grant select on links_pago to anon;
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════════
--  SIEMBRA · los links que hoy están en el código
--  Si ya corriste esto antes, lo que esté guardado NO se toca.
-- ═══════════════════════════════════════════════════════════════════
insert into links_pago (plan, url) values
  ('singular', 'https://checkout.baccredomatic.com/MS4xNGNjODllMTk4MGEzN2FhMDYxNmYxNzkzNjU4Nzg3'),
  ('plan5',    'https://checkout.baccredomatic.com/LjBmNWFmNmYxMmY0MDk4ZWUwMDgyNjAxNzkzNjU4ODQ5'),
  ('plan10',   'https://checkout.baccredomatic.com/MTkxMGFiNDZkMGUzLmYwMjY5ODc2ODAxNzkzNjU4OTUw'),
  ('ilimit1',  'https://checkout.baccredomatic.com/MTQ4MTYxYjU0NjA5MDE2MS44ZWE1M2ExNzkzNjU5MDA5'),
  ('ilimit3',  'https://checkout.baccredomatic.com/YTMxOC43MTEwOGQyNzA5MjA2NTY2MTYxNzg3NjI1ODc4')
on conflict (plan) do nothing;


-- ═══════════════════════════════════════════════════════════════════
--  REVISIÓN · las tres filas tienen que salir con ✅
-- ═══════════════════════════════════════════════════════════════════
select 1 as paso, 'La tabla links_pago existe' as revision,
       case when exists (select 1 from information_schema.tables
                          where table_name = 'links_pago')
            then '✅ sí' else '❌ NO' end as estado
union all
select 2, 'Quedaron los 5 links cargados',
       case when (select count(*) from links_pago where url <> '') = 5
            then '✅ sí, los 5'
            else '⚠️ hay ' || (select count(*) from links_pago where url <> '')::text || ' — revisá la pestaña Pagos' end
union all
select 3, 'Ningún link repetido entre dos planes',
       case when not exists (select 1 from links_pago where url <> ''
                              group by url having count(*) > 1)
            then '✅ ninguno'
            else '❌ HAY REPETIDOS — dos planes cobran el mismo monto' end
order by paso;
