create or replace function public.can_view_hr_payroll() returns boolean
language sql stable security invoker set search_path='public','pg_temp' as $$
  select public.current_finance_role() in
    ('OWNER','HR_MANAGER','HR_OFFICER','DR_AMANY_APPROVER','FINANCE_MANAGER')
$$;
revoke all on function public.can_view_hr_payroll() from public,anon;
grant execute on function public.can_view_hr_payroll() to authenticated;
