-- ═══════════════════════════════════════════════════════════════════
--  PRESENZA STUDIO · Poner a las alumnas que YA existen dentro del
--  acceso "Mis clases"
--
--  Correr DESPUÉS de supabase-login-alumnas.sql.
--
--  Va en dos partes:
--    A) DIAGNÓSTICO — qué alumnas van a poder entrar y cuáles no.
--       Son solo consultas, no cambian nada. Correlas primero.
--    B) BACKFILL — deja pre-cargado el listado de alumnas para que cada
--       una solo tenga que elegir su PIN.
--
--  Es seguro correrlo más de una vez.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
--  A) DIAGNÓSTICO  ·  no modifica nada
-- ═══════════════════════════════════════════════════════════════════

-- A1 · ¿Cuántas alumnas podrían crear su acceso hoy?
with gente as (
  select norm_tel(tel) t from suscriptoras where length(norm_tel(tel)) = 8
  union
  select norm_tel(tel)   from reservas     where length(norm_tel(tel)) = 8
)
select count(distinct t) as celulares_listos from gente;

-- A2 · Fichas SIN teléfono válido: estas alumnas NO van a poder entrar.
--      Hay que pedirles el número y completarlo desde el panel.
select id, nombre, coalesce(nullif(tel, ''), '(vacío)') as tel
  from suscriptoras
 where length(norm_tel(tel)) <> 8
 order by nombre;

-- A3 · Un mismo celular usado por personas distintas (madre e hija, etc.).
--      OJO: solo una puede tener cuenta, y vería las clases de ambas,
--      porque la identidad es el número. Conviene pedirle a la segunda
--      su propio celular antes de anunciar el acceso.
select norm_tel(tel) as celular,
       count(distinct norm_nombre(nombre)) as personas,
       string_agg(distinct nombre, ' · ')  as quienes
  from (select tel, nombre from suscriptoras
        union all
        select tel, nombre from reservas) t
 where length(norm_tel(tel)) = 8
 group by 1
having count(distinct norm_nombre(nombre)) > 1;


-- ═══════════════════════════════════════════════════════════════════
--  B) BACKFILL  ·  deja el listado pre-cargado
--
--  Crea la ficha de acceso de cada alumna SIN PIN. Cuando ella entre a
--  "Crea tu acceso", el sistema encuentra su ficha y solo le pide elegir
--  el PIN: no se duplica ni se crea otra.
--
--  Ventaja real: te queda un roster para ver quién ya activó y quién no.
-- ═══════════════════════════════════════════════════════════════════

-- B1 · Las que tienen ficha de suscriptora (con su plan enlazado)
insert into alumnas (nombre_completo, tel, email, sub_id)
select distinct on (norm_tel(s.tel)) s.nombre, s.tel, nullif(s.email, ''), s.id
  from suscriptoras s
 where length(norm_tel(s.tel)) = 8
 order by norm_tel(s.tel), s.id
on conflict do nothing;

-- B2 · Las que solo han reservado, sin plan. Se toma el nombre de su
--      reserva más reciente, que es el dato más fresco que hay de ellas.
insert into alumnas (nombre_completo, tel, email)
select distinct on (norm_tel(r.tel)) r.nombre, r.tel, nullif(r.email, '')
  from reservas r
 where length(norm_tel(r.tel)) = 8
   and not exists (select 1 from alumnas a where norm_tel(a.tel) = norm_tel(r.tel))
 order by norm_tel(r.tel), r.creado desc
on conflict do nothing;


-- ═══════════════════════════════════════════════════════════════════
--  C) TU ROSTER  ·  quién ya activó su acceso y quién no
--     Guardá esta consulta: es la que vas a correr para dar seguimiento.
-- ═══════════════════════════════════════════════════════════════════
select nombre_completo,
       norm_tel(tel) as celular,
       case when pin_hash is null then '⏳ pendiente de activar'
            else '✓ activó' end as estado,
       ultimo_acceso
  from alumnas
 order by (pin_hash is not null), nombre_completo;
