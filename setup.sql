-- Baza de date pentru site-ul P.U.C.D. — DE LA 0.
-- Rulează tot fișierul în Supabase → SQL Editor → New query → Run.
-- ATENȚIE: șterge tot ce era (membri, votări, voturi) și pornește curat.
-- La final îți afișează codul tău de admin și codul contului de debug.

-- ───────── Ștergem tot ce era ─────────
drop table if exists votes, questions, members cascade;
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.proname in (
             '_member','_admin','_is_closed','_outcome','member_name','member_role','is_admin','is_debug',
             'role_options','army_roster','list_questions','cast_vote','get_results','question_outcomes',
             'recruitment_history','admin_votes','admin_members','add_question','edit_question',
             'set_question_closed','set_question_deadline','delete_question','add_member','set_member_role',
             'set_member_admin','regenerate_code','delete_member',
             '_is_president_role','_is_founder','is_founder')
  loop execute 'drop function if exists ' || f.sig || ' cascade'; end loop;
end $$;

-- ───────── Tabele ─────────
create table members (
  code       text primary key default substr(replace(gen_random_uuid()::text, '-', ''), 1, 20),
  name       text not null,
  role       text,
  is_admin   boolean not null default false,
  is_debug   boolean not null default false,
  created_at timestamptz not null default now()
);

create table questions (
  id            bigint generated always as identity primary key,
  question_text text not null,
  options       text[] not null,
  roles         text[],
  closes_at     timestamptz,
  closed        boolean not null default false,
  decided_at    timestamptz,
  hide_results  boolean not null default false,
  secret        boolean not null default false,
  kind          text not null default 'normal' check (kind in ('normal', 'lege', 'recrutare')),
  subject       text,
  quorum        int not null default 0,
  threshold     int not null default 50,
  created_at    timestamptz not null default now()
);

create table votes (
  question_id bigint not null references questions(id) on delete cascade,
  member_code text not null references members(code) on delete cascade on update cascade,
  choice      text not null,
  created_at  timestamptz not null default now(),
  constraint votes_one_per_member unique (question_id, member_code)
);

-- Nimeni nu citește tabelele direct: totul trece prin funcțiile de mai jos.
alter table members   enable row level security;
alter table questions enable row level security;
alter table votes     enable row level security;
revoke all on members, questions, votes from anon, authenticated;

-- ───────── Ajutătoare (interne) ─────────
create or replace function _member(p_code text) returns members
language plpgsql security definer set search_path = public as $$
declare m members;
begin
  select * into m from members where code = p_code;
  if not found then raise exception 'cod invalid'; end if;
  return m;
end $$;

create or replace function _admin(p_code text) returns members
language plpgsql security definer set search_path = public as $$
declare m members;
begin
  m := _member(p_code);
  if not m.is_admin then raise exception 'cod invalid'; end if;
  return m;
end $$;

create or replace function _is_closed(q questions) returns boolean
language sql stable as $$
  select q.closed or (q.closes_at is not null and q.closes_at <= now())
$$;

create or replace function _outcome(q questions) returns text
language plpgsql stable security definer set search_path = public as $$
declare pro int; con int; voters int; eligible int;
begin
  if q.kind = 'normal' or not _is_closed(q) then return null; end if;
  select count(*) filter (where v.choice = 'Pentru'),
         count(*) filter (where v.choice = 'Împotrivă'),
         count(*)
    into pro, con, voters
    from votes v join members m on m.code = v.member_code
   where v.question_id = q.id and not m.is_debug;
  select count(*) into eligible from members m
   where not m.is_debug and (q.roles is null or m.role = any(q.roles));
  if q.quorum > 0 and voters * 100 < q.quorum * eligible then return 'FĂRĂ CVORUM'; end if;
  if (q.threshold >= 99 and pro > 0 and con = 0)
     or (q.threshold between 66 and 98 and pro * 3 >= (pro + con) * 2 and pro > 0)
     or (q.threshold < 66 and pro * 2 > pro + con) then
    return case when q.kind = 'recrutare' then 'PRIMIT' else 'ADOPTAT' end;
  end if;
  return 'RESPINS';
end $$;

-- ───────── Pentru toți membrii ─────────
create or replace function member_name(p_code text) returns text
language sql stable security definer set search_path = public as $$
  select name from members where code = p_code
$$;

create or replace function member_role(p_code text) returns text
language sql stable security definer set search_path = public as $$
  select role from members where code = p_code
$$;

create or replace function is_admin(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from members where code = p_code), false)
$$;

create or replace function is_debug(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_debug from members where code = p_code), false)
$$;

