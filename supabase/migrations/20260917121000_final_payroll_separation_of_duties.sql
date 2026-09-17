begin;

create table if not exists public.hr_user_capabilities (
  user_id uuid not null references auth.users(id) on delete cascade,
  capability text not null check (capability in (
    'BIOMETRIC_MANAGER','PAYROLL_PREPARER','ATTENDANCE_OFFICER',
    'DR_AMANY_APPROVER','PAYROLL_CASHIER'
  )),
  active boolean not null default true,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id),
  primary key (user_id, capability)
);

alter table public.hr_user_capabilities enable row level security;
revoke all on public.hr_user_capabilities from public, anon, authenticated;
grant select on public.hr_user_capabilities to authenticated;
drop policy if exists hr_capabilities_self_read on public.hr_user_capabilities;
create policy hr_capabilities_self_read on public.hr_user_capabilities
for select to authenticated using (user_id = auth.uid());

create or replace function public.has_hr_capability(p_capability text)
returns boolean language sql stable security definer
set search_path='public','pg_temp' as $$
  select exists (
    select 1 from public.hr_user_capabilities c
    join public.user_profiles p on p.user_id=c.user_id
    where c.user_id=auth.uid() and c.capability=upper(p_capability)
      and c.active and p.active
  )
$$;
revoke all on function public.has_hr_capability(text) from public, anon;
grant execute on function public.has_hr_capability(text) to authenticated;

-- Resolve the five named people by Auth email. Missing accounts stay untouched.
update public.user_profiles p set role='HR_MANAGER',active=true,updated_at=now()
from auth.users u where p.user_id=u.id and lower(u.email)=lower('rehab@midcairointernationalschool.com');
update public.user_profiles p set role='ATTENDANCE_OFFICER',active=true,updated_at=now()
from auth.users u where p.user_id=u.id and lower(u.email)=lower('Mariananadysmsm@gmail.com');
update public.user_profiles p set role='DR_AMANY_APPROVER',active=true,updated_at=now()
from auth.users u where p.user_id=u.id and lower(u.email)=lower('amanyhussienelz@gmail.com');
update public.user_profiles p set role='PAYROLL_CASHIER',active=true,updated_at=now()
from auth.users u where p.user_id=u.id and lower(u.email) in
  (lower('Mahmoudelsaid69000@gmail.com'),lower('ahmedshams79@gmail.com'));

-- Remove every former HR capability for these identities, then grant only the
-- explicitly approved final distribution.
delete from public.hr_user_capabilities c using auth.users u
where c.user_id=u.id and lower(u.email) in (
  lower('rehab@midcairointernationalschool.com'),lower('Mariananadysmsm@gmail.com'),
  lower('amanyhussienelz@gmail.com'),lower('Mahmoudelsaid69000@gmail.com'),
  lower('ahmedshams79@gmail.com')
);
insert into public.hr_user_capabilities(user_id,capability)
select u.id,x.capability from auth.users u
cross join lateral (
  select unnest(case lower(u.email)
    when lower('rehab@midcairointernationalschool.com') then array['BIOMETRIC_MANAGER','PAYROLL_PREPARER']
    when lower('Mariananadysmsm@gmail.com') then array['ATTENDANCE_OFFICER']
    when lower('amanyhussienelz@gmail.com') then array['DR_AMANY_APPROVER']
    else array['PAYROLL_CASHIER'] end)
) x(capability)
where lower(u.email) in (
  lower('rehab@midcairointernationalschool.com'),lower('Mariananadysmsm@gmail.com'),
  lower('amanyhussienelz@gmail.com'),lower('Mahmoudelsaid69000@gmail.com'),
  lower('ahmedshams79@gmail.com')
) on conflict(user_id,capability) do update set active=true,granted_at=now();

alter table public.payroll_runs
  add column if not exists prepared_at timestamptz,
  add column if not exists prepared_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists paid_at timestamptz,
  add column if not exists paid_by uuid references auth.users(id),
  add column if not exists supporting_document_url text;

