-- Correct the existing dashboard's historical + current-baseline definition.
-- This is a cash/baseline summary, not revenue recognition or net profit.
-- No source values or archived financial rows are rewritten.
begin;
create or replace view public.v_finance_all_time_summary with(security_invoker=true) as
with rev as (
 select
  (select coalesce(sum(total_piasters),0) from public.historical_revenue_entries where revenue_type<>'IG_STUDENT_ACCOUNT')
  +(select coalesce(sum(legacy_paid_piasters),0) from public.student_accounts
    where academic_year='2026-2027' and (to_jsonb(student_accounts)->'source_meta'->>'superseded') is distinct from 'true') as total_revenue_piasters
), exp as (
 select coalesce(sum(case when source_external_id is not null
   then coalesce(round(source_amount_egp*100)::bigint,net_paid_piasters,0)*coalesce(effect_sign,1)
   else coalesce(net_paid_piasters,0)*coalesce(effect_sign,1) end),0) as total_expense_piasters,
   count(*) as expense_rows
 from public.expenses where status in('POSTED','REVERSED')
)
select rev.total_revenue_piasters,exp.total_expense_piasters,
 rev.total_revenue_piasters-exp.total_expense_piasters as cash_surplus_piasters,
 (select count(*) from public.historical_revenue_entries where revenue_type<>'IG_STUDENT_ACCOUNT') as historical_revenue_rows,
 exp.expense_rows from rev cross join exp;

-- Imported history predates tenant IDs and belongs to the original MCIS tenant.
-- Fail closed for other tenants until the legacy data has explicit tenant IDs.
drop policy if exists historical_revenue_legacy_scope on public.historical_revenue_entries;
create policy historical_revenue_legacy_scope on public.historical_revenue_entries
 as restrictive for all to authenticated
 using(public.can_access_organization(public.default_organization_id()) and public.current_finance_role()::text in('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','TREASURY','AUDITOR','IG_ACCOUNTANT') and (public.current_finance_role()::text<>'IG_ACCOUNTANT' or upper(coalesce(division_code,''))='IG'))
 with check(public.can_access_organization(public.default_organization_id()) and public.current_finance_role()::text in('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','TREASURY'));
commit;
