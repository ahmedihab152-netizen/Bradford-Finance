-- Read-only Phase 0 baseline. Safe to run against Production.
select
  (select count(*) from public.students) as students,
  (select count(*) from public.student_accounts) as student_accounts,
  (select count(*) from public.student_payments) as student_payments,
  (select count(*) from public.expenses) as expenses,
  (select count(*) from public.fixed_assets) as fixed_assets,
  (select count(*) from public.hr_employees) as hr_employees,
  (select count(*) from public.audit_events) as audit_events,
  (select count(*) from public.backup_manifests) as backup_manifests,
  (select count(*) from public.restore_test_runs) as restore_test_runs,
  (select count(*) from (
    select entry_id
    from public.journal_lines
    group by entry_id
    having sum(debit_piasters) <> sum(credit_piasters)
  ) unbalanced) as unbalanced_journals;

select n.nspname as schema_name, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r' and n.nspname = 'public'
order by c.relname;
