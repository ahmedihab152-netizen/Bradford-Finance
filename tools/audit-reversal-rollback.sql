-- Staging only. Append the reversal migration immediately after BEGIN before running.
-- Uses an existing owner identity as JWT claims, without credentials or user mutation.
begin;
create temp table audit_reversal_result(test text,passed boolean,detail text);
create temp table audit_reversal_before(measure text primary key,value bigint);
insert into audit_reversal_before values
 ('cash',coalesce((select sum(cash_change_piasters) from public.v_cash_movement_live),0)),
 ('trial_cash',coalesce((select balance_piasters from public.v_journal_trial_balance where account_code='1100'),0)),
 ('profit_loss',coalesce((select sum(amount_piasters) from public.v_profit_and_loss_live),0)),
 ('balance_assets',coalesce((select sum(balance_piasters) from public.v_balance_sheet_live where account_type='ASSET'),0)),
 ('balance_equity',coalesce((select sum(balance_piasters) from public.v_balance_sheet_live where account_type='EQUITY'),0)),
 ('cost_center_profit',coalesce((select sum(net_profit_piasters) from public.v_cost_center_profit_loss),0));
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal','aal2')::text,true) from public.user_profiles where role='OWNER' and active limit 1;
do $$declare j uuid;rev uuid;revenue text;begin
 select code into strict revenue from public.chart_of_accounts where account_type='REVENUE' and is_active order by code limit 1;
 j:=public.create_manual_journal_draft(gen_random_uuid(),current_date,'AUDIT reversal arithmetic','1100',revenue,12345);
 perform public.post_journal_entry(j);
 insert into audit_reversal_result select 'posted_original_cash_12345',coalesce((select balance_piasters from public.v_journal_trial_balance where account_code='1100'),0)-(select value from audit_reversal_before where measure='trial_cash')=12345,'before reversal +123.45 EGP';
 rev:=public.reverse_journal_entry(j,'Synthetic audit reversal',current_date);
 insert into audit_reversal_result select 'original_and_reversal_audited',exists(select 1 from public.journal_entries where id=j and status='REVERSED') and exists(select 1 from public.journal_entries where id=rev and status='POSTED' and reversal_of=j) and exists(select 1 from public.audit_events where record_id=j::text and action='REVERSE'),'original retained, reversal linked, audit event recorded';
 begin
  perform public.reverse_journal_entry(j,'Duplicate synthetic reversal',current_date);
  insert into audit_reversal_result values('repeat_reversal_denied',false,'duplicate allowed');
 exception when others then insert into audit_reversal_result values('repeat_reversal_denied',true,sqlerrm);end;
end $$;
insert into audit_reversal_result
select 'reversal_zero_net_'||after.measure,after.value=before.value,'expected delta 0 piasters; actual '||(after.value-before.value)::text
from (values
 ('cash',coalesce((select sum(cash_change_piasters) from public.v_cash_movement_live),0)),
 ('trial_cash',coalesce((select balance_piasters from public.v_journal_trial_balance where account_code='1100'),0)),
 ('profit_loss',coalesce((select sum(amount_piasters) from public.v_profit_and_loss_live),0)),
 ('balance_assets',coalesce((select sum(balance_piasters) from public.v_balance_sheet_live where account_type='ASSET'),0)),
 ('balance_equity',coalesce((select sum(balance_piasters) from public.v_balance_sheet_live where account_type='EQUITY'),0)),
 ('cost_center_profit',coalesce((select sum(net_profit_piasters) from public.v_cost_center_profit_loss),0))) after(measure,value)
join audit_reversal_before before using(measure);
insert into audit_reversal_result select 'report_invoker_rls_'||c.relname,coalesce(c.reloptions,'{}') @> array['security_invoker=true'],'caller RLS remains enabled after replacement' from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in('v_journal_trial_balance','v_profit_and_loss_live','v_cash_movement_live','v_balance_sheet_live','v_cost_center_profit_loss','v_production_health');
select jsonb_agg(to_jsonb(r)) results from audit_reversal_result r;
rollback;
