begin;
-- IG receipt creation retries must identify the same subjects and amounts.
create or replace function public.create_ig_exam_payment_batch(p_account_id uuid,p_transaction_date date,p_idempotency_key text,p_lines jsonb,p_tenders jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare b uuid;existing uuid;x jsonb;clean jsonb:='[]'::jsonb;entry public.ig_exam_entries%rowtype;paid bigint;
begin
 if auth.uid() is null or not private.can_use_student_cashier(p_account_id) then raise exception 'Not authorized for this student';end if;
 if nullif(btrim(p_idempotency_key),'') is null then raise exception 'Idempotency key is required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 select id into existing from public.student_payment_batches where idempotency_key=p_idempotency_key and account_id=p_account_id and created_by=auth.uid();
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one IG subject is required';end if;
 if jsonb_array_length(p_lines)<>(select count(distinct value->>'ig_exam_entry_id') from jsonb_array_elements(p_lines)) then raise exception 'Duplicate IG subject line';end if;
 for x in select value from jsonb_array_elements(p_lines) order by value->>'ig_exam_entry_id' loop
  select * into entry from public.ig_exam_entries where id=(x->>'ig_exam_entry_id')::uuid and account_id=p_account_id and status='POSTED' for update;
  if not found then raise exception 'Approved IG entry not found';end if;
  paid:=(x->>'paid_now_piasters')::bigint;
  if paid<=0 or (existing is null and paid>entry.fee_piasters-coalesce((select sum(l.paid_now_piasters) from public.student_payment_lines l where l.ig_exam_entry_id=entry.id and l.status='POSTED'),0)) then raise exception 'IG payment exceeds outstanding fee';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('category','EXAMS','description',x->>'description','due_piasters',entry.fee_piasters,'paid_now_piasters',paid,'cost_center_id',public.ig_cost_center_id(),'ig_exam_entry_id',entry.id));
 end loop;
 b:=public.create_student_payment_batch(p_account_id,p_transaction_date,p_idempotency_key,clean,p_tenders,p_notes);
 for x in select value from jsonb_array_elements(p_lines) order by value->>'ig_exam_entry_id' loop
  if exists(select 1 from public.student_payment_lines l where l.batch_id=b and l.ig_exam_entry_id=(x->>'ig_exam_entry_id')::uuid and l.description=x->>'description' and l.paid_now_piasters=(x->>'paid_now_piasters')::bigint) then continue;end if;
  update public.student_payment_lines set ig_exam_entry_id=(x->>'ig_exam_entry_id')::uuid
   where id=(select l.id from public.student_payment_lines l where l.batch_id=b and l.ig_exam_entry_id is null and l.description=x->>'description' and l.paid_now_piasters=(x->>'paid_now_piasters')::bigint limit 1);
  if not found then raise exception 'Unable to link IG subject line';end if;
 end loop;
 return b;
end $$;
-- Lock each subject and recheck the unpaid amount at approval, so two pending
-- receipts cannot both consume the same remaining fee.
do $patch$
declare body text;needle text;replacement text;
begin
 body:=pg_get_functiondef('public.review_student_payment_batch(uuid,text,text)'::regprocedure);
 needle:='perform private.assert_open_accounting_period(b.transaction_date);';
 if position(needle in body)=0 then raise exception 'Cashier approval definition changed';end if;
 replacement:=$q$for l in select * from public.student_payment_lines where batch_id=p_batch and ig_exam_entry_id is not null order by ig_exam_entry_id loop
   perform 1 from public.ig_exam_entries e where e.id=l.ig_exam_entry_id and e.account_id=b.account_id and e.status='POSTED' for update;
   if not found then raise exception 'Approved IG fee entry is not available';end if;
   if (select coalesce(sum(x.paid_now_piasters),0) from public.student_payment_lines x where x.ig_exam_entry_id=l.ig_exam_entry_id and x.status='POSTED')+(select coalesce(sum(x.paid_now_piasters),0) from public.student_payment_lines x where x.ig_exam_entry_id=l.ig_exam_entry_id and x.batch_id=p_batch)>(select fee_piasters from public.ig_exam_entries where id=l.ig_exam_entry_id) then raise exception 'IG payment exceeds outstanding fee at approval';end if;
 end loop;
 perform private.assert_open_accounting_period(b.transaction_date);$q$;
 body:=replace(body,needle,replacement);execute body;
 body:=pg_get_functiondef('public.reverse_student_payment_batch(uuid,text,date,boolean)'::regprocedure);
 needle:='if exists(select 1 from public.student_payment_lines where batch_id=p_batch and ig_exam_entry_id is not null) then raise exception ''Exam entry reversal requires its own examination workflow'';end if;';
 if position(needle in body)=0 then raise exception 'Refund definition changed';end if;
 body:=replace(body,needle,'-- Exam fee entry remains approved; reversed receipt lines no longer count as paid.');execute body;
 body:=pg_get_functiondef('public.review_ig_exam_entry(uuid,text,text)'::regprocedure);
 needle:='if not found or r.status<>''SUBMITTED'' then raise exception ''Only submitted entries can be reviewed'';end if;';
 if position(needle in body)=0 then raise exception 'IG review definition changed';end if;
 body:=replace(body,needle,needle||' if not private.cashier_account_in_scope(r.account_id) then raise exception ''Student account scope denied'';end if; perform private.require_admin_mfa_if_enabled();');execute body;
end $patch$;
-- The IG role needs only active, in-scope bank names and identifiers to
-- record a non-cash receipt; do not grant it access to all bank data.
create or replace function public.ig_cashier_bank_options()
returns table(id uuid,bank_name text,account_label text) language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or public.current_finance_role()::text not in('OWNER','FINANCE_MANAGER','IG_ACCOUNTANT') then raise exception 'Not authorized';end if;
 return query select b.id,b.bank_name,b.account_label from public.bank_accounts b where b.active and public.can_access_organization(b.organization_id) order by b.bank_name,b.account_label;
end $$;
revoke all on function public.ig_cashier_bank_options() from public,anon;
grant execute on function public.ig_cashier_bank_options() to authenticated;
commit;
