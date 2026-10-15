-- Bradford attendance policy supplied by management on 2026-10-15.
-- Additive and financially inert: classifications create DRAFT movements only.

create table if not exists public.hr_attendance_policy_rules (
  rule_code text primary key,
  category text not null,
  definition_ar text not null,
  definition_en text not null,
  min_minutes integer,
  max_minutes integer,
  occurrence_from integer,
  occurrence_to integer,
  deduction_percent_daily numeric(6,2) not null default 0 check (deduction_percent_daily between 0 and 1000),
  deduction_days numeric(6,2) not null default 0 check (deduction_days between 0 and 100),
  consequence_ar text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.hr_attendance_policy_rules
(rule_code,category,definition_ar,definition_en,min_minutes,max_minutes,occurrence_from,occurrence_to,deduction_percent_daily,deduction_days,consequence_ar)
values
 ('ON_DUTY','EXCUSE','مأمورية عمل','On-duty excuse',null,null,null,null,0,0,'بدون خصم'),
 ('EXEMPTED','EXCUSE','إعفاء يوم كامل أو نصف يوم','Full-day / half-day excuse',null,null,null,null,0,0,'بدون خصم'),
 ('ABSENCE_INFORMED','ABSENCE','غياب بإخطار','Informed absence',null,null,null,null,0,1,'خصم أجر يوم عن كل يوم غياب'),
 ('ABSENCE_INFORMED_GT5','ABSENCE','غياب متصل بإخطار أكثر من 5 أيام','Consecutive informed absence over 5 days',null,null,6,null,0,2,'خصم أجر يومين عن كل يوم'),
 ('ABSENCE_UNEXCUSED','ABSENCE','غياب بدون عذر','Unexcused absence',null,null,null,null,0,2,'خصم أجر يومين عن كل يوم غياب'),
 ('ABSENCE_UNEXCUSED_GT5','ABSENCE','غياب متصل بدون عذر أكثر من 5 أيام','Consecutive unexcused absence over 5 days',null,null,6,null,0,10,'تنبيه كتابي قبل إنهاء التعاقد؛ يلزم قرار HR'),
 ('ABSENCE_ANY_10','ABSENCE','غياب متصل بإخطار أو بدون عذر لمدة 10 أيام','Consecutive absence for 10 days',null,null,10,null,0,0,'إيقاف المرتب وإخطار إنهاء التعاقد؛ يلزم قرار HR وقانوني'),
 ('LATE_EARLY_04_10','LATE_EARLY','تأخير أو خروج مبكر 4–10 دقائق','Late arrival or early leave 4–10 minutes',4,10,null,null,5,0,'خصم 5% من الأجر اليومي'),
 ('LATE_EARLY_11_20','LATE_EARLY','تأخير أو خروج مبكر 11–20 دقيقة','Late arrival or early leave 11–20 minutes',11,20,null,null,10,0,'خصم 10% من الأجر اليومي'),
 ('LATE_EARLY_21_60','LATE_EARLY','تأخير أو خروج مبكر 21–60 دقيقة','Late arrival or early leave 21–60 minutes',21,60,null,null,20,0,'خصم 20% من الأجر اليومي'),
 ('LATE_EARLY_61_90','LATE_EARLY','تأخير أو خروج مبكر 61–90 دقيقة','Late arrival or early leave 61–90 minutes',61,90,null,null,30,0,'خصم 30% من الأجر اليومي'),
 ('LATE_EARLY_91_150','LATE_EARLY','تأخير أو خروج مبكر 91–150 دقيقة','Late arrival or early leave 91–150 minutes',91,150,null,null,40,0,'خصم 40% من الأجر اليومي'),
 ('LATE_EARLY_GT150','LATE_EARLY','تأخير أو خروج مبكر أكثر من 150 دقيقة','Late arrival or early leave over 150 minutes',151,null,null,null,50,0,'خصم 50% من الأجر اليومي'),
 ('PERMISSION_01_02','PERMISSION','أول وثاني إذن تأخير أو خروج مبكر في الفصل الدراسي','First and second late/early permission per term',null,null,1,2,0,0,'بدون خصم'),
 ('PERMISSION_03','PERMISSION','الإذن الثالث في الفصل الدراسي','Third late/early permission per term',null,null,3,3,20,0,'خصم 20% من الأجر اليومي'),
 ('PERMISSION_04','PERMISSION','الإذن الرابع في الفصل الدراسي','Fourth late/early permission per term',null,null,4,4,30,0,'خصم 30% من الأجر اليومي'),
 ('PERMISSION_05_PLUS','PERMISSION','الإذن الخامس وما بعده في الفصل الدراسي','Fifth and later late/early permission per term',null,null,5,null,40,0,'خصم 40% من الأجر اليومي'),
 ('MISSING_PUNCH','MISSING_PUNCH','عدم وجود بصمة دخول أو خروج','No sign-in or no sign-out',null,null,null,null,20,0,'خصم 20% من الأجر اليومي')
on conflict (rule_code) do update set
 category=excluded.category,definition_ar=excluded.definition_ar,definition_en=excluded.definition_en,
 min_minutes=excluded.min_minutes,max_minutes=excluded.max_minutes,
 occurrence_from=excluded.occurrence_from,occurrence_to=excluded.occurrence_to,
 deduction_percent_daily=excluded.deduction_percent_daily,deduction_days=excluded.deduction_days,
 consequence_ar=excluded.consequence_ar,updated_at=now();

alter table public.hr_employee_movements add column if not exists policy_rule_code text references public.hr_attendance_policy_rules(rule_code);
alter table public.hr_employee_movements add column if not exists calculation_metadata jsonb not null default '{}'::jsonb;
alter table public.hr_holidays add column if not exists source_type text not null default 'MANUAL' check (source_type in ('MANUAL','NO_PUNCH_DAY'));
alter table public.hr_holidays add column if not exists source_batch_id uuid references public.hr_attendance_file_batches(id);

alter table public.hr_attendance_policy_rules enable row level security;
revoke all on public.hr_attendance_policy_rules from public,anon,authenticated;
grant select on public.hr_attendance_policy_rules to authenticated;
create policy attendance_policy_read on public.hr_attendance_policy_rules for select to authenticated
using (public.current_finance_role() in ('OWNER','HR_MANAGER','HR_OFFICER','DR_AMANY_APPROVER'));

create or replace function private.attendance_rule_for_minutes(p_minutes integer)
returns public.hr_attendance_policy_rules language sql stable security definer
set search_path='public','private','pg_temp' as $$
 select r from public.hr_attendance_policy_rules r
 where r.active and r.category='LATE_EARLY'
   and p_minutes>=coalesce(r.min_minutes,0)
   and (r.max_minutes is null or p_minutes<=r.max_minutes)
 order by r.min_minutes desc limit 1
$$;

create or replace function private.hr_apply_attendance_policy(p_batch uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare
 v_from date; v_to date; v_date date; v_daily record; v_rule public.hr_attendance_policy_rules%rowtype;
 v_created integer:=0; v_holidays integer:=0; v_alerts integer:=0; v_type text; v_minutes integer; v_existing uuid;
begin
 select min((punch_time at time zone 'Africa/Cairo')::date),max((punch_time at time zone 'Africa/Cairo')::date)
 into v_from,v_to from public.hr_attendance_file_punches where batch_id=p_batch;
 if v_from is null then return jsonb_build_object('holidays',0,'draft_policy_movements',0,'alerts',0); end if;

 -- Management rule: a calendar day with no punch by anybody is a school holiday.
 for v_date in select generate_series(v_from,v_to,'1 day'::interval)::date loop
  if not exists(select 1 from public.hr_attendance_file_punches p where (p.punch_time at time zone 'Africa/Cairo')::date=v_date) then
   insert into public.hr_holidays(holiday_date,holiday_name,source_type,source_batch_id,created_by)
   values(v_date,'إجازة تلقائية — لا توجد أي بصمة','NO_PUNCH_DAY',p_batch,auth.uid())
   on conflict(holiday_date) do nothing;
   if found then v_holidays:=v_holidays+1; end if;
  end if;
 end loop;

 -- Apply late, early-leave and missing-punch rules to calculated rows only.
 for v_daily in
  select d.* from public.hr_daily_attendance d
  where d.attendance_date between v_from and v_to
    and d.source_log_ids && array(select p.id from public.hr_attendance_file_punches p where p.batch_id=p_batch)
 loop
  if v_daily.missing_in or v_daily.missing_out then
   select * into v_rule from public.hr_attendance_policy_rules where rule_code='MISSING_PUNCH' and active;
   v_type:='MISSING_PUNCH'; v_minutes:=0;
   select id into v_existing from public.hr_employee_movements where source_type='BIOMETRIC' and source_record_id=v_daily.id::text and movement_type=v_type;
   if v_existing is null then
    insert into public.hr_employee_movements(employee_id,occurred_at,movement_type,description,source_type,source_record_id,status,created_by,updated_by,policy_rule_code,calculation_metadata)
    values(v_daily.employee_id,v_daily.attendance_date::timestamptz,v_type,'عدم وجود بصمة دخول أو خروج — مسودة للمراجعة','BIOMETRIC',v_daily.id::text,'DRAFT',auth.uid(),auth.uid(),v_rule.rule_code,
      jsonb_build_object('daily_percent',v_rule.deduction_percent_daily,'financial_effect',false));
    v_created:=v_created+1;
   end if;
  else
   foreach v_type in array array['LATE','EARLY_LEAVE'] loop
    v_minutes:=case when v_type='LATE' then v_daily.late_minutes else v_daily.early_leave_minutes end;
    select * into v_rule from private.attendance_rule_for_minutes(v_minutes);
    if v_rule.rule_code is not null then
     update public.hr_employee_movements set policy_rule_code=v_rule.rule_code,
       calculation_metadata=jsonb_build_object('minutes',v_minutes,'daily_percent',v_rule.deduction_percent_daily,'financial_effect',false),
       description=v_rule.definition_ar||' — مسودة للمراجعة'
     where source_type='BIOMETRIC' and source_record_id=v_daily.id::text and movement_type=v_type and status='DRAFT';
    end if;
   end loop;
  end if;
 end loop;
 perform private.hr_audit('hr_attendance_file_batches',p_batch,'APPLY_ATTENDANCE_POLICY',null,
  jsonb_build_object('from',v_from,'to',v_to,'auto_holidays',v_holidays,'draft_policy_movements',v_created,'financial_effect',false));
 return jsonb_build_object('from',v_from,'to',v_to,'auto_holidays',v_holidays,'draft_policy_movements',v_created,'alerts',v_alerts,'financial_effect',false);
end$$;

revoke all on function private.attendance_rule_for_minutes(integer),private.hr_apply_attendance_policy(uuid) from public,anon,authenticated;

create or replace function public.hr_finalize_attendance_file(p_batch uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare v_import jsonb; v_policy jsonb;
begin
 if auth.uid() is null or not public.has_hr_capability('BIOMETRIC_MANAGER') then
  raise exception 'HR biometric manager confirmation required';
 end if;
 v_import:=public.hr_confirm_attendance_file(p_batch);
 v_policy:=private.hr_apply_attendance_policy(p_batch);
 return v_import||jsonb_build_object('policy',v_policy);
end$$;

revoke all on function public.hr_finalize_attendance_file(uuid) from public,anon;
grant execute on function public.hr_finalize_attendance_file(uuid) to authenticated;

comment on table public.hr_attendance_policy_rules is 'Management-approved attendance consequences. Financial amounts remain DRAFT until HR review.';
comment on function private.hr_apply_attendance_policy(uuid) is 'Classifies confirmed file attendance and auto-registers days with zero punches across all staff as holidays.';
comment on function public.hr_finalize_attendance_file(uuid) is 'Atomically confirms a file, calculates attendance, applies management rules and registers zero-punch dates as holidays.';
