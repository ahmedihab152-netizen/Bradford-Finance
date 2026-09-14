-- RLS policies execute this helper as the authenticated caller.
-- It is SECURITY DEFINER, returns only a boolean decision, and performs no writes.
grant execute on function private.can_use_student_cashier(uuid) to authenticated;
