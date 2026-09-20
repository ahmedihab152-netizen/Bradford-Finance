begin;

create or replace view public.v_payment_expense_approval_queue
with (security_invoker=true) as
select 'PAYMENT'::text record_type,p.id,p.transaction_date,p.amount_piasters,
 coalesce(s.student_name,'Student payment') description,s.student_code,s.grade,
 p.receipt_number reference_number,p.payment_method::text payment_method,p.status::text status,
 p.created_at,p.created_by,cp.full_name created_by_name,p.approved_at,p.approved_by,
 ap.full_name approved_by_name,p.review_note,p.cost_center_id,
 s.student_name,coalesce(s.program,nullif(upper(btrim(p.division_code)),''),nullif(upper(btrim(sa.division_code)),'')) program,
 s.grade_sort_order,sa.academic_year,coalesce(nullif(p.category_label,''),nullif(p.payment_category,''),'PAYMENT') operation_type
from public.student_payments p
left join public.student_accounts sa on sa.id=p.account_id
left join public.students s on s.id=sa.student_id
left join public.user_profiles cp on cp.user_id=p.created_by
left join public.user_profiles ap on ap.user_id=p.approved_by
where p.status::text in('DRAFT','SUBMITTED','POSTED')
union all
select 'EXPENSE'::text,e.id,e.transaction_date,e.net_paid_piasters,
 coalesce(nullif(e.description,''),nullif(e.category,''),'Expense'),null::text,null::text,
 coalesce(e.invoice_number,e.expense_number),e.payment_method::text,e.status::text,
 e.created_at,e.created_by,cp.full_name,e.approved_at,e.approved_by,ap.full_name,e.review_note,e.cost_center_id,
 null::text,null::text,null::integer,null::text,coalesce(nullif(e.category,''),'EXPENSE')
from public.expenses e
left join public.user_profiles cp on cp.user_id=e.created_by
left join public.user_profiles ap on ap.user_id=e.approved_by
where e.source_external_id is null and e.status::text in('DRAFT','SUBMITTED','POSTED');

revoke all on public.v_payment_expense_approval_queue from public,anon;
grant select on public.v_payment_expense_approval_queue to authenticated;

create or replace function public.review_financial_records_batch(
 p_records jsonb,p_action text,p_reason text default null,p_grade text default null,p_program text default null
) returns jsonb language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare x jsonb;v_type text;v_table text;v_id uuid;v_status text;v_grade text;v_program text;v_amount bigint;
 v_action text:=upper(btrim(coalesce(p_action,'')));v_count integer:=0;v_total bigint:=0;v_ids jsonb:='[]'::jsonb;
begin
 if auth.uid() is null or not public.is_dr_amany_payment_expense_approver() then
  raise exception 'Only Dr. Amany Hussein can review payments and expenses';
 end if;
 if v_action not in('APPROVE','REJECT') then raise exception 'Action must be APPROVE or REJECT';end if;
 if v_action='REJECT' and length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Rejection reason is required';end if;
 if jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)=0 or jsonb_array_length(p_records)>200 then
  raise exception 'Select between 1 and 200 records';
 end if;
 if (select count(*) from jsonb_array_elements(p_records))<>(select count(distinct (value->>'record_type')||':'||(value->>'id')) from jsonb_array_elements(p_records)) then
  raise exception 'Duplicate records are not allowed';
 end if;
 for x in select value from jsonb_array_elements(p_records) loop
  v_type:=upper(btrim(x->>'record_type'));v_id:=(x->>'id')::uuid;
  if v_type='PAYMENT' then
   v_table:='student_payments';
   select p.status::text,s.grade,coalesce(s.program,nullif(upper(btrim(p.division_code)),''),nullif(upper(btrim(sa.division_code)),''))
    into v_status,v_grade,v_program from public.student_payments p
    left join public.student_accounts sa on sa.id=p.account_id left join public.students s on s.id=sa.student_id
    where p.id=v_id for update of p;
  elsif v_type='EXPENSE' then
   v_table:='expenses';select e.status::text,null::text,null::text into v_status,v_grade,v_program from public.expenses e where e.id=v_id for update;
  else raise exception 'Unsupported record type';end if;
  if v_status is null then raise exception 'Record % was not found',v_id;end if;
  if v_action='APPROVE' and v_status not in('DRAFT','SUBMITTED') then raise exception 'Record % is no longer pending',v_id;end if;
  if v_action='REJECT' and v_status<>'SUBMITTED' then raise exception 'Only SUBMITTED records can be rejected: %',v_id;end if;
  if coalesce(p_grade,'')<>'' and coalesce(v_grade,'')<>p_grade then raise exception 'Mixed Grade selection is not allowed';end if;
  if coalesce(p_program,'')<>'' and coalesce(v_program,'')<>p_program then raise exception 'Mixed Program selection is not allowed';end if;
  if v_action='APPROVE' then perform private.approve_financial_record(v_table,v_id,'Batch approved by Dr. Amany Hussein');
  else perform private.reject_financial_record(v_table,v_id,btrim(p_reason));end if;
  select amount_piasters into strict v_amount from public.v_payment_expense_approval_queue where record_type=v_type and id=v_id;
  v_total:=v_total+coalesce(v_amount,0);v_count:=v_count+1;v_ids:=v_ids||to_jsonb(v_id::text);
 end loop;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata)
 values('financial_approval_batch',gen_random_uuid()::text,'BATCH_'||v_action,
  jsonb_build_object('count',v_count,'total_piasters',v_total,'record_ids',v_ids),auth.uid(),
  jsonb_build_object('grade',p_grade,'program',p_program,'reason',p_reason,'approved_role','DR_AMANY_APPROVER','occurred_at',now()));
 return jsonb_build_object('count',v_count,'total_piasters',v_total,'record_ids',v_ids);
end$$;

revoke all on function public.review_financial_records_batch(jsonb,text,text,text,text) from public,anon;
grant execute on function public.review_financial_records_batch(jsonb,text,text,text,text) to authenticated;

comment on function public.review_financial_records_batch(jsonb,text,text,text,text) is
'Atomic Dr Amany batch review. Locks every record; any duplicate, stale status, mixed group, or failed posting rolls back the whole call.';

commit;
