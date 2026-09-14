drop trigger if exists payroll_include_hr_movements on public.payroll_runs;
drop function if exists private.hr_include_before_submit();

create or replace function public.hr_payroll_action(p_run uuid,p_action text,p_reason text default null)
returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.payroll_runs%rowtype;target text;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 select * into r from public.payroll_runs where id=p_run for update;
 if not found then raise exception 'Payroll run not found';end if;
 if p_action='SUBMIT' and r.status in ('DRAFT','RETURNED_FOR_CORRECTION') and public.current_finance_role() in ('HR_OFFICER','HR_MANAGER') then target:='SUBMITTED_TO_HR_MANAGER';
 elsif p_action='HR_APPROVE' and r.status='SUBMITTED_TO_HR_MANAGER' and public.current_finance_role()='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') then target:='HR_MANAGER_APPROVED';
 elsif p_action='RETURN' and r.status in ('SUBMITTED_TO_HR_MANAGER','HR_MANAGER_APPROVED') and public.current_finance_role()='HR_MANAGER' and public.is_hr_authority('HR_MANAGER') then if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Reason required';end if;target:='RETURNED_FOR_CORRECTION';
 elsif p_action='AMANY_APPROVE' and r.status='HR_MANAGER_APPROVED' and public.current_finance_role()='DR_AMANY_APPROVER' and public.is_hr_authority('AMANY_FINAL') then target:='AMANY_APPROVED';
 elsif p_action='REJECT' and r.status='HR_MANAGER_APPROVED' and public.current_finance_role()='DR_AMANY_APPROVER' and public.is_hr_authority('AMANY_FINAL') then if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Reason required';end if;target:='REJECTED';
 else raise exception 'Not authorized or invalid payroll transition';end if;
 if target='SUBMITTED_TO_HR_MANAGER' then perform private.hr_include_movements(p_run);select * into r from public.payroll_runs where id=p_run;end if;
 perform set_config('bradford.hr_workflow','1',true);
 update public.payroll_runs set status=target,submitted_at=case when target='SUBMITTED_TO_HR_MANAGER' then now() else submitted_at end,submitted_by=case when target='SUBMITTED_TO_HR_MANAGER' then auth.uid() else submitted_by end,hr_approved_at=case when target='HR_MANAGER_APPROVED' then now() else hr_approved_at end,hr_approved_by=case when target='HR_MANAGER_APPROVED' then auth.uid() else hr_approved_by end,amany_approved_at=case when target='AMANY_APPROVED' then now() else amany_approved_at end,amany_approved_by=case when target='AMANY_APPROVED' then auth.uid() else amany_approved_by end,locked_at=case when target='AMANY_APPROVED' then now() else locked_at end,rejection_reason=p_reason,updated_at=now(),updated_by=auth.uid() where id=p_run;
 if target='AMANY_APPROVED' then update public.payroll_runs set journal_entry_id=private.hr_post_journal(p_run,'ACCRUAL'),status='READY_FOR_PAYMENT' where id=p_run;end if;
 perform private.hr_audit('payroll_runs',p_run,p_action,to_jsonb(r),jsonb_build_object('status',target,'reason',p_reason));
end$$;
revoke all on function public.hr_payroll_action(uuid,text,text) from public,anon;
grant execute on function public.hr_payroll_action(uuid,text,text) to authenticated;
