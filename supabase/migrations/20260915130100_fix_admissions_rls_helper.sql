-- RLS policies must be able to invoke the private role predicate.
-- The function exposes one boolean only and derives identity from auth.uid().
grant usage on schema private to authenticated;
grant execute on function private.is_admissions_reader() to authenticated;
