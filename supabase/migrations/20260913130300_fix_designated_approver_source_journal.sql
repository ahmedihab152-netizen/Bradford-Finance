-- Correct the source column name used by Bradford journal entries.
create or replace function private.post_journal_entry(p_entry_id uuid)
returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare
 v_role public.finance_role; v_status text; v_date date; v_debit bigint; v_credit bigint;
 v_source_module text; v_source_id uuid; v_source_status text; v_designated_source boolean:=false;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 v_role:=public.current_finance_role();
 select status::text,transaction_date,source_module,source_id into v_status,v_date,v_source_module,v_source_id
 from public.journal_entries where id=p_entry_id for update;
 if v_status is null then raise exception 'Journal entry not found'; end if;
 if public.is_dr_amany_payment_expense_approver() and v_source_module in ('student_payments','expenses') and v_source_id is not null then
   execute format('select status::text from public.%I where id=$1',v_source_module) into v_source_status using v_source_id;
   v_designated_source:=v_source_status='SUBMITTED';
 end if;
 if v_role not in ('OWNER','CEO','FINANCE_MANAGER') and not v_designated_source then raise exception 'Only Finance Admin can post journals'; end if;
 perform private.require_admin_mfa_if_enabled();
 if v_status not in ('DRAFT','SUBMITTED') then raise exception 'Journal cannot be posted from current status'; end if;
 perform private.assert_open_accounting_period(v_date);
 select coalesce(sum(debit_piasters),0),coalesce(sum(credit_piasters),0) into v_debit,v_credit from public.journal_lines where entry_id=p_entry_id;
 if v_debit=0 or v_debit<>v_credit then raise exception 'Journal is not balanced: debit %, credit %',v_debit,v_credit; end if;
 perform set_config('bradford.workflow','1',true);
 update public.journal_entries set status='POSTED',posted_at=now(),posted_by=auth.uid() where id=p_entry_id;
end $$;
revoke all on function private.post_journal_entry(uuid) from public,anon,authenticated;
