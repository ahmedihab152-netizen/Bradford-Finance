create table public.hr_employee_movements(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 occurred_at timestamptz not null,movement_type text not null check(movement_type in ('ATTENDANCE','ABSENCE_UNEXCUSED','ABSENCE_EXCUSED','PAID_LEAVE','UNPAID_LEAVE','LATE','EARLY_LEAVE','MISSING_PUNCH','MISSED_CLASS','LATE_TO_CLASS','MISSED_DUTY','MISSION','HOURLY_PERMISSION','ADMIN_PENALTY','MANUAL_DEDUCTION','BONUS','OVERTIME','COVER')),
 days numeric(8,2) not null default 0,minutes integer not null default 0,hours numeric(8,2) not null default 0,period_number text,class_grade text,class_section text,subject text,
 proposed_amount_piasters bigint not null default 0,approved_amount_piasters bigint,description text,notes text,document_url text,
 source_type text not null default 'MANUAL' check(source_type in ('MANUAL','BIOMETRIC','MISSING_PUNCH_REQUEST')),
 source_record_id text,status text not null default 'DRAFT' check(status in ('DRAFT','SUBMITTED_TO_HR','HR_MANAGER_APPROVED','INCLUDED_IN_PAYROLL','REJECTED','RETURNED_FOR_CORRECTION','CANCELLED_BEFORE_APPROVAL')),
 review_reason text,included_payroll_run_id uuid references public.payroll_runs(id),created_at timestamptz not null default now(),created_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),updated_by uuid references auth.users(id),reviewed_at timestamptz,reviewed_by uuid references auth.users(id)
);
create index hr_movements_employee_date_idx on public.hr_employee_movements(employee_id,occurred_at desc);
create index hr_movements_status_date_idx on public.hr_employee_movements(status,occurred_at desc);

create table public.biometric_devices(
 id uuid primary key default gen_random_uuid(),device_name text not null,manufacturer text,model text,serial_number text not null unique,branch text,location text,ip_address inet,timezone text not null default 'Africa/Cairo',connection_status text not null default 'UNKNOWN',last_sync_at timestamptz,integration_method text not null check(integration_method in ('FILE_IMPORT','LOCAL_SYNC_AGENT','CLOUD_API')),active boolean not null default true,created_at timestamptz not null default now(),created_by uuid references auth.users(id),updated_at timestamptz not null default now(),updated_by uuid references auth.users(id)
);
create table public.biometric_employee_links(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),employee_code text not null,biometric_device_user_id text not null,device_id uuid not null references public.biometric_devices(id),active boolean not null default true,created_at timestamptz not null default now(),created_by uuid references auth.users(id),unique(device_id,biometric_device_user_id),unique(device_id,employee_id)
);
create table public.biometric_import_batches(
 id uuid primary key default gen_random_uuid(),file_name text not null,sha256 text,device_id uuid references public.biometric_devices(id),status text not null default 'PREVIEW' check(status in ('PREVIEW','CONFIRMED','REJECTED')),column_mapping jsonb not null default '{}'::jsonb,accepted_count integer not null default 0,rejected_count integer not null default 0,duplicate_count integer not null default 0,validation_result jsonb not null default '{}'::jsonb,created_at timestamptz not null default now(),created_by uuid references auth.users(id),confirmed_at timestamptz,confirmed_by uuid references auth.users(id)
);
create table public.biometric_raw_logs(
 id bigint generated always as identity primary key,device_id uuid not null references public.biometric_devices(id),device_user_id text not null,punch_time timestamptz not null,punch_type text,verification_method text,source_reference text,import_batch_id uuid references public.biometric_import_batches(id),imported_at timestamptz not null default now(),raw_payload jsonb not null default '{}'::jsonb,unique(device_id,device_user_id,punch_time,punch_type)
);
create table public.hr_work_schedules(
 id uuid primary key default gen_random_uuid(),schedule_name text not null,department text,employee_id uuid references public.hr_employees(id),valid_from date not null,valid_to date,check_in time not null,check_out time not null,grace_minutes integer not null default 0,working_days integer[] not null default array[0,1,2,3,4],shift_name text,ramadan boolean not null default false,flexible boolean not null default false,overtime_rule jsonb not null default '{}'::jsonb,active boolean not null default true,created_at timestamptz not null default now(),created_by uuid references auth.users(id)
);
create table public.hr_holidays(id uuid primary key default gen_random_uuid(),holiday_date date not null unique,holiday_name text not null,created_at timestamptz not null default now(),created_by uuid references auth.users(id));
create table public.hr_daily_attendance(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),attendance_date date not null,first_in timestamptz,last_out timestamptz,worked_minutes integer not null default 0,late_minutes integer not null default 0,early_leave_minutes integer not null default 0,overtime_minutes integer not null default 0,missing_in boolean not null default false,missing_out boolean not null default false,absent boolean not null default false,rest_day boolean not null default false,holiday boolean not null default false,status text not null default 'ATTENDANCE_CALCULATED',notes text,source_log_ids bigint[] not null default '{}',reviewed_at timestamptz,reviewed_by uuid references auth.users(id),approved_at timestamptz,approved_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(employee_id,attendance_date)
);
create table public.hr_missing_punch_requests(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),attendance_date date not null,requested_time timestamptz not null,request_type text not null check(request_type in ('MISSING_IN','MISSING_OUT')),reason text not null,document_url text,manager_confirmed_at timestamptz,manager_confirmed_by uuid references auth.users(id),status text not null default 'SUBMITTED',hr_review_reason text,created_at timestamptz not null default now(),created_by uuid not null references auth.users(id)
);

