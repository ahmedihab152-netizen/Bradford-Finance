-- Management decision: attendance deductions use daily salary = Gross / 30.
-- Gross is the effective compensation basic salary plus fixed allowance.
-- Calculated amounts remain proposed DRAFT values until HR approval.

create table if not exists public.hr_attendance_pay_basis (
  singleton boolean primary key default true check (singleton),
  salary_basis text not null default 'GROSS' check (salary_basis='GROSS'),
  daily_divisor numeric(6,2) not null default 30 check (daily_divisor>0),
  gross_components text[] not null default array['basic_salary_piasters','fixed_allowance_piasters'],
  active boolean not null default true,
  decided_at timestamptz not null default now(),
  decided_by uuid references auth.users(id)
);
insert into public.hr_attendance_pay_basis(singleton,salary_basis,daily_divisor,gross_components)
values(true,'GROSS',30,array['basic_salary_piasters','fixed_allowance_piasters'])
on conflict(singleton) do update set salary_basis='GROSS',daily_divisor=30,
 gross_components=excluded.gross_components,active=true,decided_at=now();

alter table public.hr_attendance_pay_basis enable row level security;
revoke all on public.hr_attendance_pay_basis from public,anon,authenticated;
grant select on public.hr_attendance_pay_basis to authenticated;
create policy attendance_pay_basis_read on public.hr_attendance_pay_basis for select to authenticated
using (public.current_finance_role() in ('OWNER','HR_MANAGER','HR_OFFICER','DR_AMANY_APPROVER'));

create or replace function private.apply_attendance_movement_amount()
returns trigger language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare
 v_code text; v_gross bigint; v_divisor numeric; v_daily numeric;
 v_percent numeric; v_days numeric; v_amount bigint;
begin
 if new.source_type<>'BIOMETRIC' or new.status<>'DRAFT' or new.policy_rule_code is null then return new; end if;
 select employee_code into v_code from public.hr_employees where id=new.employee_id;
 select (c.basic_salary_piasters+c.fixed_allowance_piasters)
 into v_gross from public.employee_compensation c
 where upper(c.employee_code)=upper(v_code)
   and c.status in ('ACTIVE','DRAFT')
   and c.effective_from<=new.occurred_at::date
   and (c.effective_to is null or c.effective_to>=new.occurred_at::date)
 order by case c.status when 'ACTIVE' then 0 else 1 end,c.effective_from desc,c.updated_at desc limit 1;
 select daily_divisor into v_divisor from public.hr_attendance_pay_basis where singleton and active;
 select deduction_percent_daily,deduction_days into v_percent,v_days
 from public.hr_attendance_policy_rules where rule_code=new.policy_rule_code and active;
 if v_gross is null or v_divisor is null then
  new.proposed_amount_piasters:=0;
  new.calculation_metadata:=coalesce(new.calculation_metadata,'{}')||jsonb_build_object(
   'salary_basis','GROSS','daily_divisor',30,'salary_status','NEEDS_COMPENSATION_REVIEW','financial_effect',false);
  return new;
 end if;
 v_daily:=v_gross/v_divisor;
 v_amount:=round(v_daily*(coalesce(v_days,0)+(coalesce(v_percent,0)/100.0)))::bigint;
 new.proposed_amount_piasters:=greatest(v_amount,0);
 new.calculation_metadata:=coalesce(new.calculation_metadata,'{}')||jsonb_build_object(
  'salary_basis','GROSS','gross_piasters',v_gross,'daily_divisor',v_divisor,
  'daily_salary_piasters',round(v_daily)::bigint,'deduction_percent',coalesce(v_percent,0),
  'deduction_days',coalesce(v_days,0),'proposed_amount_piasters',greatest(v_amount,0),
  'financial_effect',false,'requires_hr_approval',true);
 return new;
end$$;

drop trigger if exists hr_attendance_movement_amount on public.hr_employee_movements;
create trigger hr_attendance_movement_amount before insert or update of policy_rule_code,calculation_metadata
on public.hr_employee_movements for each row execute function private.apply_attendance_movement_amount();

revoke all on function private.apply_attendance_movement_amount() from public,anon,authenticated;
comment on table public.hr_attendance_pay_basis is 'Approved attendance deduction basis: Gross salary divided by 30.';
