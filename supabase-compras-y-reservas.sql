begin;

alter table public.suscriptoras add column if not exists pendiente_metodo text;
alter table public.reservas add column if not exists clase_descontada boolean not null default false;

create or replace function public.solicitar_compra_publica(
  p_nombre text, p_email text, p_tel text, p_nivel text, p_plan text, p_metodo text
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_id text;
  v_anterior suscriptoras%rowtype;
begin
  if p_plan is null or p_plan not in ('singular', 'plan5', 'plan10', 'ilimit1', 'ilimit3')
     or p_metodo is null or p_metodo not in ('link_bac', 'transferencia') then
    raise exception 'Paquete o método de pago no válido.';
  end if;
  if nullif(trim(p_nombre), '') is null
     or coalesce(trim(p_email), '') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     or length(norm_tel(p_tel)) < 8 then
    raise exception 'Completa tu nombre, correo y teléfono.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(lower(trim(p_email)), 0));
  select * into v_anterior from suscriptoras
   where lower(email) = lower(trim(p_email))
      or (norm_tel(tel) = norm_tel(p_tel) and nombre_coincide(nombre, p_nombre))
   order by (lower(email) = lower(trim(p_email))) desc limit 1 for update;
  if v_anterior.pendiente_plan is not null then
    if v_anterior.pendiente_plan = p_plan and v_anterior.pendiente_metodo = p_metodo then
      return v_anterior.id;
    end if;
    raise exception 'Ya tienes una compra pendiente. Contacta al estudio para cambiar el paquete o el método.';
  end if;
  v_id := solicitar_plan_publico(p_nombre, lower(trim(p_email)), p_tel, p_nivel, p_plan);
  update suscriptoras set pendiente_metodo = p_metodo,
    pendiente_estado = 'espera', pendiente_ref = null where id = v_id;
  return v_id;
end $$;

revoke all on function public.solicitar_compra_publica(text,text,text,text,text,text) from public;
grant execute on function public.solicitar_compra_publica(text,text,text,text,text,text) to anon, authenticated;
create or replace function public.validar_reserva_con_plan()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_sub suscriptoras%rowtype;
  v_gratis boolean;
begin
  if auth.role() = 'service_role' then return new; end if;

  select exists(select 1 from clases_especiales e
    where e.clase = new.clase and e.fecha = new.fecha and e.hora = new.hora
      and e.activa and e.precio = 0) into v_gratis;
  select * into v_sub from suscriptoras s
    where (nullif(trim(new.email), '') is not null and lower(s.email) = lower(trim(new.email)))
       or (length(norm_tel(new.tel)) >= 8 and norm_tel(s.tel) = norm_tel(new.tel))
       or (s.email ilike '%@pendiente.presenza' and nombre_coincide(s.nombre, new.nombre))
    order by (lower(s.email) = lower(trim(coalesce(new.email, '')))) desc nulls last
    limit 1 for update;
  if not found or not coalesce(v_sub.activa, false)
     or v_sub.plan is null
     or v_sub.fecha_vence is null or v_sub.fecha_vence < hoy_ni()
     or v_sub.fecha_vence < new.fecha
     or (v_sub.plan not in ('ilimit1', 'ilimit3', 'ilimit6') and coalesce(v_sub.clases_restantes, 0) <= 0) then
    raise exception 'Necesitas un paquete o membresía activa con clases disponibles para esta fecha.';
  end if;
  new.pago_ok := true;
  new.metodo := case when v_gratis then '🎁 Clase gratis' else '💎 Suscripción · ' || v_sub.plan end;
  new.clase_descontada := not v_gratis and v_sub.plan not in ('ilimit1', 'ilimit3', 'ilimit6');
  update suscriptoras set
    clases_restantes = clases_restantes - case when new.clase_descontada then 1 else 0 end,
    clases_usadas = coalesce(clases_usadas, 0) + case when new.clase_descontada then 1 else 0 end,
    email = case when email ilike '%@pendiente.presenza' and nullif(trim(new.email), '') is not null
      then lower(trim(new.email)) else email end
    where id = v_sub.id;
  return new;
end $$;

drop trigger if exists reservas_exigen_plan on public.reservas;
create trigger reservas_exigen_plan before insert on public.reservas
  for each row execute function public.validar_reserva_con_plan();

create or replace function public.reservar_con_plan(p_reserva jsonb)
returns boolean language plpgsql security invoker set search_path = public as $$
begin
  insert into reservas (slot_key, clase, fecha, hora, ts, nombre, email, tel,
    nivel, notas, lugar, metodo, instructor, pago_ok, clase_descontada)
  select r.slot_key, r.clase, r.fecha, r.hora, r.ts, r.nombre, r.email, r.tel,
    r.nivel, r.notas, r.lugar, r.metodo, r.instructor, true, false
  from jsonb_populate_record(null::reservas, p_reserva) r;
  return true;
end $$;
revoke all on function public.reservar_con_plan(jsonb) from public;
grant execute on function public.reservar_con_plan(jsonb) to anon, authenticated;
commit;
