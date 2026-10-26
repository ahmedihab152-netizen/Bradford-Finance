begin;
-- A posted journal remains part of the ledger after its reversing entry posts.
-- Excluding the original while retaining the reversal creates a negative original.
-- Preserve columns and grants; explicitly retain caller RLS on replacement views.
set local search_path=public,pg_temp;
do $$
declare view_name text; definition text; revised text;
begin
 foreach view_name in array array['v_journal_trial_balance','v_profit_and_loss_live','v_cash_movement_live','v_balance_sheet_live','v_cost_center_profit_loss','v_production_health'] loop
  definition:=pg_get_viewdef(('public.'||view_name)::regclass,true);
  revised:=regexp_replace(definition,'\m(e|je)\.status = ''POSTED''::record_status','\1.status IN (''POSTED''::record_status, ''REVERSED''::record_status)','g');
  if revised=definition then raise exception 'Expected posted journal filter missing from %',view_name;end if;
  execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,revised);
 end loop;
end $$;
commit;
