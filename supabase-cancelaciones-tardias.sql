begin;

create table if not exists public.penalizaciones_cancelacion (
  id bigint generated always as identity primary key,
  reserva_id bigint not null unique,
  nombre text not null,
  email text,
  tel text,
  clase text not null,
  fecha_clase date not null,
  hora text not null,
  tipo text not null check (tipo in ('clase', 'fee')),
  monto_usd numeric(10,2) not null default 0,
  creada timestamptz not null default now(),
  pagado_en timestamptz,
  pagado_por uuid
);
alter table public.penalizaciones_cancelacion enable row level security;
revoke all on public.penalizaciones_cancelacion from anon, authenticated;

create or replace function public.cancelar_reserva_alumna(
  p_token uuid, p_ts bigint, p_confirmar boolean default false,
  p_acepta_penalizacion boolean default false
) returns table(ok boolean, mensaje text, devuelta boolean, requiere_penalizacion boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tel text;
  v_email text;
  v_res public.reservas%rowtype;
  v_inicio timestamptz;
  v_tardia boolean;
  v_ilimitada boolean;
  v_sub_id text;
  v_devuelta boolean := false;
  v_aviso text;
begin
  select norm_tel(a.tel), lower(coalesce(a.email, '')) into v_tel, v_email
    from public.alumnas a join public.sesiones_alumna s on s.alumna_id = a.id
    where s.token = p_token and s.expira > now();
  if v_tel is null then
    return query select false, 'Tu sesión expiró. Vuelve a entrar.', false, false; return;
  end if;
  select * into v_res from public.reservas r
    where r.ts = p_ts and (norm_tel(r.tel) = v_tel
      or (v_email <> '' and lower(coalesce(r.email,'')) = v_email))
    order by r.id limit 1 for update;
  if not found then
    return query select false, 'No encontramos esa reserva a tu nombre.', false, false; return;
  end if;
  if v_res.cancelada is not null then
    return query select false, 'Esa reserva ya estaba cancelada.', false, false; return;
  end if;
  v_inicio := (v_res.fecha + v_res.hora::time) at time zone 'America/Managua';
  if v_inicio <= now() then
    return query select false, 'Esa clase ya comenzó o ya pasó.', false, false; return;
  end if;
  v_tardia := v_inicio - now() < interval '6 hours';
  v_ilimitada := lower(coalesce(v_res.metodo,'')) like '%ilimit%';
  if v_tardia and v_ilimitada then
    v_aviso := 'Las clases se deben cancelar con mínimo 6 horas de anticipación. Al cancelar esta clase se te cobrará un fee de US$5. ¿Deseas continuar?';
  elsif v_tardia and coalesce(v_res.clase_descontada,false) then
    v_aviso := 'Las clases se deben cancelar con mínimo 6 horas de anticipación. Al cancelar esta clase se te deducirá de tu paquete y no se devolverá. ¿Deseas continuar?';
  else
    v_aviso := 'Si se descontó una clase de tu paquete, se devolverá. Para asistir después tendrás que reservar de nuevo. ¿Deseas cancelar?';
  end if;
  if not coalesce(p_confirmar,false) then
    return query select true, v_aviso, false, v_tardia; return;
  end if;
  if v_tardia and not coalesce(p_acepta_penalizacion,false) then
    return query select false, v_aviso, false, true; return;
  end if;

  if not v_tardia and coalesce(v_res.clase_descontada,false) then
    select s.id into v_sub_id from public.suscriptoras s
      where (nullif(lower(coalesce(v_res.email,'')),'') is not null and lower(s.email) = lower(v_res.email))
        or (length(norm_tel(v_res.tel)) >= 8 and norm_tel(s.tel) = norm_tel(v_res.tel))
      order by (lower(s.email) = lower(coalesce(v_res.email,''))) desc nulls last
      limit 1 for update;
    if v_sub_id is not null then
      update public.suscriptoras set clases_restantes = clases_restantes + 1,
        clases_usadas = greatest(0,coalesce(clases_usadas,0)-1)
        where id = v_sub_id and clases_restantes < 1000;
      v_devuelta := found;
    end if;
  end if;
  if v_tardia and (v_ilimitada or coalesce(v_res.clase_descontada,false)) then
    insert into public.penalizaciones_cancelacion
      (reserva_id,nombre,email,tel,clase,fecha_clase,hora,tipo,monto_usd)
    values (v_res.id,v_res.nombre,v_res.email,v_res.tel,v_res.clase,v_res.fecha,v_res.hora,
      case when v_ilimitada then 'fee' else 'clase' end, case when v_ilimitada then 5 else 0 end);
  end if;
  delete from public.reservas where id = v_res.id;
  return query select true,
    case when v_tardia and v_ilimitada then 'Reserva cancelada. Quedó pendiente el fee de US$5 por cancelación con menos de 6 horas de anticipación.'
      when v_tardia and coalesce(v_res.clase_descontada,false) then 'Reserva cancelada. La clase se mantiene descontada de tu paquete por cancelar con menos de 6 horas de anticipación.'
      else 'Tu reserva quedó cancelada.' end, v_devuelta, false;
end $$;

create or replace function public.cancelar_mi_reserva(p_token uuid,p_ts bigint)
returns table(ok boolean,mensaje text,devuelta boolean)
language sql security definer set search_path = public as $$
  select r.ok,r.mensaje,r.devuelta from public.cancelar_reserva_alumna(p_token,p_ts,true,false) r
$$;

create or replace function public.gestionar_fees_cancelacion(p_pagado bigint default null)
returns setof public.penalizaciones_cancelacion
language plpgsql security definer set search_path = public as $$
begin
  if auth.role() is distinct from 'authenticated' or not exists (
    select 1 from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null
      and lower(u.email) in ('jimena@presenza.auth','carlos@presenza.auth','laura@presenza.auth')
  ) then raise exception 'Solo Jimena, Carlos y Laura pueden gestionar los fees de cancelación.'; end if;
  if p_pagado is not null then
    update public.penalizaciones_cancelacion set pagado_en = now(), pagado_por = auth.uid()
      where id = p_pagado and tipo = 'fee' and pagado_en is null;
    if not found then raise exception 'Este fee ya fue registrado como pagado o no existe.'; end if;
  end if;
  return query select * from public.penalizaciones_cancelacion
    where tipo = 'fee' and pagado_en is null order by creada;
end $$;

revoke all on function public.cancelar_reserva_alumna(uuid,bigint,boolean,boolean) from public;
grant execute on function public.cancelar_reserva_alumna(uuid,bigint,boolean,boolean) to anon,authenticated;
revoke all on function public.cancelar_mi_reserva(uuid,bigint) from public;
grant execute on function public.cancelar_mi_reserva(uuid,bigint) to anon,authenticated;
revoke all on function public.gestionar_fees_cancelacion(bigint) from public,anon;
grant execute on function public.gestionar_fees_cancelacion(bigint) to authenticated;

commit;
