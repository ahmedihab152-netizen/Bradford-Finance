begin;
create or replace function public.create_manual_journal_draft(p_id uuid,p_date date,p_description text,p_debit text,p_credit text,p_amount bigint)
returns uuid language plpgsql security invoker set search_path='' as $$
declare existing public.journal_entries%rowtype;
begin
 if auth.uid() is null or public.current_finance_role()::text not in('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT') then raise exception 'Not authorized';end if;
 if p_id is null or p_date is null or length(btrim(coalesce(p_description,'')))<1 or p_amount is null or p_amount<=0 or p_debit is null or p_credit is null or p_debit=p_credit then raise exception 'Invalid journal inputs';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into existing from public.journal_entries where id=p_id;
 if found then
  if existing.created_by is distinct from auth.uid() or existing.source_module is distinct from 'manual' or existing.description is distinct from btrim(p_description) or existing.transaction_date is distinct from p_date
   or (select count(*) from public.journal_lines where entry_id=p_id)<>2
   or not exists(select 1 from public.journal_lines where entry_id=p_id and line_no=1 and account_code=p_debit and debit_piasters=p_amount and credit_piasters=0)
   or not exists(select 1 from public.journal_lines where entry_id=p_id and line_no=2 and account_code=p_credit and credit_piasters=p_amount and debit_piasters=0)
  then raise exception 'Request identifier already used';end if;
  return p_id;
 end if;
 if (select count(*) from public.chart_of_accounts where code in(p_debit,p_credit) and is_active)<>2 then raise exception 'Two active accounts are required';end if;
 insert into public.journal_entries(id,transaction_date,description,source_module,status,created_by) values(p_id,p_date,btrim(p_description),'manual','DRAFT',auth.uid());
 insert into public.journal_lines(entry_id,line_no,account_code,debit_piasters,credit_piasters) values(p_id,1,p_debit,p_amount,0),(p_id,2,p_credit,0,p_amount);
 return p_id;
end $$;
revoke all on function public.create_manual_journal_draft(uuid,date,text,text,text,bigint) from public,anon;
grant execute on function public.create_manual_journal_draft(uuid,date,text,text,text,bigint) to authenticated;
commit;
