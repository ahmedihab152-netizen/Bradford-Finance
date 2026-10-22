-- Complete, auditable attendance/payroll review workflow.
-- October remains a draft: this migration never approves or pays it.

alter table public.hr_payroll_review_batches
  add column if not exists source_attendance_batch_id uuid references public.hr_attendance_file_batches(id),
  add column if not exists schedule_policy jsonb not null default '{"sun_wed":{"in":"07:35","out":"14:42"},"thu":{"in":"07:35","out":"15:30"},"weekend":[5,6],"holiday_dates":["2026-10-08"],"source":"SCHOOL_POLICY"}'::jsonb,
  add column if not exists payroll_run_id uuid references public.payroll_runs(id),
  add column if not exists is_test boolean not null default false;

alter table public.hr_payroll_review_employees
  add column if not exists employee_id uuid references public.hr_employees(id),
  add column if not exists loan_installment_piasters bigint not null default 0 check (loan_installment_piasters>=0),
  add column if not exists review_status text not null default 'UNREVIEWED'
    check (review_status in ('UNREVIEWED','IN_REVIEW','REVIEWED','BLOCKED')),
  add column if not exists identity_status text not null default 'UNCONFIRMED'
    check (identity_status in ('CONFIRMED','UNCONFIRMED','CONFLICT')),
  add column if not exists data_issues text[] not null default '{}',
  add column if not exists excluded_reason text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references auth.users(id);

alter table public.hr_payroll_review_items
  add column if not exists employee_id uuid references public.hr_employees(id),
  add column if not exists source_type text not null default 'IMPORTED_REVIEW',
  add column if not exists source_reference text,
  add column if not exists schedule_in time,
  add column if not exists schedule_out time,
  add column if not exists schedule_source text not null default 'SCHOOL_POLICY',
  add column if not exists admin_reason text,
  add column if not exists attachment_url text,
  add column if not exists financial_treatment text,
  add column if not exists permission_sequence integer,
  add column if not exists material boolean not null default true;

alter table public.hr_payroll_review_items drop column approved_deduction_piasters;
alter table public.hr_payroll_review_items add column approved_deduction_piasters bigint generated always as
 (case
   when decision='APPLY' then suggested_deduction_piasters
   when decision='INFORMED_ABSENCE' then daily_salary_piasters
   when decision='UNEXCUSED_ABSENCE' then daily_salary_piasters*2
   when decision='UNPAID_LEAVE' then daily_salary_piasters
   when decision='SICK_LEAVE' and financial_treatment='FULL_DAY' then daily_salary_piasters
   when decision='SICK_LEAVE' and financial_treatment='PROPOSED' then suggested_deduction_piasters
   else 0 end) stored;

alter table public.hr_payroll_review_employees drop column final_net_payable_piasters;
alter table public.hr_payroll_review_employees add column final_net_payable_piasters bigint generated always as
 (greatest(0,net_salary_piasters-approved_deduction_piasters+increase_piasters-loan_installment_piasters)) stored;

-- Remove the invalid holiday inference. Only the explicitly confirmed 8 October holiday remains.
delete from public.hr_holidays where source_type='NO_PUNCH_DAY';
insert into public.hr_holidays(holiday_date,holiday_name,source_type)
values(date '2026-10-08','إجازة مدرسية معتمدة','MANUAL')
on conflict (holiday_date) do update set holiday_name=excluded.holiday_name,source_type=excluded.source_type,source_batch_id=null;

-- Make missing source values and identity conflicts visible; never silently treat them as valid zeroes.
update public.hr_payroll_review_employees e set
 employee_id=h.id,
 identity_status=case
   when upper(e.employee_code)='EG001' and lower(e.employee_name) not like '%amany%' then 'CONFLICT'
   when h.id is not null and lower(regexp_replace(e.employee_name,'[^a-z0-9]','','g'))=lower(regexp_replace(h.full_name,'[^a-z0-9]','','g')) then 'CONFIRMED'
   when h.id is not null then 'UNCONFIRMED' else 'UNCONFIRMED' end,
 data_issues=array_remove(array[
   case when nullif(btrim(e.employee_code),'') is null then 'MISSING_EMPLOYEE_CODE' end,
   case when e.gross_salary_piasters=0 then 'MISSING_GROSS_SOURCE' end,
   case when upper(e.employee_code)='EG001' and lower(e.employee_name) not like '%amany%' then 'EG001_NAME_CONFLICT_AMANY_UYAR' end,
   case when h.id is null then 'NO_CONFIRMED_EMPLOYEE_LINK' end
 ],null),
 review_status=case when nullif(btrim(e.employee_code),'') is null or upper(e.employee_code)='EG001' then 'BLOCKED' else e.review_status end
