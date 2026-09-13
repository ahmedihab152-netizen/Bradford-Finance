begin;

-- Link the existing Auth account. No Auth user is created and no credentials change.
update public.user_profiles
set role='DR_AMANY_APPROVER'::public.finance_role,
    full_name='د. أماني حسين', active=true, updated_at=now()
where user_id=(select id from auth.users where lower(email)=lower('amanyhussienelz@gmail.com'));

do $$
declare v_amany uuid;
begin
  select id into v_amany from auth.users where lower(email)=lower('amanyhussienelz@gmail.com');
  if v_amany is null then raise exception 'Existing Dr Amany Auth account was not found'; end if;
  if not exists(select 1 from public.user_profiles where user_id=v_amany and active) then
    raise exception 'Dr Amany user profile link failed';
  end if;
  update public.approval_authorities
     set approver_user_id=v_amany, approver_name='Dr. Amany Hussein', active=true,
         linked_at=now(), linked_by=(select user_id from public.user_profiles where role='OWNER' and active order by created_at limit 1),
         updated_at=now()
   where scope='PAYMENTS_EXPENSES';
  if not found then raise exception 'PAYMENTS_EXPENSES authority is missing'; end if;
end $$;

-- The designated approver can read only the two queues she approves. Existing RLS
-- continues to deny INSERT/UPDATE; state changes remain available only through RPC.
drop policy if exists dr_amany_payments_read on public.student_payments;
create policy dr_amany_payments_read on public.student_payments for select to authenticated
using (public.is_dr_amany_payment_expense_approver());
drop policy if exists dr_amany_expenses_read on public.expenses;
create policy dr_amany_expenses_read on public.expenses for select to authenticated
using (public.is_dr_amany_payment_expense_approver());

-- Rejecting a pending payment/expense is also exclusive to the designated account.
create or replace function private.reject_financial_record(p_table text,p_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare v_status text; v_special boolean;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_table not in ('expenses','student_payments','treasury_transactions') then raise exception 'Unsupported financial table'; end if;
 v_special:=p_table in ('expenses','student_payments');
 if v_special and not public.is_dr_amany_payment_expense_approver() then
   raise exception 'Only Dr. Amany Hussein can reject payments and expenses';
 elsif not v_special and not public.is_finance_admin() then
   raise exception 'Only Finance Admin can reject';
 end if;
 if p_reason is null or length(btrim(p_reason))<3 then raise exception 'Rejection reason is required'; end if;
 execute format('SELECT status::text FROM public.%I WHERE id=$1 FOR UPDATE',p_table) into v_status using p_id;
 if v_status<>'SUBMITTED' then raise exception 'Only SUBMITTED records can be rejected'; end if;
 perform set_config('bradford.workflow','1',true);
 execute format('UPDATE public.%I SET status=''DRAFT'',review_note=$2,submitted_at=NULL,submitted_by=NULL,updated_at=now(),updated_by=auth.uid() WHERE id=$1',p_table) using p_id,btrim(p_reason);
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata)
 values(p_table,p_id::text,'REJECT',jsonb_build_object('status','DRAFT'),auth.uid(),jsonb_build_object('reason',btrim(p_reason),'approval_authority',case when v_special then 'DR_AMANY_HUSSEIN' else 'FINANCE_ADMIN' end));
end $$;

revoke all on function private.reject_financial_record(text,uuid,text) from public,anon,authenticated;

commit;
