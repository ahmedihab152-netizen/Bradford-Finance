begin;

create or replace function private.hr_prepare_run_defaults()
returns trigger language plpgsql security definer set search_path='public','private','pg_temp' as $$
begin
  new.prepared_by := coalesce(new.prepared_by,auth.uid());
  new.prepared_at := coalesce(new.prepared_at,now());
  perform private.hr_audit(
    'payroll_runs',new.id,'PREPARE',null,
    jsonb_build_object(
      'status',new.status,
      'prepared_by',new.prepared_by,
      'prepared_at',new.prepared_at,
      'supporting_document_url',new.supporting_document_url
    )
  );
  return new;
end$$;

revoke all on function private.hr_prepare_run_defaults() from public,anon,authenticated;

commit;
