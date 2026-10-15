-- Attendance spreadsheet import that does not require a live biometric device.
-- The source file is parsed in the authenticated client, validated server-side,
-- and only confirmed punches can produce calculated attendance and DRAFT payroll movements.

create table if not exists public.hr_attendance_file_batches (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  source_format text not null check (source_format in ('CSV','XLS','XLSX')),
  status text not null default 'PREVIEW' check (status in ('PREVIEW','CONFIRMED','REJECTED')),
  total_rows integer not null default 0,
  valid_rows integer not null default 0,
  duplicate_rows integer not null default 0,
  unlinked_rows integer not null default 0,
  invalid_rows integer not null default 0,
  column_mapping jsonb not null default '{}'::jsonb,
  validation_result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  confirmed_at timestamptz,
  confirmed_by uuid references auth.users(id),
  unique (sha256, created_by)
);

create table if not exists public.hr_attendance_file_rows (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.hr_attendance_file_batches(id),
  row_number integer not null check (row_number > 0),
  employee_code text,
  employee_id uuid references public.hr_employees(id),
  punch_time timestamptz,
  punch_type text check (punch_type in ('IN','OUT','AUTO')),
  validation_status text not null check (validation_status in ('VALID','DUPLICATE','UNLINKED','INVALID')),
  validation_errors text[] not null default '{}',
  normalized_data jsonb not null default '{}'::jsonb,
  imported_punch_id bigint,
  created_at timestamptz not null default now(),
  unique (batch_id, row_number)
);

create table if not exists public.hr_attendance_file_punches (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.hr_attendance_file_batches(id),
  source_row_id bigint not null unique references public.hr_attendance_file_rows(id),
  employee_id uuid not null references public.hr_employees(id),
  punch_time timestamptz not null,
  punch_type text not null check (punch_type in ('IN','OUT','AUTO')),
  source_file_name text not null,
  imported_at timestamptz not null default now(),
  imported_by uuid not null references auth.users(id),
  raw_payload jsonb not null default '{}'::jsonb,
  unique (employee_id, punch_time, punch_type)
);

alter table public.hr_attendance_file_batches enable row level security;
alter table public.hr_attendance_file_rows enable row level security;
alter table public.hr_attendance_file_punches enable row level security;

revoke all on public.hr_attendance_file_batches, public.hr_attendance_file_rows,
  public.hr_attendance_file_punches from anon, authenticated;
grant select on public.hr_attendance_file_batches, public.hr_attendance_file_rows,
  public.hr_attendance_file_punches to authenticated;

create policy attendance_file_batches_read on public.hr_attendance_file_batches
for select to authenticated using (
  public.has_hr_capability('ATTENDANCE_OFFICER')
  or public.has_hr_capability('BIOMETRIC_MANAGER')
  or public.current_finance_role() = 'OWNER'
);
create policy attendance_file_rows_read on public.hr_attendance_file_rows
for select to authenticated using (exists (
  select 1 from public.hr_attendance_file_batches b where b.id = batch_id
));
create policy attendance_file_punches_read on public.hr_attendance_file_punches
for select to authenticated using (
  public.has_hr_capability('ATTENDANCE_OFFICER')
  or public.has_hr_capability('BIOMETRIC_MANAGER')
  or public.current_finance_role() = 'OWNER'
);

create or replace function private.attendance_file_punch_immutable()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'Confirmed attendance file punches cannot be changed or deleted';
end$$;
drop trigger if exists attendance_file_punch_immutable on public.hr_attendance_file_punches;
create trigger attendance_file_punch_immutable before update or delete
on public.hr_attendance_file_punches for each row
execute function private.attendance_file_punch_immutable();

create or replace function public.hr_preview_attendance_file(
  p_file_name text,
  p_sha256 text,
  p_source_format text,
  p_column_mapping jsonb,
  p_rows jsonb
) returns uuid
language plpgsql security definer set search_path = 'public','private','pg_temp' as $$
declare
  v_batch uuid; v_row jsonb; v_number integer := 0; v_code text; v_time timestamptz;
  v_type text; v_employee uuid; v_state text; v_errors text[];
  v_valid integer := 0; v_duplicate integer := 0; v_unlinked integer := 0; v_invalid integer := 0;
