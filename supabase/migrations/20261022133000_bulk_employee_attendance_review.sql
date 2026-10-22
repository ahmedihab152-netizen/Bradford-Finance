create or replace function public.hr_save_employee_attendance_review(
  p_batch uuid,
  p_employee_code text,
  p_decisions jsonb
) returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  actor uuid := auth.uid();
  role_name text;
  expected_count integer;
  supplied_count integer;
  distinct_count integer;
  invalid_count integer;
  old_items jsonb;
  new_items jsonb;
  employee_row public.hr_payroll_review_employees%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select role::text into role_name from public.user_profiles where user_id=actor and active;
  if role_name not in ('OWNER','CEO','HR_MANAGER') then raise exception 'HR Manager permission required'; end if;
  if jsonb_typeof(p_decisions) <> 'array' then raise exception 'Decisions must be an array'; end if;

  perform 1 from public.hr_payroll_review_batches where id=p_batch and status='PENDING_HR' for update;
  if not found then raise exception 'Batch is not available for HR review'; end if;
  select * into employee_row from public.hr_payroll_review_employees where batch_id=p_batch and employee_code=p_employee_code for update;
  if not found then raise exception 'Employee is not part of this payroll batch'; end if;

  select count(*) into expected_count from public.hr_payroll_review_items where batch_id=p_batch and employee_code=p_employee_code;
  supplied_count := jsonb_array_length(p_decisions);
  select count(distinct d.item_id) into distinct_count
    from jsonb_to_recordset(p_decisions) as d(item_id uuid, action text, reason text);
  if supplied_count <> expected_count or distinct_count <> expected_count then
    raise exception 'Every attendance row must be reviewed exactly once';
  end if;

  select count(*) into invalid_count
  from jsonb_to_recordset(p_decisions) as d(item_id uuid, action text, reason text)
  left join public.hr_payroll_review_items i on i.id=d.item_id and i.batch_id=p_batch and i.employee_code=p_employee_code
  where i.id is null
     or upper(coalesce(d.action,'')) not in ('APPLY','CANCEL')
     or (upper(d.action)='CANCEL' and length(btrim(coalesce(d.reason,'')))<3);
  if invalid_count>0 then raise exception 'Invalid decision or missing cancellation reason'; end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.event_date,i.id),'[]'::jsonb) into old_items
  from public.hr_payroll_review_items i where i.batch_id=p_batch and i.employee_code=p_employee_code;

  update public.hr_payroll_review_items i set
    decision=case when upper(d.action)='APPLY' then 'APPLY' else 'EXEMPT' end,
    reviewer_note=case when upper(d.action)='APPLY' then 'تم احتساب الخصم' else btrim(d.reason) end,
    admin_reason=case when upper(d.action)='APPLY' then 'تم احتساب الخصم' else btrim(d.reason) end,
    financial_treatment=case when upper(d.action)='APPLY' then 'PROPOSED' else 'NO_DEDUCTION' end,
    reviewed_at=now(),
    reviewed_by=actor
  from jsonb_to_recordset(p_decisions) as d(item_id uuid, action text, reason text)
  where i.id=d.item_id and i.batch_id=p_batch and i.employee_code=p_employee_code;

  update public.hr_payroll_review_employees set
    review_status=case when identity_status='CONFLICT' or cardinality(data_issues)>0 and data_issues && array['MISSING_EMPLOYEE_CODE','EG001_NAME_CONFLICT_AMANY_UYAR','NO_CONFIRMED_EMPLOYEE_LINK'] then 'BLOCKED' else 'REVIEWED' end,
    reviewed_at=now(),reviewed_by=actor
  where batch_id=p_batch and employee_code=p_employee_code;
  perform public.hr_refresh_payroll_review_batch(p_batch);

  select coalesce(jsonb_agg(to_jsonb(i) order by i.event_date,i.id),'[]'::jsonb) into new_items
  from public.hr_payroll_review_items i where i.batch_id=p_batch and i.employee_code=p_employee_code;
  insert into public.hr_audit_events(table_name,record_id,action,old_data,new_data,changed_by)
  values('hr_payroll_review_employees',p_batch::text||':'||p_employee_code,'BULK_ATTENDANCE_REVIEW',old_items,new_items,actor);

  return jsonb_build_object(
    'employee_code',p_employee_code,
    'reviewed_rows',expected_count,
    'approved_deduction_piasters',(select approved_deduction_piasters from public.hr_payroll_review_employees where batch_id=p_batch and employee_code=p_employee_code),
    'final_net_payable_piasters',(select final_net_payable_piasters from public.hr_payroll_review_employees where batch_id=p_batch and employee_code=p_employee_code)
  );
end$$;

revoke all on function public.hr_save_employee_attendance_review(uuid,text,jsonb) from public,anon;
grant execute on function public.hr_save_employee_attendance_review(uuid,text,jsonb) to authenticated;
