-- Keep payroll disbursement on the FINANCE_MANAGER role while authority binding
-- still restricts the action to the designated Mahmoud Auth identity.

create or replace function public.can_view_hr_payroll() returns boolean
language sql stable security invoker set search_path = 'public','pg_temp'
as $$
  select public.current_finance_role() in
    ('OWNER','HR_MANAGER','HR_OFFICER','DR_AMANY_APPROVER','FINANCE_MANAGER')
$$;
revoke all on function public.can_view_hr_payroll() from public, anon;
grant execute on function public.can_view_hr_payroll() to authenticated;

drop policy if exists payroll_runs_read on public.payroll_runs;
create policy payroll_runs_read on public.payroll_runs for select to authenticated
using (
  public.can_view_hr_payroll()
  and (public.current_finance_role() <> 'FINANCE_MANAGER'
       or status in ('AMANY_APPROVED','READY_FOR_PAYMENT','PAID'))
);

drop policy if exists payroll_lines_read on public.payroll_lines;
create policy payroll_lines_read on public.payroll_lines for select to authenticated
using (exists (
  select 1 from public.payroll_runs r
  where r.id = payroll_run_id
    and public.can_view_hr_payroll()
    and (public.current_finance_role() <> 'FINANCE_MANAGER'
         or r.status in ('AMANY_APPROVED','READY_FOR_PAYMENT','PAID'))
));

drop policy if exists payroll_payments_read on public.payroll_payments;
create policy payroll_payments_read on public.payroll_payments for select to authenticated
using (public.current_finance_role() in ('OWNER','HR_MANAGER','DR_AMANY_APPROVER','FINANCE_MANAGER'));

drop policy if exists hr_authorities_read on public.hr_approval_authorities;
create policy hr_authorities_read on public.hr_approval_authorities for select to authenticated
using (public.current_finance_role() in
  ('OWNER','HR_MANAGER','HR_OFFICER','DR_AMANY_APPROVER','FINANCE_MANAGER'));

create or replace function public.hr_record_payroll_payment(
  p_run uuid,p_date date,p_method text,p_reference text,p_document_url text
) returns uuid language plpgsql security definer
set search_path='public','private','pg_temp' as $$
declare r public.payroll_runs%rowtype; pid uuid; jid uuid;
begin
  if public.current_finance_role() <> 'FINANCE_MANAGER'
     or not public.is_hr_authority('PAYMENT') then
    raise exception 'Only the designated payroll disbursement authority can record payment';
  end if;
  select * into r from public.payroll_runs where id=p_run for update;
  if not found or r.status not in ('AMANY_APPROVED','READY_FOR_PAYMENT') then
    raise exception 'Payroll is not approved for payment';
  end if;
  if p_method not in ('CASH','BANK')
     or nullif(btrim(p_reference),'') is null
     or nullif(btrim(p_document_url),'') is null then
    raise exception 'Payment method, reference and document are required';
  end if;
  jid := private.hr_post_journal(p_run,'PAYMENT',p_method);
  insert into public.payroll_payments(
    payroll_run_id,payment_date,payment_method,payment_reference,
    document_url,amount_piasters,journal_entry_id,created_by
  ) values (
    p_run,p_date,p_method,btrim(p_reference),btrim(p_document_url),
    r.net_pay_piasters,jid,auth.uid()
  ) returning id into pid;
  perform set_config('bradford.hr_workflow','1',true);
  update public.payroll_runs
  set status='PAID',locked_at=now(),updated_at=now(),updated_by=auth.uid()
  where id=p_run;
  perform private.hr_audit('payroll_payments',pid,'PAY',null,
    jsonb_build_object('run_id',p_run,'amount',r.net_pay_piasters,
                       'method',p_method,'reference',p_reference));
  return pid;
end $$;

revoke all on function public.hr_record_payroll_payment(uuid,date,text,text,text)
  from public, anon;
grant execute on function public.hr_record_payroll_payment(uuid,date,text,text,text)
  to authenticated;
