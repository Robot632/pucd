-- Contul de test (debug) poate juca rolul de Președinte.
-- NU șterge nimic: rulează-l o singură dată în Supabase → SQL Editor → New query → Run.
--
--  • Contul de debug primește drepturi de admin în baza de date, dar site-ul îi arată
--    panoul doar când alege funcția „Presedinte”.
--  • Cu altă funcție aleasă vede doar votările acelei funcții, ca un membru obișnuit.
--  • Votul lui tot nu se numără; nu poate numi președinți (asta rămâne doar la fondator).

update members set is_admin = true where is_debug;

create or replace function list_questions(p_code text, p_role text default null) returns setof questions
language plpgsql stable security definer set search_path = public as $$
declare m members; r text;
begin
  m := _member(p_code);
  r := case when m.is_debug then p_role else m.role end;
  return query select * from questions q
    where (m.is_admin and (not m.is_debug or lower(trim(coalesce(r, ''))) in ('presedinte', 'președinte')))
       or q.roles is null or r = any(q.roles)
    order by q.created_at desc;
end $$;

notify pgrst, 'reload schema';

select name, role, is_admin, is_debug from members where is_debug;
