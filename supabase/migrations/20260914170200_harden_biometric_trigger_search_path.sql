-- Lock the immutable biometric trigger to a trusted search path.
-- This is additive, keeps existing attendance data untouched, and is reversible
-- by restoring the previous function definition.

create or replace function private.biometric_raw_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception 'Raw biometric logs cannot be changed or deleted';
end
$function$;

revoke all on function private.biometric_raw_immutable() from public, anon, authenticated;

comment on function private.biometric_raw_immutable() is
  'Trigger-only guard that prevents changes or deletion of raw biometric logs.';
