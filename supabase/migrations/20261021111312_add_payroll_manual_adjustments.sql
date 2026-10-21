-- Allow HR to record one explicit manual deduction or increase per employee.
-- Attendance decisions remain itemized and are added to the manual deduction.

alter table public.hr_payroll_review_employees
  add column if not exists manual_deduction_piasters bigint not null default 0
    check (manual_deduction_piasters >= 0),
  add column if not exists adjustment_note text;

create or replace function public.hr_refresh_payroll_review_batch(p_batch uuid)
returns void language plpgsql security definer
set search_path='public','pg_temp' as $$
begin
  update public.hr_payroll_review_employees e set
    approved_deduction_piasters=x.approved_total + e.manual_deduction_piasters,
    updated_at=now()
  from (
    select employee_code,coalesce(sum(approved_deduction_piasters),0)::bigint approved_total
    from public.hr_payroll_review_items
    where batch_id=p_batch
    group by employee_code
  ) x
  where e.batch_id=p_batch and e.employee_code=x.employee_code;

  update public.hr_payroll_review_employees e
  set approved_deduction_piasters=e.manual_deduction_piasters,updated_at=now()
  where e.batch_id=p_batch
    and not exists (
      select 1 from public.hr_payroll_review_items i
      where i.batch_id=p_batch and i.employee_code=e.employee_code
    );

  update public.hr_payroll_review_batches b set
    employee_count=x.employee_count,
    item_count=x.item_count,
    unresolved_count=x.unresolved_count,
    suggested_deduction_piasters=x.suggested_total,
    approved_deduction_piasters=e.approved_total,
    gross_salary_total_piasters=e.gross_total,
    net_salary_total_piasters=e.net_total,
    increase_total_piasters=e.increase_total,
    final_net_payable_total_piasters=e.final_total,
    updated_at=now()
  from (
    select count(distinct employee_code)::int employee_count,
           count(*)::int item_count,
           count(*) filter(where decision='NEEDS_REVIEW')::int unresolved_count,
           coalesce(sum(suggested_deduction_piasters),0)::bigint suggested_total
    from public.hr_payroll_review_items where batch_id=p_batch
  ) x,
  (
    select coalesce(sum(gross_salary_piasters),0)::bigint gross_total,
           coalesce(sum(net_salary_piasters),0)::bigint net_total,
           coalesce(sum(approved_deduction_piasters),0)::bigint approved_total,
           coalesce(sum(increase_piasters),0)::bigint increase_total,
           coalesce(sum(final_net_payable_piasters),0)::bigint final_total
    from public.hr_payroll_review_employees where batch_id=p_batch
  ) e
  where b.id=p_batch;
end$$;

create or replace function public.hr_set_payroll_adjustment(
  p_batch uuid,
  p_employee_code text,
  p_increase_piasters bigint,
  p_manual_deduction_piasters bigint,
  p_note text default null
) returns void language plpgsql security definer
set search_path='public','pg_temp' as $$
declare
  actor uuid := (select auth.uid());
  role_name text;
  old_row jsonb;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select role::text into role_name from public.user_profiles where user_id=actor and active;
  if role_name not in ('OWNER','CEO','HR_MANAGER') then
    raise exception 'HR Manager permission required';
  end if;
  if coalesce(p_increase_piasters,-1) < 0 or coalesce(p_manual_deduction_piasters,-1) < 0 then
    raise exception 'Adjustment amounts cannot be negative';
  end if;
  if not exists (
    select 1 from public.hr_payroll_review_batches
    where id=p_batch and status='PENDING_HR'
  ) then raise exception 'Batch is not available for HR changes'; end if;

  select to_jsonb(e) into old_row
  from public.hr_payroll_review_employees e
  where e.batch_id=p_batch and e.employee_code=p_employee_code
  for update;
  if old_row is null then raise exception 'Employee is not in this payroll batch'; end if;

  update public.hr_payroll_review_employees
  set increase_piasters=p_increase_piasters,
      manual_deduction_piasters=p_manual_deduction_piasters,
      increase_note=case when p_increase_piasters > 0 then nullif(btrim(p_note),'') else null end,
      adjustment_note=nullif(btrim(p_note),''),
      updated_at=now(),updated_by=actor
  where batch_id=p_batch and employee_code=p_employee_code;

  perform public.hr_refresh_payroll_review_batch(p_batch);
  insert into public.hr_audit_events(table_name,record_id,action,old_data,new_data,changed_by)
  values(
    'hr_payroll_review_employees',p_batch::text||':'||p_employee_code,'SET_MANUAL_ADJUSTMENT',old_row,
    (select to_jsonb(e) from public.hr_payroll_review_employees e
     where e.batch_id=p_batch and e.employee_code=p_employee_code),actor
  );
end$$;

revoke all on function public.hr_set_payroll_adjustment(uuid,text,bigint,bigint,text) from public,anon;
grant execute on function public.hr_set_payroll_adjustment(uuid,text,bigint,bigint,text) to authenticated;

do $$declare r record; begin
  for r in select id from public.hr_payroll_review_batches loop
    perform public.hr_refresh_payroll_review_batch(r.id);
  end loop;
end$$;
