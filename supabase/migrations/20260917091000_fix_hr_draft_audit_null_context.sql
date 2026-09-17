-- Ensure direct DRAFT updates are audited when no workflow context is set.
-- current_setting(..., true) returns NULL for an unset key; SQL NULL comparison
-- previously skipped the audit call unintentionally.

create or replace function private.hr_movement_direct_audit()
returns trigger
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
begin
  if coalesce(current_setting('bradford.hr_movement_workflow',true),'') <> '1' then
    perform private.hr_audit(
      'hr_employee_movements',
      new.id,
      'UPDATE_DRAFT',
      to_jsonb(old),
      to_jsonb(new)
    );
  end if;
  return new;
end$$;

revoke all on function private.hr_movement_direct_audit() from public,anon,authenticated;

comment on function private.hr_movement_direct_audit() is
  'Audits direct HR movement draft updates; workflow-managed updates audit themselves.';
