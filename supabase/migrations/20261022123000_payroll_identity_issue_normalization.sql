-- Normalize visible salary-source issues after the first workflow migration.
update public.hr_payroll_review_employees set
 data_issues=case when gross_salary_piasters=0 and not(data_issues @> array['MISSING_GROSS_SOURCE']) then array_append(data_issues,'MISSING_GROSS_SOURCE') else data_issues end,
 identity_status=case when identity_status='CONFLICT' then 'CONFLICT' when employee_id is not null then 'CONFIRMED' else 'UNCONFIRMED' end,
 review_status=case when identity_status='CONFLICT' or employee_id is null then 'BLOCKED' when review_status='BLOCKED' then 'UNREVIEWED' else review_status end;

update public.hr_payroll_review_batches b set source_attendance_batch_id=x.id
from lateral (select id from public.hr_attendance_file_batches order by created_at desc limit 1) x
where b.batch_key='october_2026_attendance_review_v1';

-- Explicit identity-resolution queue. Suggestions are never financial links.
create table if not exists public.hr_identity_resolution_issues(
 id uuid primary key default gen_random_uuid(),
 source_batch_id uuid references public.hr_attendance_file_batches(id),
 source_identity text not null,
 source_name text,
 suggested_employee_code text,
 issue_type text not null check(issue_type in ('AMBIGUOUS_NAME','CODE_NAME_CONFLICT','DUPLICATE_DEVICE_LINK','UNLINKED_DEVICE_ID')),
 status text not null default 'OPEN' check(status in ('OPEN','CONFIRMED','REJECTED')),
 resolution_note text,
 resolved_employee_id uuid references public.hr_employees(id),
 resolved_at timestamptz,resolved_by uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(source_batch_id,source_identity,issue_type)
);
alter table public.hr_identity_resolution_issues enable row level security;
create policy hr_identity_issues_select on public.hr_identity_resolution_issues for select to authenticated using (public.current_finance_role() in ('OWNER','CEO','HR_MANAGER','HR_OFFICER','DR_AMANY_APPROVER'));

insert into public.hr_identity_resolution_issues(source_batch_id,source_identity,source_name,suggested_employee_code,issue_type)
select b.source_attendance_batch_id,'EG001','Uyar','EG001','CODE_NAME_CONFLICT'
from public.hr_payroll_review_batches b where b.batch_key='october_2026_attendance_review_v1'
on conflict do nothing;
insert into public.hr_identity_resolution_issues(source_batch_id,source_identity,source_name,suggested_employee_code,issue_type)
select b.source_attendance_batch_id,v.identity,v.person_name,'EG072','DUPLICATE_DEVICE_LINK'
from public.hr_payroll_review_batches b cross join (values('112','Mariam Ahmed Mostafa'),('189','Ahmed Mostafa Mohamed')) v(identity,person_name)
where b.batch_key='october_2026_attendance_review_v1' on conflict do nothing;

grant select on public.hr_identity_resolution_issues to authenticated;
