begin;
alter view public.v_journal_trial_balance set (security_invoker=true);
alter view public.v_profit_and_loss_live set (security_invoker=true);
alter view public.v_cash_movement_live set (security_invoker=true);
alter view public.v_balance_sheet_live set (security_invoker=true);
alter view public.v_cost_center_profit_loss set (security_invoker=true);
alter view public.v_production_health set (security_invoker=true);
commit;
