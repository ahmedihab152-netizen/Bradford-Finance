alter table public.hr_payroll_review_items drop constraint if exists hr_payroll_review_items_decision_check;
alter table public.hr_payroll_review_items add constraint hr_payroll_review_items_decision_check check(decision in(
 'NEEDS_REVIEW','APPLY','INFORMED_ABSENCE','UNEXCUSED_ABSENCE','EXEMPT','PERMISSION','ON_DUTY','SICK_LEAVE','PAID_LEAVE','UNPAID_LEAVE','CORRECTED'
));

-- Retire the legacy three-argument RPC so it cannot bypass the richer decision record.
revoke all on function public.hr_review_payroll_item(uuid,text,text) from public,anon,authenticated;