from public.hr_employees h where upper(h.employee_code)=upper(e.employee_code);

update public.hr_payroll_review_employees e set
 data_issues=array_remove(array[
  'MISSING_EMPLOYEE_CODE',case when e.gross_salary_piasters=0 then 'MISSING_GROSS_SOURCE' end,'NO_CONFIRMED_EMPLOYEE_LINK'
 ],null),identity_status='UNCONFIRMED',review_status='BLOCKED'
where nullif(btrim(e.employee_code),'') is null;

-- Net is the sole daily deduction basis. Gross remains an independent source field.
update public.hr_payroll_review_items i set
 employee_id=e.employee_id,
 daily_salary_piasters=round(e.net_salary_piasters/30.0)::bigint,
 suggested_rate=case
  when i.event_type='No sign-in/out' then .20
  when i.event_type='Absence' then 1.00
  when coalesce(i.minutes,0) between 4 and 10 then .05
  when coalesce(i.minutes,0) between 11 and 20 then .10
  when coalesce(i.minutes,0) between 21 and 60 then .20
  when coalesce(i.minutes,0) between 61 and 90 then .30
  when coalesce(i.minutes,0) between 91 and 150 then .40
  when coalesce(i.minutes,0)>150 then .50 else 0 end,
 schedule_in=time '07:35',
 schedule_out=case when extract(isodow from i.event_date)=4 then time '15:30' else time '14:42' end,
 schedule_source='SCHOOL_POLICY_2026_10'
from public.hr_payroll_review_employees e
where e.batch_id=i.batch_id and e.employee_code=i.employee_code;

update public.hr_payroll_review_items set
 suggested_deduction_piasters=round(daily_salary_piasters*suggested_rate)::bigint;

create or replace function public.hr_refresh_payroll_review_batch(p_batch uuid)
returns void language plpgsql security definer set search_path='public','pg_temp' as $$
begin
 update public.hr_payroll_review_employees e set
  approved_deduction_piasters=coalesce((select sum(i.approved_deduction_piasters) from public.hr_payroll_review_items i where i.batch_id=e.batch_id and i.employee_code=e.employee_code),0)+e.manual_deduction_piasters,
  updated_at=now() where e.batch_id=p_batch;
 update public.hr_payroll_review_batches b set
  employee_count=(select count(*) from public.hr_payroll_review_employees where batch_id=p_batch),
  item_count=(select count(*) from public.hr_payroll_review_items where batch_id=p_batch),
  unresolved_count=(select count(*) from public.hr_payroll_review_items where batch_id=p_batch and decision='NEEDS_REVIEW'),
  suggested_deduction_piasters=(select coalesce(sum(suggested_deduction_piasters),0) from public.hr_payroll_review_items where batch_id=p_batch),
  approved_deduction_piasters=(select coalesce(sum(approved_deduction_piasters),0) from public.hr_payroll_review_employees where batch_id=p_batch),
  gross_salary_total_piasters=(select coalesce(sum(gross_salary_piasters),0) from public.hr_payroll_review_employees where batch_id=p_batch),
  net_salary_total_piasters=(select coalesce(sum(net_salary_piasters),0) from public.hr_payroll_review_employees where batch_id=p_batch),
  increase_total_piasters=(select coalesce(sum(increase_piasters),0) from public.hr_payroll_review_employees where batch_id=p_batch),
  final_net_payable_total_piasters=(select coalesce(sum(final_net_payable_piasters),0) from public.hr_payroll_review_employees where batch_id=p_batch),updated_at=now()
 where b.id=p_batch;
end$$;