create or replace function role_options(p_code text) returns table(role text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _member(p_code);
  return query select distinct m.role from members m
    where m.role is not null and not m.is_debug order by 1;
end $$;

create or replace function list_questions(p_code text, p_role text default null) returns setof questions
language plpgsql stable security definer set search_path = public as $$
declare m members; r text;
begin
  m := _member(p_code);
  r := case when m.is_debug then p_role else m.role end;
  return query select * from questions q
    where m.is_admin or q.roles is null or r = any(q.roles)
    order by q.created_at desc;
end $$;

create or replace function cast_vote(p_code text, p_question bigint, p_choice text) returns void
language plpgsql security definer set search_path = public as $$
declare m members; q questions;
begin
  m := _member(p_code);
  select * into q from questions where id = p_question;
  if not found then raise exception 'intrebare invalida'; end if;
  if _is_closed(q) then raise exception 'votul e inchis'; end if;
  if not m.is_debug and not m.is_admin and q.roles is not null and not (m.role = any(q.roles)) then
    raise exception 'functie nepermisa';
  end if;
  if not (p_choice = any(q.options)) then raise exception 'alegere invalida'; end if;
  if m.is_debug then
    delete from votes where question_id = q.id and member_code = m.code;
  end if;
  insert into votes(question_id, member_code, choice) values (q.id, m.code, p_choice);
end $$;

create or replace function get_results(p_code text, p_question bigint) returns table(choice text, n bigint)
language plpgsql stable security definer set search_path = public as $$
declare m members; q questions;
begin
  m := _member(p_code);
  select * into q from questions where id = p_question;
  if not found then raise exception 'intrebare invalida'; end if;
  if not m.is_admin and (q.secret or (q.hide_results and not _is_closed(q))) then
    return;
  end if;
  return query select v.choice, count(*) from votes v join members mm on mm.code = v.member_code
    where v.question_id = q.id and not mm.is_debug group by v.choice;
end $$;

create or replace function question_outcomes(p_code text) returns table(question_id bigint, outcome text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _member(p_code);
  return query select q.id, _outcome(q) from questions q where _outcome(q) is not null;
end $$;

create or replace function recruitment_history(p_code text) returns table(subject text, outcome text, decided_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _member(p_code);
  return query select q.subject, _outcome(q), coalesce(q.decided_at, q.closes_at)
    from questions q where q.kind = 'recrutare' and _is_closed(q)
    order by 3 desc nulls last;
end $$;

-- ───────── Doar pentru comandant (admin) ─────────
create or replace function admin_votes(p_code text) returns table(question_id bigint, name text, choice text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _admin(p_code);
  return query select v.question_id, m.name, v.choice from votes v join members m on m.code = v.member_code
    where not m.is_debug;
end $$;

create or replace function admin_members(p_code text) returns table(code text, name text, role text, is_admin boolean, is_debug boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform _admin(p_code);
  return query select m.code, m.name, m.role, m.is_admin, m.is_debug from members m
    order by m.is_admin desc, m.is_debug, m.role nulls last, m.name;
end $$;

create or replace function add_question(
  p_code text, p_text text, p_options text[], p_roles text[], p_closes_at timestamptz,
  p_hide boolean, p_secret boolean, p_kind text, p_subject text, p_quorum int, p_threshold int
) returns bigint
language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  perform _admin(p_code);
  if coalesce(trim(p_text), '') = '' or coalesce(array_length(p_options, 1), 0) < 2 then
    raise exception 'intrebare invalida';
  end if;
  insert into questions(question_text, options, roles, closes_at, hide_results, secret, kind, subject, quorum, threshold)
  values (trim(p_text), p_options, nullif(p_roles, '{}'), p_closes_at, coalesce(p_hide, false), coalesce(p_secret, false),
          coalesce(p_kind, 'normal'), p_subject, coalesce(p_quorum, 0), coalesce(p_threshold, 50))
  returning id into new_id;
  return new_id;
end $$;

create or replace function edit_question(p_code text, p_id bigint, p_text text, p_options text[]) returns void
language plpgsql security definer set search_path = public as $$
declare q questions; i int;
begin
  perform _admin(p_code);
  select * into q from questions where id = p_id;
  if not found or coalesce(trim(p_text), '') = '' then raise exception 'intrebare invalida'; end if;
  if array_length(p_options, 1) is distinct from array_length(q.options, 1) then raise exception 'numar variante'; end if;
  -- voturile urmează varianta redenumită
  for i in 1 .. array_length(q.options, 1) loop
    if q.options[i] <> p_options[i] then
      update votes set choice = p_options[i] where question_id = p_id and choice = q.options[i];
    end if;
  end loop;
  update questions set question_text = trim(p_text), options = p_options where id = p_id;
end $$;

create or replace function set_question_closed(p_code text, p_id bigint, p_closed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin(p_code);
  update questions set
    closed = p_closed,
    decided_at = case when p_closed then now() else null end,
    closes_at = case when not p_closed and closes_at <= now() then null else closes_at end
  where id = p_id;
end $$;

create or replace function set_question_deadline(p_code text, p_id bigint, p_closes_at timestamptz) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin(p_code);
  update questions set closes_at = p_closes_at, closed = false, decided_at = null where id = p_id;
end $$;

create or replace function delete_question(p_code text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _admin(p_code);
  delete from questions where id = p_id;
end $$;

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

-- ───────── Permisiuni ─────────
revoke execute on function _member(text), _admin(text), _is_closed(questions), _outcome(questions),
  _is_president_role(text), _is_founder(members) from public, anon, authenticated;
grant execute on function
  member_name(text), member_role(text), is_admin(text), is_debug(text), is_founder(text), role_options(text),
  list_questions(text, text), cast_vote(text, bigint, text), get_results(text, bigint),
  question_outcomes(text), recruitment_history(text),
  admin_votes(text), admin_members(text),
  add_question(text, text, text[], text[], timestamptz, boolean, boolean, text, text, int, int),
  edit_question(text, bigint, text, text[]), set_question_closed(text, bigint, boolean),
  set_question_deadline(text, bigint, timestamptz), delete_question(text, bigint),
  add_member(text, text, text), set_member_role(text, text, text),
  regenerate_code(text, text), delete_member(text, text)
to anon;

-- ───────── Primii membri ─────────
-- Tu (fondator: admin cu funcția „Fondator”) + contul de debug. Poți schimba numele/funcția înainte de Run.
insert into members(name, role, is_admin) values ('Gabi', 'Fondator', true);
insert into members(name, role, is_debug) values ('debug', null, true);

select name, code, case when is_admin then 'FONDATOR' else 'DEBUG' end as tip from members order by is_admin desc;
