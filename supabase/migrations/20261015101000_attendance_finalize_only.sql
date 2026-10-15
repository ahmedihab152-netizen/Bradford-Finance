-- Confirmation is exposed only through the atomic policy finalizer.
-- This prevents clients from bypassing the school attendance rules.
revoke execute on function public.hr_confirm_attendance_file(uuid) from authenticated;
