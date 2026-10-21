-- Fondatorul coloniei + Președinții (admini numiți de fondator).
-- NU șterge nimic: rulează-l o singură dată în Supabase → SQL Editor → New query → Run,
-- peste baza de date făcută deja cu setup.sql (membrii, votările și voturile rămân).
--
-- Reguli:
--  • Fondatorul = contul admin cu funcția „Fondator” (cel creat de setup.sql). E unul singur.
--  • Doar fondatorul poate numi / schimba / scoate un Președinte. Președintele devine automat admin,
--    iar dacă îi iei funcția de Președinte, nu mai e admin.
--  • Adminii (fondator + președinți) dau orice altă funcție membrilor obișnuiți.
--  • Doar fondatorul poate da cod nou sau șterge un admin. Pe fondator nu-l poate atinge nimeni.

create or replace function _is_president_role(r text) returns boolean
language sql immutable as $$
  select lower(trim(coalesce(r, ''))) in ('presedinte', 'președinte')
$$;

create or replace function _is_founder(m members) returns boolean
language sql immutable as $$
  select m.is_admin and lower(trim(coalesce(m.role, ''))) = 'fondator'
$$;

create or replace function is_founder(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select _is_founder(m) from members m where m.code = p_code), false)
$$;

create or replace function add_member(p_code text, p_name text, p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare me members; c text;
begin
  me := _admin(p_code);
  if coalesce(trim(p_name), '') = '' then raise exception 'nume invalid'; end if;
  if lower(trim(coalesce(p_role, ''))) = 'fondator' then raise exception 'fondatorul este unul singur'; end if;
  if _is_president_role(p_role) and not _is_founder(me) then
    raise exception 'doar fondatorul poate numi presedintele';
  end if;
  -- cine e Presedinte devine automat admin
  insert into members(name, role, is_admin)
  values (trim(p_name), nullif(trim(p_role), ''), _is_president_role(p_role))
  returning code into c;
  return c;
end $$;

create or replace function set_member_role(p_code text, p_member text, p_role text) returns void
language plpgsql security definer set search_path = public as $$
declare me members; t members;
begin
  me := _admin(p_code);
  select * into t from members where code = p_member;
  if not found or t.is_debug then raise exception 'membru invalid'; end if;
  if _is_founder(t) then raise exception 'functia fondatorului nu se schimba'; end if;
  if lower(trim(coalesce(p_role, ''))) = 'fondator' then raise exception 'fondatorul este unul singur'; end if;
  if (t.is_admin or _is_president_role(p_role)) and not _is_founder(me) then
    raise exception 'doar fondatorul poate numi sau schimba presedintele';
  end if;
  -- Presedinte => admin; orice alta functie => nu mai e admin
  update members set role = nullif(trim(p_role), ''), is_admin = _is_president_role(p_role)
  where code = p_member;
end $$;

create or replace function regenerate_code(p_code text, p_member text) returns text
language plpgsql security definer set search_path = public as $$
declare me members; t members; c text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 20);
begin
  me := _admin(p_code);
  select * into t from members where code = p_member;
  if not found then raise exception 'membru invalid'; end if;
  if _is_founder(t) or (t.is_admin and not _is_founder(me)) then raise exception 'cod admin'; end if;
  update members set code = c where code = p_member;
  return c;
end $$;

create or replace function delete_member(p_code text, p_member text) returns void
language plpgsql security definer set search_path = public as $$
declare me members; t members;
begin
  me := _admin(p_code);
  select * into t from members where code = p_member;
  if not found then return; end if;
  if _is_founder(t) or (t.is_admin and not _is_founder(me)) then raise exception 'nu poti sterge'; end if;
  delete from members where code = p_member;
end $$;

revoke execute on function _is_president_role(text), _is_founder(members) from public, anon, authenticated;
grant execute on function is_founder(text) to anon;

-- Verificare: cine e fondator / admin acum.
select name, role, case when _is_founder(m) then 'FONDATOR' when is_admin then 'ADMIN' when is_debug then 'DEBUG' else '' end as tip
from members m order by is_admin desc, is_debug, name;