update public.payroll_runs set prepared_at=coalesce(prepared_at,created_at),prepared_by=coalesce(prepared_by,created_by)
where prepared_at is null or prepared_by is null;

alter table public.payroll_runs drop constraint if exists payroll_runs_status_check;
alter table public.payroll_runs add constraint payroll_runs_status_check check(status in (
  'DRAFT','SUBMITTED','APPROVED','PAID','REJECTED','RETURNED_FOR_CORRECTION','REVERSED',
  'SUBMITTED_TO_HR_MANAGER','HR_MANAGER_APPROVED','AMANY_APPROVED','READY_FOR_PAYMENT'
));

create or replace function public.can_view_hr_payroll() returns boolean
language sql stable security definer set search_path='public','pg_temp' as $$
  select public.has_hr_capability('PAYROLL_PREPARER')
      or public.has_hr_capability('DR_AMANY_APPROVER')
      or public.has_hr_capability('PAYROLL_CASHIER')
$$;
revoke all on function public.can_view_hr_payroll() from public,anon;
grant execute on function public.can_view_hr_payroll() to authenticated;

drop policy if exists payroll_runs_read on public.payroll_runs;
create policy payroll_runs_read on public.payroll_runs for select to authenticated
using (public.can_view_hr_payroll() and
  (not public.has_hr_capability('PAYROLL_CASHIER') or status in ('APPROVED','PAID')));
drop policy if exists payroll_runs_insert on public.payroll_runs;
create policy payroll_runs_insert on public.payroll_runs for insert to authenticated
with check(public.has_hr_capability('PAYROLL_PREPARER') and status='DRAFT'
  and created_by=auth.uid() and coalesce(prepared_by,auth.uid())=auth.uid());
drop policy if exists payroll_runs_update_draft on public.payroll_runs;
create policy payroll_runs_update_draft on public.payroll_runs for update to authenticated
using(public.has_hr_capability('PAYROLL_PREPARER') and status in ('DRAFT','RETURNED_FOR_CORRECTION'))
with check(public.has_hr_capability('PAYROLL_PREPARER') and status in ('DRAFT','RETURNED_FOR_CORRECTION'));

drop policy if exists payroll_lines_read on public.payroll_lines;
create policy payroll_lines_read on public.payroll_lines for select to authenticated using(exists(
  select 1 from public.payroll_runs r where r.id=payroll_run_id and public.can_view_hr_payroll()
  and (not public.has_hr_capability('PAYROLL_CASHIER') or r.status in ('APPROVED','PAID'))));
drop policy if exists payroll_lines_write on public.payroll_lines;
create policy payroll_lines_write on public.payroll_lines for all to authenticated
using(public.has_hr_capability('PAYROLL_PREPARER') and exists(select 1 from public.payroll_runs r where r.id=payroll_run_id and r.status in ('DRAFT','RETURNED_FOR_CORRECTION')))
with check(public.has_hr_capability('PAYROLL_PREPARER') and exists(select 1 from public.payroll_runs r where r.id=payroll_run_id and r.status in ('DRAFT','RETURNED_FOR_CORRECTION')));
drop policy if exists payroll_payments_read on public.payroll_payments;
create policy payroll_payments_read on public.payroll_payments for select to authenticated
using(public.can_view_hr_payroll());

drop policy if exists hr_attendance_read on public.hr_attendance;
drop policy if exists hr_attendance_insert on public.hr_attendance;
drop policy if exists hr_attendance_update on public.hr_attendance;
create policy hr_attendance_read on public.hr_attendance for select to authenticated
using(public.has_hr_capability('ATTENDANCE_OFFICER') or public.has_hr_capability('BIOMETRIC_MANAGER'));
create policy hr_attendance_insert on public.hr_attendance for insert to authenticated
with check(public.has_hr_capability('ATTENDANCE_OFFICER'));
create policy hr_attendance_update on public.hr_attendance for update to authenticated
using(public.has_hr_capability('ATTENDANCE_OFFICER')) with check(public.has_hr_capability('ATTENDANCE_OFFICER'));

