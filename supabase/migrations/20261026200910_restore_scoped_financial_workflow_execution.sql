begin;
-- Public invoker RPCs delegate to existing private definer functions. Their
-- callers need EXECUTE, but the definer must check tenant scope before access.
create or replace function private.assert_financial_record_scope(p_table text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare org uuid;batch uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 if p_table not in('expenses','student_payments','treasury_transactions','journal_entries') then raise exception 'Unsupported financial table';end if;
 execute format('select organization_id from public.%I where id=$1 for update',p_table) into org using p_id;
 if org is null or not public.can_access_organization(org) then raise exception 'Record not found or organization scope denied';end if;
 if p_table in('student_payments','treasury_transactions') then
  execute format('select payment_batch_id from public.%I where id=$1',p_table) into batch using p_id;
  if batch is not null then raise exception 'Use the unified receipt reversal or review';end if;
 end if;
end $$;
revoke all on function private.assert_financial_record_scope(text,uuid) from public,anon,authenticated;
do $guard$
declare signature regprocedure;name text;body text;patched text;args text;
begin
 foreach name in array array['submit_financial_record','approve_financial_record','reject_financial_record','void_financial_draft','reverse_financial_record','post_journal_entry','reverse_journal_entry'] loop
  select p.oid::regprocedure,pg_get_functiondef(p.oid) into signature,body from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname=name;
  if signature is null then raise exception 'Missing private workflow %',name;end if;
  args:=case when name in('post_journal_entry','reverse_journal_entry') then '''journal_entries'',p_entry_id' else 'p_table,p_id' end;
  patched:=regexp_replace(body,'\m[Bb][Ee][Gg][Ii][Nn]\M','begin'||chr(10)||' perform private.assert_financial_record_scope('||args||');');
  if patched=body then raise exception 'Workflow body shape changed for %',name;end if;
  if name='reject_financial_record' then patched:=replace(patched,'perform private.assert_financial_record_scope(p_table,p_id);','perform private.assert_financial_record_scope(p_table,p_id); perform private.require_admin_mfa_if_enabled();');end if;
  execute patched;
  execute format('revoke all on function %s from public,anon',signature);
  execute format('grant execute on function %s to authenticated',signature);
 end loop;
end $guard$;
-- Existing treasury rows use RECEIPT/PAYMENT, not IN/OUT. Reversed originals
-- remain in the signed ledger alongside their opposite-direction correction.
do $$declare definition text;revised text;begin
 definition:=pg_get_viewdef('public.v_live_cash_position'::regclass,true);
 revised:=replace(definition,'treasury_transactions.direction = ''IN''::text','treasury_transactions.direction = ''RECEIPT''::text');
 revised:=replace(revised,'treasury_transactions.status = ''POSTED''::record_status','treasury_transactions.status IN (''POSTED''::record_status,''REVERSED''::record_status)');
 if revised=definition then raise exception 'Cash position view definition changed';end if;
 execute 'create or replace view public.v_live_cash_position with (security_invoker=true) as '||revised;
end $$;
commit;