create or replace function private.hr_movement_guard() returns trigger language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare role_now public.finance_role:=public.current_finance_role();workflow boolean:=current_setting('bradford.hr_movement_workflow',true)='1';
begin
 if tg_op='DELETE' then raise exception 'Employee movements are immutable; cancel or adjust instead';end if;
 if old.status='INCLUDED_IN_PAYROLL' then raise exception 'Movement already included in payroll; create an adjustment';end if;
 if not workflow and role_now='HR_OFFICER' and old.status not in ('DRAFT','RETURNED_FOR_CORRECTION') then raise exception 'HR Officer can edit drafts only';end if;
 if new.status is distinct from old.status and not workflow then raise exception 'Use HR movement workflow';end if;
 new.updated_at:=now();new.updated_by:=auth.uid();return new;
end$$;
create trigger hr_movement_guard before update or delete on public.hr_employee_movements for each row execute function private.hr_movement_guard();
create or replace function private.biometric_raw_immutable() returns trigger language plpgsql as $$begin raise exception 'Raw biometric logs cannot be changed or deleted';end$$;
create trigger biometric_raw_immutable before update or delete on public.biometric_raw_logs for each row execute function private.biometric_raw_immutable();

create or replace function public.hr_movement_action(p_id uuid,p_action text,p_reason text default null,p_approved_amount_piasters bigint default null) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare m public.hr_employee_movements%rowtype;target text;role_now public.finance_role:=public.current_finance_role();
begin
 select * into m from public.hr_employee_movements where id=p_id for update;if not found then raise exception 'Movement not found';end if;
 if p_action='SUBMIT' and role_now in ('HR_OFFICER','HR_MANAGER') and m.status in ('DRAFT','RETURNED_FOR_CORRECTION') then target:='SUBMITTED_TO_HR';
 elsif p_action='APPROVE' and role_now='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') and m.status='SUBMITTED_TO_HR' then target:='HR_MANAGER_APPROVED';
 elsif p_action='RETURN' and role_now='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') and m.status='SUBMITTED_TO_HR' then target:='RETURNED_FOR_CORRECTION';
 elsif p_action='REJECT' and role_now='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') and m.status='SUBMITTED_TO_HR' then target:='REJECTED';
 elsif p_action='CANCEL' and role_now in ('HR_OFFICER','HR_MANAGER') and m.status in ('DRAFT','RETURNED_FOR_CORRECTION') then target:='CANCELLED_BEFORE_APPROVAL';
 else raise exception 'Not authorized or invalid movement transition';end if;
 if target in ('RETURNED_FOR_CORRECTION','REJECTED') and length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reason required';end if;
 perform set_config('bradford.hr_movement_workflow','1',true);
 update public.hr_employee_movements set status=target,review_reason=p_reason,approved_amount_piasters=case when target='HR_MANAGER_APPROVED' then coalesce(p_approved_amount_piasters,proposed_amount_piasters) else approved_amount_piasters end,reviewed_at=case when target in ('HR_MANAGER_APPROVED','RETURNED_FOR_CORRECTION','REJECTED') then now() else reviewed_at end,reviewed_by=case when target in ('HR_MANAGER_APPROVED','RETURNED_FOR_CORRECTION','REJECTED') then auth.uid() else reviewed_by end where id=p_id;
 perform private.hr_audit('hr_employee_movements',p_id,p_action,to_jsonb(m),jsonb_build_object('status',target,'reason',p_reason,'approved_amount_piasters',p_approved_amount_piasters));
end$$;