create or replace function public.hr_payroll_action(p_run uuid,p_action text,p_reason text default null)
returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.payroll_runs%rowtype; target text; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select * into r from public.payroll_runs where id=p_run for update;
 if not found then raise exception 'Payroll run not found'; end if;
 if upper(coalesce(p_action,'')) in ('APPROVE','REJECT') and not private.operational_control_enabled('payroll_approval_enabled') then
   raise exception 'Payroll approvals are disabled';
 end if;
 if p_action='SUBMIT' and r.status in ('DRAFT','RETURNED_FOR_CORRECTION')
    and public.has_hr_capability('PAYROLL_PREPARER') then
   if actor<>coalesce(r.prepared_by,r.created_by) then raise exception 'Only the preparer can submit this payroll'; end if;
   if nullif(btrim(r.supporting_document_url),'') is null then raise exception 'Payroll supporting document is required'; end if;
   target:='SUBMITTED';
 elsif p_action='APPROVE' and r.status='SUBMITTED' and public.has_hr_capability('DR_AMANY_APPROVER') then
   if actor in (r.prepared_by,r.submitted_by) then raise exception 'Separation of duties violation'; end if;
   target:='APPROVED';
 elsif p_action='REJECT' and r.status='SUBMITTED' and public.has_hr_capability('DR_AMANY_APPROVER') then
   if actor in (r.prepared_by,r.submitted_by) then raise exception 'Separation of duties violation'; end if;
   if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Rejection reason is required'; end if;
   target:='REJECTED';
 else raise exception 'Not authorized or invalid payroll transition'; end if;
 if target='SUBMITTED' then perform private.hr_include_movements(p_run); select * into r from public.payroll_runs where id=p_run; end if;
 perform set_config('bradford.hr_workflow','1',true);
 update public.payroll_runs set status=target,
   prepared_at=coalesce(prepared_at,created_at),prepared_by=coalesce(prepared_by,created_by),
   submitted_at=case when target='SUBMITTED' then now() else submitted_at end,
   submitted_by=case when target='SUBMITTED' then actor else submitted_by end,
   approved_at=case when target='APPROVED' then now() else approved_at end,
   approved_by=case when target='APPROVED' then actor else approved_by end,
   amany_approved_at=case when target='APPROVED' then now() else amany_approved_at end,
   amany_approved_by=case when target='APPROVED' then actor else amany_approved_by end,
   locked_at=case when target='APPROVED' then now() else locked_at end,
   rejection_reason=p_reason,updated_at=now(),updated_by=actor where id=p_run;
 if target='APPROVED' then
   update public.payroll_runs set journal_entry_id=private.hr_post_journal(p_run,'ACCRUAL') where id=p_run;
 end if;
 perform private.hr_audit('payroll_runs',p_run,p_action,to_jsonb(r),
   jsonb_build_object('status',target,'reason',p_reason,'actor',actor,'supporting_document_url',r.supporting_document_url));
end$$;

create or replace function public.hr_record_payroll_payment(p_run uuid,p_date date,p_method text,p_reference text,p_document_url text)
returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.payroll_runs%rowtype;pid uuid;jid uuid;actor uuid:=auth.uid();
begin
 if actor is null or not public.has_hr_capability('PAYROLL_CASHIER') then raise exception 'Payroll cashier capability required'; end if;
 select * into r from public.payroll_runs where id=p_run for update;
 if not found or r.status<>'APPROVED' then raise exception 'Payroll is not approved for payment'; end if;
 if actor in (r.prepared_by,r.submitted_by,r.approved_by) then raise exception 'Separation of duties violation'; end if;
 if p_method not in ('CASH','BANK') or nullif(btrim(p_reference),'') is null or nullif(btrim(p_document_url),'') is null then
   raise exception 'Payment method, reference and document are required'; end if;
 jid:=private.hr_post_journal(p_run,'PAYMENT',p_method);
 insert into public.payroll_payments(payroll_run_id,payment_date,payment_method,payment_reference,document_url,amount_piasters,journal_entry_id,created_by)
 values(p_run,p_date,p_method,btrim(p_reference),btrim(p_document_url),r.net_pay_piasters,jid,actor) returning id into pid;
 perform set_config('bradford.hr_workflow','1',true);
 update public.payroll_runs set status='PAID',paid_at=now(),paid_by=actor,locked_at=now(),updated_at=now(),updated_by=actor where id=p_run;
 perform private.hr_audit('payroll_payments',pid,'PAY',null,jsonb_build_object(
   'run_id',p_run,'amount',r.net_pay_piasters,'method',p_method,'reference',p_reference,
   'document_url',p_document_url,'paid_by',actor,'paid_at',now()));
 return pid;
