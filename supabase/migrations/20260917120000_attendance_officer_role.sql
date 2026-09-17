-- Dedicated attendance-only role. Kept separate so the following migration can
-- safely use the enum value after PostgreSQL commits this enum change.
alter type public.finance_role add value if not exists 'ATTENDANCE_OFFICER';
