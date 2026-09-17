-- Temporary production go-live safety locks.
-- These controls are intentionally fail-closed and can be re-enabled only by
-- changing the matching finance_settings value through an audited admin path.

insert into public.finance_settings(key,value,description)
values
  ('payroll_approval_enabled','false'::jsonb,'Temporary go-live lock: blocks HR and final payroll approvals.'),
  ('biometric_sync_enabled','false'::jsonb,'Temporary go-live lock: blocks confirmation/synchronization of biometric imports.')
on conflict (key) do update
set value=excluded.value,
    description=excluded.description,
    updated_at=now(),
    updated_by=null;

create or replace function private.operational_control_enabled(p_key text)
returns boolean
language sql
stable
security definer
set search_path='public','pg_temp'
as $$
  select coalesce(
    (select case
       when jsonb_typeof(value)='boolean' then (value #>> '{}')::boolean
       else false
     end
     from public.finance_settings
     where key=p_key),
    false
  )
$$;

revoke all on function private.operational_control_enabled(text) from public,anon,authenticated;

create or replace function public.hr_payroll_action(p_run uuid,p_action text,p_reason text default null)
returns void
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare r public.payroll_runs%rowtype;target text;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 if upper(coalesce(p_action,'')) in ('HR_APPROVE','AMANY_APPROVE')
    and not private.operational_control_enabled('payroll_approval_enabled') then
   raise exception 'Payroll approvals are temporarily disabled for production go-live validation';
 end if;
 select * into r from public.payroll_runs where id=p_run for update;
 if not found then raise exception 'Payroll run not found';end if;
 if p_action='SUBMIT' and r.status in ('DRAFT','RETURNED_FOR_CORRECTION') and public.current_finance_role() in ('HR_OFFICER','HR_MANAGER') then target:='SUBMITTED_TO_HR_MANAGER';
 elsif p_action='HR_APPROVE' and r.status='SUBMITTED_TO_HR_MANAGER' and public.current_finance_role()='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') then target:='HR_MANAGER_APPROVED';
 elsif p_action='RETURN' and r.status in ('SUBMITTED_TO_HR_MANAGER','HR_MANAGER_APPROVED') and public.current_finance_role()='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') then if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Reason required';end if;target:='RETURNED_FOR_CORRECTION';
 elsif p_action='AMANY_APPROVE' and r.status='HR_MANAGER_APPROVED' and public.current_finance_role()='DR_AMANY_APPROVER' and public.is_hr_authority('AMANY_FINAL') then target:='AMANY_APPROVED';
 elsif p_action='REJECT' and r.status='HR_MANAGER_APPROVED' and public.current_finance_role()='DR_AMANY_APPROVER' and public.is_hr_authority('AMANY_FINAL') then if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Reason required';end if;target:='REJECTED';
 else raise exception 'Not authorized or invalid payroll transition';end if;
 if target='SUBMITTED_TO_HR_MANAGER' then perform private.hr_include_movements(p_run);select * into r from public.payroll_runs where id=p_run;end if;
 perform set_config('bradford.hr_workflow','1',true);
 update public.payroll_runs set status=target,submitted_at=case when target='SUBMITTED_TO_HR_MANAGER' then now() else submitted_at end,submitted_by=case when target='SUBMITTED_TO_HR_MANAGER' then auth.uid() else submitted_by end,hr_approved_at=case when target='HR_MANAGER_APPROVED' then now() else hr_approved_at end,hr_approved_by=case when target='HR_MANAGER_APPROVED' then auth.uid() else hr_approved_by end,amany_approved_at=case when target='AMANY_APPROVED' then now() else amany_approved_at end,amany_approved_by=case when target='AMANY_APPROVED' then auth.uid() else amany_approved_by end,locked_at=case when target='AMANY_APPROVED' then now() else locked_at end,rejection_reason=p_reason,updated_at=now(),updated_by=auth.uid() where id=p_run;
 if target='AMANY_APPROVED' then update public.payroll_runs set journal_entry_id=private.hr_post_journal(p_run,'ACCRUAL'),status='READY_FOR_PAYMENT' where id=p_run;end if;
 perform private.hr_audit('payroll_runs',p_run,p_action,to_jsonb(r),jsonb_build_object('status',target,'reason',p_reason));
end$$;

create or replace function public.hr_confirm_biometric_import(p_batch uuid)
returns integer
language plpgsql
security definer
set search_path='public','private','pg_temp'
as $$
declare b public.biometric_import_batches%rowtype;x record;rid bigint;done int:=0;
begin
 if not private.operational_control_enabled('biometric_sync_enabled') then
   raise exception 'Biometric synchronization is temporarily disabled for production go-live validation';
 end if;
 if public.current_finance_role()<>'HR_MANAGER' or not public.is_hr_authority('HR_MANAGER') then raise exception 'Only designated HR Manager can confirm biometric import';end if;
 select * into b from public.biometric_import_batches where id=p_batch for update;
 if not found or b.status<>'PREVIEW' then raise exception 'Batch is not available for confirmation';end if;
 for x in select * from public.biometric_import_rows where batch_id=p_batch and validation_status='VALID' order by row_number loop
   insert into public.biometric_raw_logs(device_id,device_user_id,punch_time,punch_type,source_reference,import_batch_id,raw_payload)
   values(b.device_id,x.device_user_id,x.punch_time,x.punch_type,b.file_name,b.id,x.normalized_data)
   on conflict(device_id,device_user_id,punch_time,punch_type) do nothing returning id into rid;
   if rid is not null then update public.biometric_import_rows set raw_log_id=rid where id=x.id;done:=done+1;end if;rid:=null;
 end loop;
 update public.biometric_import_batches set status='CONFIRMED',accepted_count=done,confirmed_at=now(),confirmed_by=auth.uid() where id=b.id;
 perform private.hr_audit('biometric_import_batches',b.id,'CONFIRM',to_jsonb(b),jsonb_build_object('imported',done));
 return done;
end$$;

revoke all on function public.hr_payroll_action(uuid,text,text),public.hr_confirm_biometric_import(uuid) from public,anon;
grant execute on function public.hr_payroll_action(uuid,text,text),public.hr_confirm_biometric_import(uuid) to authenticated;

comment on function private.operational_control_enabled(text) is
  'Fail-closed server-side operational feature control backed by finance_settings.';
