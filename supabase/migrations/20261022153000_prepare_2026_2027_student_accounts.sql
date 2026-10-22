begin;

alter table public.student_accounts
  drop constraint if exists student_accounts_student_id_academic_year_key;

create unique index if not exists student_accounts_current_student_year_uidx
  on public.student_accounts(student_id, academic_year)
  where source_meta->>'superseded' is distinct from 'true';

insert into public.student_accounts (
  student_id,
  academic_year,
  division_code,
  cost_center_id,
  organization_id,
  tuition_piasters,
  discount_piasters,
  application_fee_piasters,
  books_piasters,
  activity_piasters,
  transport_piasters,
  prior_year_balance_piasters,
  original_tuition_piasters,
  net_tuition_piasters,
  other_piasters,
  total_due_piasters,
  legacy_paid_piasters,
  legacy_remaining_piasters,
  opening_paid_piasters,
  opening_remaining_piasters,
  opening_due_piasters,
  discount_percent,
  notes,
  source_external_id,
  source_meta
)
select
  old.student_id,
  '2026-2027',
  old.division_code,
  old.cost_center_id,
  old.organization_id,
  0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  'حساب تشغيل جديد 2026-2027 — بدون ترحيل أرصدة أو تحصيلات سابقة',
  'ROLLOVER-2026-2027:' || old.student_id::text,
  jsonb_build_object(
    'rollover_from', '2025-2026',
    'prepared_at', '2026-10-22',
    'financial_opening', 'ZERO',
    'superseded', false
  )
from public.student_accounts old
join public.students s on s.id = old.student_id
where old.academic_year = '2025-2026'
  and old.source_meta->>'superseded' is distinct from 'true'
  and s.status = 'ACTIVE'
  and coalesce(s.student_code, '') not like 'BUS26-%'
  and not exists (
    select 1
    from public.student_accounts current_account
    where current_account.student_id = old.student_id
      and current_account.academic_year = '2026-2027'
      and current_account.source_meta->>'superseded' is distinct from 'true'
  );

commit;
