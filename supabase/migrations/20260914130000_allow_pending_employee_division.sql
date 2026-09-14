-- Some source employees work across divisions. Keep classification pending instead of guessing a cost center.
alter table public.hr_employees alter column school_division drop not null;