begin
  if auth.uid() is null or not (
    public.has_hr_capability('ATTENDANCE_OFFICER')
    or public.has_hr_capability('BIOMETRIC_MANAGER')
  ) then raise exception 'Attendance import permission required'; end if;
  if lower(coalesce(p_sha256,'')) !~ '^[0-9a-f]{64}$' then raise exception 'Valid SHA-256 is required'; end if;
  if upper(coalesce(p_source_format,'')) not in ('CSV','XLS','XLSX') then raise exception 'CSV or Excel file required'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 20000 then
    raise exception 'File must contain between 1 and 20000 rows';
  end if;
  insert into public.hr_attendance_file_batches(file_name,sha256,source_format,column_mapping,created_by)
  values(left(btrim(p_file_name),240),lower(p_sha256),upper(p_source_format),coalesce(p_column_mapping,'{}'),auth.uid())
  on conflict(sha256,created_by) do update set file_name=excluded.file_name
  returning id into v_batch;
  if (select status from public.hr_attendance_file_batches where id=v_batch) <> 'PREVIEW' then
    raise exception 'This file was already confirmed';
  end if;
  delete from public.hr_attendance_file_rows where batch_id=v_batch;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_number := v_number + 1; v_errors := '{}'; v_employee := null;
    v_code := nullif(btrim(v_row->>'employee_code'),'');
    begin v_time := nullif(v_row->>'punch_time','')::timestamptz; exception when others then v_time := null; end;
    v_type := upper(coalesce(nullif(btrim(v_row->>'punch_type'),''),'AUTO'));
    if v_type not in ('IN','OUT','AUTO') then v_type := 'AUTO'; end if;
    if v_code is null or v_time is null then
      v_state := 'INVALID'; v_invalid := v_invalid + 1;
      v_errors := array['employee_code and valid punch_time are required'];
    else
      select id into v_employee from public.hr_employees where upper(employee_code)=upper(v_code) and status <> 'TERMINATED' limit 1;
      if v_employee is null then
        v_state := 'UNLINKED'; v_unlinked := v_unlinked + 1; v_errors := array['employee_code was not found'];
      elsif exists(select 1 from public.hr_attendance_file_punches p where p.employee_id=v_employee and p.punch_time=v_time and p.punch_type=v_type)
         or exists(select 1 from public.hr_attendance_file_rows r where r.batch_id=v_batch and r.employee_id=v_employee and r.punch_time=v_time and r.punch_type=v_type) then
        v_state := 'DUPLICATE'; v_duplicate := v_duplicate + 1;
      else v_state := 'VALID'; v_valid := v_valid + 1; end if;
    end if;
    insert into public.hr_attendance_file_rows(batch_id,row_number,employee_code,employee_id,punch_time,punch_type,validation_status,validation_errors,normalized_data)
    values(v_batch,v_number,v_code,v_employee,v_time,v_type,v_state,v_errors,v_row);
  end loop;
  update public.hr_attendance_file_batches set total_rows=v_number,valid_rows=v_valid,duplicate_rows=v_duplicate,
    unlinked_rows=v_unlinked,invalid_rows=v_invalid,
    validation_result=jsonb_build_object('validated_server_side',true,'financial_effect',false,'requires_confirmation',true)
  where id=v_batch;
  perform private.hr_audit('hr_attendance_file_batches',v_batch,'PREVIEW',null,
    jsonb_build_object('file_name',left(p_file_name,240),'valid',v_valid,'duplicates',v_duplicate,'unlinked',v_unlinked,'invalid',v_invalid));
  return v_batch;
end$$;

