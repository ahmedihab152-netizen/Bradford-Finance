-- New student accounts must be complete zero-balance records without requiring
-- callers to know legacy cutover columns.
alter table public.student_accounts alter column opening_paid_piasters set default 0;
alter table public.student_accounts alter column opening_remaining_piasters set default 0;
alter table public.student_accounts alter column opening_due_piasters set default 0;