end$$;

create or replace function private.hr_prepare_run_defaults() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then new.prepared_by:=coalesce(new.prepared_by,auth.uid());new.prepared_at:=coalesce(new.prepared_at,now());end if;
 return new;
end$$;
drop trigger if exists hr_prepare_run_defaults on public.payroll_runs;
create trigger hr_prepare_run_defaults before insert on public.payroll_runs for each row execute function private.hr_prepare_run_defaults();

create or replace function public.hr_confirm_biometric_import(p_batch uuid)
returns integer language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare b public.biometric_import_batches%rowtype;x record;rid bigint;done int:=0;
begin
 if not private.operational_control_enabled('biometric_sync_enabled') then raise exception 'Biometric synchronization is disabled'; end if;
 if not public.has_hr_capability('BIOMETRIC_MANAGER') then raise exception 'Biometric manager capability required'; end if;
 select * into b from public.biometric_import_batches where id=p_batch for update;
 if not found or b.status<>'PREVIEW' then raise exception 'Batch is not available for confirmation';end if;
 for x in select * from public.biometric_import_rows where batch_id=p_batch and validation_status='VALID' order by row_number loop
   insert into public.biometric_raw_logs(device_id,device_user_id,punch_time,punch_type,source_reference,import_batch_id,raw_payload)
   values(b.device_id,x.device_user_id,x.punch_time,x.punch_type,b.file_name,b.id,x.normalized_data)
   on conflict(device_id,device_user_id,punch_time,punch_type) do nothing returning id into rid;
   if rid is not null then update public.biometric_import_rows set raw_log_id=rid where id=x.id;done:=done+1;end if;rid:=null;
 end loop;
 update public.biometric_import_batches set status='CONFIRMED',accepted_count=done,confirmed_at=now(),confirmed_by=auth.uid() where id=b.id;
 perform private.hr_audit('biometric_import_batches',b.id,'CONFIRM',to_jsonb(b),jsonb_build_object('imported',done));return done;
end$$;

revoke all on function private.hr_prepare_run_defaults() from public,anon,authenticated;
revoke all on function public.hr_payroll_action(uuid,text,text),public.hr_record_payroll_payment(uuid,date,text,text,text),public.hr_confirm_biometric_import(uuid) from public,anon;
grant execute on function public.hr_payroll_action(uuid,text,text),public.hr_record_payroll_payment(uuid,date,text,text,text),public.hr_confirm_biometric_import(uuid) to authenticated;

-- The payroll flag is deliberately not enabled by this migration. It is enabled
-- only after the isolated Staging UAT succeeds. Biometric sync remains disabled.
insert into public.finance_settings(key,value,description) values
 ('payroll_approval_enabled','false'::jsonb,'Enabled only after final separated-duty Staging UAT.'),
 ('biometric_sync_enabled','false'::jsonb,'Requires a connected ZKTeco device and one verified real punch.')
on conflict(key) do update set value=excluded.value,description=excluded.description,updated_at=now(),updated_by=null;

insert into public.hr_audit_events(table_name,record_id,action,new_data,changed_by)
select 'user_profiles',u.id::text,'FINAL_HR_ROLE_ASSIGNED',jsonb_build_object('email',lower(u.email),'role',p.role::text),null
from auth.users u join public.user_profiles p on p.user_id=u.id
where lower(u.email) in (lower('rehab@midcairointernationalschool.com'),lower('Mariananadysmsm@gmail.com'),lower('amanyhussienelz@gmail.com'),lower('Mahmoudelsaid69000@gmail.com'),lower('ahmedshams79@gmail.com'));

commit;