create or replace function public.hr_confirm_attendance_file(p_batch uuid)
returns jsonb
language plpgsql security definer set search_path = 'public','private','pg_temp' as $$
declare
  v_batch public.hr_attendance_file_batches%rowtype; v_row record; v_punch bigint;
  v_imported integer := 0; v_days integer := 0; v_movements integer := 0; v_daily uuid;
  v_day record; v_schedule public.hr_work_schedules%rowtype; v_first_local time; v_last_local time;
  v_worked integer; v_late integer; v_early integer; v_overtime integer; v_status text;
begin
  if auth.uid() is null or not public.has_hr_capability('BIOMETRIC_MANAGER') then
    raise exception 'HR biometric manager confirmation required';
  end if;
  select * into v_batch from public.hr_attendance_file_batches where id=p_batch for update;
  if not found or v_batch.status <> 'PREVIEW' then raise exception 'Preview batch is not available'; end if;
  for v_row in select * from public.hr_attendance_file_rows where batch_id=p_batch and validation_status='VALID' order by row_number loop
    insert into public.hr_attendance_file_punches(batch_id,source_row_id,employee_id,punch_time,punch_type,source_file_name,imported_by,raw_payload)
    values(p_batch,v_row.id,v_row.employee_id,v_row.punch_time,v_row.punch_type,v_batch.file_name,auth.uid(),v_row.normalized_data)
    on conflict(employee_id,punch_time,punch_type) do nothing returning id into v_punch;
    if v_punch is not null then update public.hr_attendance_file_rows set imported_punch_id=v_punch where id=v_row.id; v_imported:=v_imported+1; end if;
    v_punch := null;
  end loop;
  for v_day in
    select p.employee_id,(p.punch_time at time zone 'Africa/Cairo')::date attendance_date,
      min(p.punch_time) first_in,max(p.punch_time) last_out,array_agg(p.id order by p.punch_time) log_ids,count(*) punch_count
    from public.hr_attendance_file_punches p where p.batch_id=p_batch
    group by p.employee_id,(p.punch_time at time zone 'Africa/Cairo')::date
  loop
    select s.* into v_schedule from public.hr_work_schedules s join public.hr_employees e on e.id=v_day.employee_id
    where s.active and v_day.attendance_date between s.valid_from and coalesce(s.valid_to,'infinity'::date)
      and extract(dow from v_day.attendance_date)::integer=any(s.working_days)
      and (s.employee_id=v_day.employee_id or (s.employee_id is null and (s.department is null or s.department=e.department)))
    order by (s.employee_id is not null) desc,(s.department is not null) desc,s.valid_from desc limit 1;
    v_first_local := (v_day.first_in at time zone 'Africa/Cairo')::time;
    v_last_local := (v_day.last_out at time zone 'Africa/Cairo')::time;
    v_worked := case when v_day.punch_count>1 then greatest(0,floor(extract(epoch from (v_day.last_out-v_day.first_in))/60)::integer) else 0 end;
    if v_schedule.id is null then v_late:=0;v_early:=0;v_overtime:=0;v_status:='NEEDS_SCHEDULE';
    else
      v_late:=greatest(0,floor(extract(epoch from (v_first_local-v_schedule.check_in))/60)::integer-v_schedule.grace_minutes);
      v_early:=greatest(0,floor(extract(epoch from (v_schedule.check_out-v_last_local))/60)::integer);
      v_overtime:=greatest(0,floor(extract(epoch from (v_last_local-v_schedule.check_out))/60)::integer);
      v_status:=case when v_day.punch_count=1 then 'MISSING_PUNCH' else 'ATTENDANCE_CALCULATED' end;
    end if;
    insert into public.hr_daily_attendance(employee_id,attendance_date,first_in,last_out,worked_minutes,late_minutes,early_leave_minutes,overtime_minutes,
      missing_in,missing_out,status,notes,source_log_ids,updated_at)
    values(v_day.employee_id,v_day.attendance_date,v_day.first_in,case when v_day.punch_count>1 then v_day.last_out end,v_worked,v_late,v_early,v_overtime,
      false,v_day.punch_count=1,v_status,case when v_schedule.id is null then 'جدول دوام مطلوب قبل حساب التأخير والإضافي' else 'محسوب من شيت البصمة: '||v_batch.file_name end,
      v_day.log_ids,now())
    on conflict(employee_id,attendance_date) do update set first_in=excluded.first_in,last_out=excluded.last_out,worked_minutes=excluded.worked_minutes,
      late_minutes=excluded.late_minutes,early_leave_minutes=excluded.early_leave_minutes,overtime_minutes=excluded.overtime_minutes,
      missing_out=excluded.missing_out,status=excluded.status,notes=excluded.notes,source_log_ids=excluded.source_log_ids,updated_at=now()
    returning id into v_daily;
    v_days:=v_days+1;
    if v_late>0 then insert into public.hr_employee_movements(employee_id,occurred_at,movement_type,minutes,description,source_type,source_record_id,status,created_by,updated_by)
      values(v_day.employee_id,v_day.first_in,'LATE',v_late,'محسوب من شيت البصمة؛ القيمة المالية تراجعها HR','BIOMETRIC',v_daily::text,'DRAFT',auth.uid(),auth.uid())
      on conflict do nothing; if found then v_movements:=v_movements+1;end if; end if;
    if v_early>0 then insert into public.hr_employee_movements(employee_id,occurred_at,movement_type,minutes,description,source_type,source_record_id,status,created_by,updated_by)
      values(v_day.employee_id,v_day.last_out,'EARLY_LEAVE',v_early,'محسوب من شيت البصمة؛ القيمة المالية تراجعها HR','BIOMETRIC',v_daily::text,'DRAFT',auth.uid(),auth.uid())
      on conflict do nothing; if found then v_movements:=v_movements+1;end if; end if;
    if v_overtime>0 then insert into public.hr_employee_movements(employee_id,occurred_at,movement_type,hours,description,source_type,source_record_id,status,created_by,updated_by)
      values(v_day.employee_id,v_day.last_out,'OVERTIME',round(v_overtime::numeric/60,2),'محسوب من شيت البصمة؛ القيمة المالية تراجعها HR','BIOMETRIC',v_daily::text,'DRAFT',auth.uid(),auth.uid())
      on conflict do nothing; if found then v_movements:=v_movements+1;end if; end if;
  end loop;
  update public.hr_attendance_file_batches set status='CONFIRMED',confirmed_at=now(),confirmed_by=auth.uid(),valid_rows=v_imported where id=p_batch;
  perform private.hr_audit('hr_attendance_file_batches',p_batch,'CONFIRM',to_jsonb(v_batch),
    jsonb_build_object('imported_punches',v_imported,'attendance_days',v_days,'draft_movements',v_movements,'financial_effect',false));
  return jsonb_build_object('imported_punches',v_imported,'attendance_days',v_days,'draft_movements',v_movements,'financial_effect',false);
end$$;

create unique index if not exists hr_movement_attendance_source_unique
on public.hr_employee_movements(source_type,source_record_id,movement_type)
where source_type='BIOMETRIC' and source_record_id is not null;
create index if not exists attendance_file_rows_batch_status_idx on public.hr_attendance_file_rows(batch_id,validation_status);
create index if not exists attendance_file_punches_employee_time_idx on public.hr_attendance_file_punches(employee_id,punch_time);

revoke all on function private.attendance_file_punch_immutable() from public,anon,authenticated;
revoke all on function public.hr_preview_attendance_file(text,text,text,jsonb,jsonb),public.hr_confirm_attendance_file(uuid) from public,anon;
grant execute on function public.hr_preview_attendance_file(text,text,text,jsonb,jsonb),public.hr_confirm_attendance_file(uuid) to authenticated;

comment on function public.hr_confirm_attendance_file(uuid) is
'Confirms validated spreadsheet punches, calculates attendance and creates zero-value DRAFT movements. It never posts payroll or financial entries.';
