begin;

create table if not exists public.cambios_pin_alumna (
  id bigint generated always as identity primary key,
  alumna_id uuid not null references public.alumnas(id) on delete cascade,
  staff_id uuid not null,
  staff_email text not null,
  fecha timestamptz not null default now()
);
alter table public.cambios_pin_alumna enable row level security;
revoke all on public.cambios_pin_alumna from anon, authenticated;

create or replace function public.restablecer_pin_alumna_staff(p_sub_id text, p_pin_nuevo text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_staff_id uuid := auth.uid();
  v_staff_email text;
  v_sub public.suscriptoras%rowtype;
  v_alumna public.alumnas%rowtype;
begin
  select lower(u.email) into v_staff_email from auth.users u
    where u.id = v_staff_id and u.email_confirmed_at is not null;
  if auth.role() is distinct from 'authenticated' or v_staff_email is null
     or v_staff_email not in ('jimena@presenza.auth', 'carlos@presenza.auth', 'laura@presenza.auth') then
    raise exception 'Solo Jimena, Carlos y Laura pueden restablecer el PIN de una alumna.';
  end if;
  if p_pin_nuevo is null or p_pin_nuevo !~ '^[0-9]{4}$' then
    raise exception 'El nuevo PIN debe tener exactamente 4 dígitos.';
  end if;

  select * into v_sub from public.suscriptoras where id = p_sub_id for update;
  if not found then raise exception 'No se encontró la ficha de la alumna.'; end if;
  select * into v_alumna from public.alumnas where sub_id = p_sub_id order by id limit 1 for update;
  if found and (select count(*) from public.alumnas where sub_id = p_sub_id) > 1 then
    raise exception 'Hay varios accesos vinculados a esta ficha. Revisa los datos antes de cambiar el PIN.';
  end if;
  if v_alumna.id is null and length(public.norm_tel(v_sub.tel)) >= 8 then
    select * into v_alumna from public.alumnas
      where public.norm_tel(tel) = public.norm_tel(v_sub.tel) for update;
    if v_alumna.sub_id is not null and v_alumna.sub_id <> p_sub_id then
      raise exception 'El celular corresponde a otra ficha. Revisa los datos antes de cambiar el PIN.';
    end if;
    if v_alumna.id is not null and not public.nombre_coincide(v_alumna.nombre_completo, v_sub.nombre) then
      raise exception 'El nombre del acceso no coincide con esta ficha. Revisa los datos antes de cambiar el PIN.';
    end if;
  end if;
  if v_alumna.id is null then
    raise exception 'Esta alumna todavía no tiene acceso a «Mis clases». Debe registrarse con su celular primero.';
  end if;

  update public.alumnas set pin_hash = extensions.crypt(p_pin_nuevo, extensions.gen_salt('bf')),
    sub_id = p_sub_id where id = v_alumna.id;
  delete from public.sesiones_alumna where alumna_id = v_alumna.id;
  insert into public.cambios_pin_alumna(alumna_id, staff_id, staff_email)
    values(v_alumna.id, v_staff_id, v_staff_email);
  return true;
end $$;

revoke all on function public.restablecer_pin_alumna_staff(text,text) from public, anon;
grant execute on function public.restablecer_pin_alumna_staff(text,text) to authenticated;

commit;