create or replace function private.hr_include_movements(p_run uuid) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.payroll_runs%rowtype;
begin
 select * into r from public.payroll_runs where id=p_run;
 with a as(select employee_id,
  sum(case when movement_type='BONUS' then approved_amount_piasters else 0 end) bonus,
  sum(case when movement_type='OVERTIME' then approved_amount_piasters else 0 end) overtime,
  sum(case when movement_type='COVER' then approved_amount_piasters else 0 end) cover,
  sum(case when movement_type in ('ABSENCE_UNEXCUSED','UNPAID_LEAVE') then approved_amount_piasters else 0 end) absence,
  sum(case when movement_type='LATE' then approved_amount_piasters else 0 end) late,
  sum(case when movement_type='EARLY_LEAVE' then approved_amount_piasters else 0 end) early,
  sum(case when movement_type in ('ADMIN_PENALTY','MANUAL_DEDUCTION','MISSED_CLASS','LATE_TO_CLASS','MISSED_DUTY') then approved_amount_piasters else 0 end) penalty
 from public.hr_employee_movements where status='HR_MANAGER_APPROVED' and date_trunc('month',occurred_at)=r.payroll_month group by employee_id)
 update public.payroll_lines l set bonuses_piasters=l.bonuses_piasters+a.bonus,overtime_piasters=l.overtime_piasters+a.overtime,cover_piasters=l.cover_piasters+a.cover,absence_piasters=l.absence_piasters+a.absence,late_piasters=l.late_piasters+a.late,early_leave_piasters=l.early_leave_piasters+a.early,penalties_piasters=l.penalties_piasters+a.penalty from a where l.payroll_run_id=p_run and l.employee_id=a.employee_id;
 perform set_config('bradford.hr_movement_workflow','1',true);
 update public.hr_employee_movements set status='INCLUDED_IN_PAYROLL',included_payroll_run_id=p_run where status='HR_MANAGER_APPROVED' and date_trunc('month',occurred_at)=r.payroll_month and exists(select 1 from public.payroll_lines l where l.payroll_run_id=p_run and l.employee_id=hr_employee_movements.employee_id);
end$$;
create or replace function private.hr_include_before_submit() returns trigger language plpgsql security definer set search_path='public','private','pg_temp' as $$begin if new.status='SUBMITTED_TO_HR_MANAGER' and old.status in ('DRAFT','RETURNED_FOR_CORRECTION') then perform private.hr_include_movements(new.id);end if;return new;end$$;

do $$declare t text;begin foreach t in array array['hr_employee_movements','biometric_devices','biometric_employee_links','biometric_import_batches','biometric_raw_logs','hr_work_schedules','hr_holidays','hr_daily_attendance','hr_missing_punch_requests'] loop execute format('alter table public.%I enable row level security',t);end loop;end$$;
create policy hr_movements_read on public.hr_employee_movements for select to authenticated using(public.current_finance_role() in ('OWNER','HR_MANAGER','HR_OFFICER'));
create policy hr_movements_insert on public.hr_employee_movements for insert to authenticated with check(public.current_finance_role() in ('HR_MANAGER','HR_OFFICER') and status='DRAFT' and created_by=auth.uid());
create policy hr_movements_update on public.hr_employee_movements for update to authenticated using(public.current_finance_role() in ('HR_MANAGER','HR_OFFICER')) with check(public.current_finance_role() in ('HR_MANAGER','HR_OFFICER'));
do $$declare t text;begin foreach t in array array['biometric_devices','biometric_employee_links','biometric_import_batches','hr_work_schedules','hr_holidays','hr_daily_attendance','hr_missing_punch_requests'] loop execute format('create policy %I on public.%I for select to authenticated using(public.current_finance_role() in (''OWNER'',''HR_MANAGER'',''HR_OFFICER''))',t||'_read',t);execute format('create policy %I on public.%I for insert to authenticated with check(public.current_finance_role() in (''HR_MANAGER'',''HR_OFFICER''))',t||'_insert',t);execute format('create policy %I on public.%I for update to authenticated using(public.current_finance_role() in (''HR_MANAGER'',''HR_OFFICER'')) with check(public.current_finance_role() in (''HR_MANAGER'',''HR_OFFICER''))',t||'_update',t);end loop;end$$;
create policy biometric_raw_read on public.biometric_raw_logs for select to authenticated using(public.current_finance_role() in ('OWNER','HR_MANAGER','HR_OFFICER'));
create policy biometric_raw_insert on public.biometric_raw_logs for insert to authenticated with check(public.current_finance_role() in ('HR_MANAGER','HR_OFFICER'));

grant select,insert,update on public.hr_employee_movements,public.biometric_devices,public.biometric_employee_links,public.biometric_import_batches,public.hr_work_schedules,public.hr_holidays,public.hr_daily_attendance,public.hr_missing_punch_requests to authenticated;
grant select,insert on public.biometric_raw_logs to authenticated;grant usage,select on sequence public.biometric_raw_logs_id_seq to authenticated;
revoke all on function public.hr_movement_action(uuid,text,text,bigint) from public,anon;grant execute on function public.hr_movement_action(uuid,text,text,bigint) to authenticated;