create or replace function public.hr_review_payroll_item(p_item uuid,p_decision text,p_note text default null,p_attachment_url text default null,p_financial_treatment text default null)
returns void language plpgsql security definer set search_path='public','pg_temp' as $$
declare actor uuid:=(select auth.uid()); r public.hr_payroll_review_items%rowtype; role_name text; d text:=upper(coalesce(p_decision,'')); old_row jsonb;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 select role::text into role_name from public.user_profiles where user_id=actor and active;
 if role_name not in ('OWNER','CEO','HR_MANAGER') then raise exception 'HR Manager permission required'; end if;
 if d not in ('APPLY','INFORMED_ABSENCE','UNEXCUSED_ABSENCE','EXEMPT','PERMISSION','ON_DUTY','SICK_LEAVE','PAID_LEAVE','UNPAID_LEAVE','CORRECTED') then raise exception 'Invalid review decision'; end if;
 if length(btrim(coalesce(p_note,'')))<3 then raise exception 'Decision reason is required'; end if;
 select i.* into r from public.hr_payroll_review_items i join public.hr_payroll_review_batches b on b.id=i.batch_id where i.id=p_item and b.status='PENDING_HR' for update of i;
 if not found then raise exception 'Item is not available for HR review'; end if;
 old_row:=to_jsonb(r);
 update public.hr_payroll_review_items set decision=d,reviewer_note=p_note,admin_reason=p_note,attachment_url=nullif(btrim(p_attachment_url),''),financial_treatment=nullif(upper(coalesce(p_financial_treatment,'')),''),reviewed_at=now(),reviewed_by=actor where id=p_item;
 perform public.hr_refresh_payroll_review_batch(r.batch_id);
 insert into public.hr_audit_events(table_name,record_id,action,old_data,new_data,changed_by) values('hr_payroll_review_items',p_item::text,'HR_REVIEW',old_row,(select to_jsonb(i) from public.hr_payroll_review_items i where i.id=p_item),actor);
end$$;

create or replace function public.hr_save_employee_payroll_review(p_batch uuid,p_employee_code text)
returns void language plpgsql security definer set search_path='public','pg_temp' as $$
declare actor uuid:=(select auth.uid()); role_name text; blockers int;
begin
 select role::text into role_name from public.user_profiles where user_id=actor and active;
 if actor is null or role_name not in ('OWNER','CEO','HR_MANAGER') then raise exception 'HR Manager permission required'; end if;
 select count(*) into blockers from public.hr_payroll_review_items where batch_id=p_batch and employee_code=p_employee_code and decision='NEEDS_REVIEW';
 if blockers>0 then raise exception 'Resolve every material attendance case first'; end if;
 update public.hr_payroll_review_employees set review_status=case when identity_status='CONFLICT' or cardinality(data_issues)>0 and data_issues && array['MISSING_EMPLOYEE_CODE','EG001_NAME_CONFLICT_AMANY_UYAR','NO_CONFIRMED_EMPLOYEE_LINK'] then 'BLOCKED' else 'REVIEWED' end,reviewed_at=now(),reviewed_by=actor where batch_id=p_batch and employee_code=p_employee_code;
 perform public.hr_refresh_payroll_review_batch(p_batch);
end$$;

create or replace function public.hr_accept_remaining_and_send_to_amany(p_batch uuid,p_note text default null)
returns void language plpgsql security definer set search_path='public','pg_temp' as $$
declare actor uuid:=(select auth.uid()); role_name text; b public.hr_payroll_review_batches%rowtype; unresolved int; blocked int;
begin
 select role::text into role_name from public.user_profiles where user_id=actor and active;
 if actor is null or role_name not in ('OWNER','CEO','HR_MANAGER') then raise exception 'HR Manager permission required'; end if;
 select * into b from public.hr_payroll_review_batches where id=p_batch and status='PENDING_HR' for update;
 if not found then raise exception 'Batch is not available for HR approval'; end if;
 select count(*) into unresolved from public.hr_payroll_review_items where batch_id=p_batch and decision='NEEDS_REVIEW' and material;
 select count(*) into blocked from public.hr_payroll_review_employees where batch_id=p_batch and (review_status<>'REVIEWED' or identity_status<>'CONFIRMED');
 if unresolved>0 or blocked>0 then raise exception 'Cannot send: % unresolved cases and % unreviewed/identity-blocked employees',unresolved,blocked; end if;
 update public.hr_payroll_review_batches set status='PENDING_AMANY',hr_accepted_at=now(),hr_accepted_by=actor,hr_note=nullif(btrim(p_note),''),updated_at=now(),updated_by=actor where id=p_batch;
 insert into public.hr_audit_events(table_name,record_id,action,old_data,new_data,changed_by) values('hr_payroll_review_batches',p_batch::text,'HR_SEND_TO_AMANY',to_jsonb(b),(select to_jsonb(x) from public.hr_payroll_review_batches x where x.id=p_batch),actor);
end$$;

revoke all on function public.hr_review_payroll_item(uuid,text,text,text,text) from public,anon;
revoke all on function public.hr_save_employee_payroll_review(uuid,text) from public,anon;
grant execute on function public.hr_review_payroll_item(uuid,text,text,text,text),public.hr_save_employee_payroll_review(uuid,text) to authenticated;

do $$declare r record; begin for r in select id from public.hr_payroll_review_batches loop perform public.hr_refresh_payroll_review_batch(r.id); end loop; end$$;
