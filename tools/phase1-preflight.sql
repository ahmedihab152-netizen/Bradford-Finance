-- Read-only Phase 1 preflight. Run in Production before creating the backup,
-- and again in the isolated restored environment. This script performs no writes.

with required_tables(table_name) as (
  values
    ('students'),
    ('student_accounts'),
    ('student_charges'),
    ('student_payments'),
    ('user_profiles'),
    ('audit_events')
), table_check as (
  select r.table_name, (t.table_name is not null) as present
  from required_tables r
  left join information_schema.tables t
    on t.table_schema = 'public' and t.table_name = r.table_name
)
select 'required_table' as check_type, table_name as object_name,
       case when present then 'PASS' else 'FAIL' end as result
from table_check
order by table_name;

with required_columns(table_name, column_name) as (
  values
    ('students','id'), ('students','student_code'), ('students','student_name'), ('students','grade'), ('students','status'),
    ('student_accounts','id'), ('student_accounts','student_id'), ('student_accounts','academic_year'),
    ('student_payments','account_id'), ('student_payments','status'), ('student_payments','amount_piasters'),
    ('student_charges','account_id')
), column_check as (
  select r.table_name, r.column_name, (c.column_name is not null) as present
  from required_columns r
  left join information_schema.columns c
    on c.table_schema = 'public' and c.table_name = r.table_name and c.column_name = r.column_name
)
select 'required_column' as check_type, table_name || '.' || column_name as object_name,
       case when present then 'PASS' else 'FAIL' end as result
from column_check
order by table_name, column_name;

select 'duplicate_student_code' as check_type, coalesce(student_code, '<NULL>') as object_name,
       count(*)::text as result
from public.students
group by student_code
having count(*) > 1
order by count(*) desc, student_code;

select 'duplicate_account_year' as check_type, student_id::text || '/' || academic_year as object_name,
       count(*)::text as result
from public.student_accounts
group by student_id, academic_year
having count(*) > 1
order by count(*) desc, student_id;

select 'orphan_student_account' as check_type, a.id::text as object_name, 'FAIL' as result
from public.student_accounts a
left join public.students s on s.id = a.student_id
where s.id is null
order by a.id;

select 'rls_enabled' as check_type, c.relname as object_name,
       case when c.relrowsecurity then 'PASS' else 'FAIL' end as result
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('students','student_accounts','student_charges','student_payments','user_profiles','audit_events')
order by c.relname;
