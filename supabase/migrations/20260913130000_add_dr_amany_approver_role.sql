-- Dedicated non-operational role for the exclusive payment/expense approver.
alter type public.finance_role add value if not exists 'DR_AMANY_APPROVER';
