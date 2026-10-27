begin;
alter table public.student_payment_batches add column if not exists voided_at timestamptz, add column if not exists voided_by uuid references auth.users(id), add column if not exists void_reason text;
alter table public.student_payment_batches drop constraint student_payment_batches_status_check;
alter table public.student_payment_batches add constraint student_payment_batches_status_check check(status in('DRAFT','SUBMITTED','POSTED','REJECTED','REVERSED','VOID'));
alter table public.student_payment_lines drop constraint student_payment_lines_status_check;
alter table public.student_payment_lines add constraint student_payment_lines_status_check check(status in('DRAFT','SUBMITTED','POSTED','REJECTED','REVERSED','VOID'));
create table public.student_payment_batch_reversals(
 batch_id uuid primary key references public.student_payment_batches(id),
 journal_entry_id uuid not null unique references public.journal_entries(id),
 transaction_date date not null,reason text not null check(length(btrim(reason))>=5),
 goods_returned boolean not null, movements jsonb not null,
 created_at timestamptz not null default now(),created_by uuid not null references auth.users(id)
);
alter table public.student_payment_batch_reversals enable row level security;
revoke all on public.student_payment_batch_reversals from public,anon,authenticated;
grant select on public.student_payment_batch_reversals to authenticated;
create policy batch_reversals_read on public.student_payment_batch_reversals for select to authenticated
 using(exists(select 1 from public.student_payment_batches b where b.id=batch_id));

create or replace function public.void_student_payment_batch(p_batch uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.student_payment_batches%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 select * into b from public.student_payment_batches where id=p_batch for update;
 if not found or not private.can_use_student_cashier(b.account_id) then raise exception 'Draft not found or not authorized';end if;
 if b.created_by<>auth.uid() and not public.is_finance_admin() then raise exception 'Only the maker or Finance Admin can cancel';end if;
 if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'A clear cancellation reason is required';end if;
 if b.status='VOID' then
  if b.void_reason is distinct from btrim(p_reason) then raise exception 'Cancellation already recorded with another reason';end if;
  return;
 end if;
 if b.status<>'DRAFT' then raise exception 'Only drafts can be cancelled; submitted receipts require approval review';end if;
 update public.student_payment_batches set status='VOID',voided_at=now(),voided_by=auth.uid(),void_reason=btrim(p_reason),updated_at=now(),updated_by=auth.uid() where id=p_batch;
 update public.student_payment_lines set status='VOID' where batch_id=p_batch;
 update public.student_stock_reservations set status='RELEASED',updated_at=now() where batch_id=p_batch and status='RESERVED';
 update public.transport_enrollments set status='CANCELLED',updated_at=now(),updated_by=auth.uid() where payment_batch_id=p_batch and status='SUSPENDED';
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by) values('student_payment_batches',p_batch::text,'VOID_DRAFT',jsonb_build_object('reason',btrim(p_reason)),auth.uid());
end $$;

create or replace function public.reverse_student_payment_batch(p_batch uuid,p_reason text,p_reversal_date date,p_goods_returned boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare b public.student_payment_batches%rowtype; prior public.student_payment_batch_reversals%rowtype;
 p public.student_payments%rowtype;t public.treasury_transactions%rowtype;k public.bank_transactions%rowtype;
 j uuid;reversed_j uuid;new_id uuid;org uuid;links jsonb:='[]';r record;debits bigint;credits bigint;
begin
 if auth.uid() is null or not public.is_finance_admin() then raise exception 'Only Finance Admin can reverse a posted receipt';end if;
 perform private.require_admin_mfa_if_enabled();
 select * into b from public.student_payment_batches where id=p_batch for update;
 if not found or not private.cashier_account_in_scope(b.account_id) then raise exception 'Receipt not found or not authorized';end if;
 if length(btrim(coalesce(p_reason,'')))<5 or p_reversal_date is null or p_reversal_date<b.transaction_date or p_reversal_date>current_date or p_goods_returned is null then raise exception 'Provide a clear reason and a valid reversal date';end if;
 select * into prior from public.student_payment_batch_reversals where batch_id=p_batch;
 if found then
  if prior.reason is distinct from btrim(p_reason) or prior.transaction_date is distinct from p_reversal_date or prior.goods_returned is distinct from p_goods_returned then raise exception 'Receipt already reversed with different details';end if;
  return prior.journal_entry_id;
 end if;
 if b.status<>'POSTED' then raise exception 'Only posted receipts can be reversed';end if;
 perform private.assert_open_accounting_period(p_reversal_date);
 if exists(select 1 from public.student_payment_lines where batch_id=p_batch and ig_exam_entry_id is not null) then raise exception 'Exam entry reversal requires its own examination workflow';end if;
 if exists(select 1 from public.student_payment_lines where batch_id=p_batch and (uniform_item_id is not null or book_item_id is not null)) and not p_goods_returned then raise exception 'Confirm receipt of all returned stock before reversing this receipt';end if;
 if exists(select 1 from public.student_payment_lines l where l.batch_id=p_batch and (l.uniform_item_id is not null or l.book_item_id is not null) and not exists(select 1 from public.student_stock_reservations s where s.line_id=l.id and s.batch_id=b.id and s.status='ISSUED' and s.quantity=l.quantity)) then raise exception 'Issued stock does not match receipt';end if;
 if exists(select 1 from public.transport_enrollments e join public.student_payment_lines l on l.transport_enrollment_id=e.id where e.payment_batch_id=p_batch and l.batch_id<>p_batch and l.status in('DRAFT','SUBMITTED','POSTED')) then raise exception 'Another receipt uses this transport enrollment';end if;
 select organization_id into org from public.student_accounts where id=b.account_id;
 perform 1 from public.student_payments where payment_batch_id=p_batch for update;
 if (select coalesce(sum(amount_piasters),0) from public.student_payments where payment_batch_id=p_batch and status='POSTED' and effect_sign=1 and organization_id=org)<>b.total_piasters or exists(select 1 from public.student_payments s where s.reversal_of in(select id from public.student_payments where payment_batch_id=p_batch)) then raise exception 'Payment ledger does not match receipt or already has a separate correction';end if;
 if exists(select 1 from public.student_payment_lines l where l.batch_id=p_batch and not exists(select 1 from public.student_payments s where s.id=l.legacy_payment_id and s.payment_line_id=l.id and s.account_id=b.account_id and s.amount_piasters=l.paid_now_piasters and s.status='POSTED')) then raise exception 'Receipt line payment link is incomplete';end if;
 perform 1 from public.treasury_transactions where payment_batch_id=p_batch for update;
 perform 1 from public.bank_transactions where payment_batch_id=p_batch for update;
 if (select coalesce(sum(amount_piasters),0) from public.treasury_transactions where payment_batch_id=p_batch and status='POSTED' and direction='RECEIPT' and organization_id=org)+(select coalesce(sum(credit_piasters),0) from public.bank_transactions where payment_batch_id=p_batch and organization_id=org)<>b.total_piasters then raise exception 'Cash and bank movements do not match receipt';end if;
 if exists(select 1 from public.bank_transactions where payment_batch_id=p_batch and debit_piasters>0) or exists(select 1 from public.treasury_transactions where payment_batch_id=p_batch and direction='PAYMENT') then raise exception 'Receipt already has an unlinked refund movement';end if;
 if (select count(*) from public.journal_entries where source_module='student_payment_batches' and source_id=p_batch and status='POSTED')<>1 then raise exception 'Receipt must have exactly one posted journal';end if;
 select id into j from public.journal_entries where source_module='student_payment_batches' and source_id=p_batch and status='POSTED' for update;
 if j is null then raise exception 'Posted receipt journal not found';end if;
 select sum(debit_piasters),sum(credit_piasters) into debits,credits from public.journal_lines where entry_id=j;
 if debits is distinct from b.total_piasters or credits is distinct from b.total_piasters then raise exception 'Receipt journal is not balanced to its total';end if;
 reversed_j:=private.reverse_journal_entry(j,btrim(p_reason),p_reversal_date);
 perform set_config('bradford.workflow','1',true);
 for p in select * from public.student_payments where payment_batch_id=p_batch and status='POSTED' and effect_sign=1 order by id loop
  insert into public.student_payments(account_id,transaction_date,amount_piasters,payment_method,receipt_number,notes,status,reversal_of,effect_sign,payment_category,category_label,division_code,cost_center_id,cashbox_id,payment_batch_id,journal_entry_id,approved_at,approved_by,created_by,updated_by,organization_id)
  values(p.account_id,p_reversal_date,p.amount_piasters,p.payment_method,'REV-'||p.receipt_number,btrim(p_reason),'POSTED',p.id,-1,p.payment_category,p.category_label,p.division_code,p.cost_center_id,p.cashbox_id,b.id,reversed_j,now(),auth.uid(),auth.uid(),auth.uid(),org) returning id into new_id;
  links:=links||jsonb_build_array(jsonb_build_object('table','student_payments','original',p.id,'reversal',new_id));
  update public.student_payments set status='REVERSED',reversed_at=now(),reversed_by=auth.uid(),reversal_reason=btrim(p_reason) where id=p.id;
 end loop;
 for t in select * from public.treasury_transactions where payment_batch_id=p_batch and status='POSTED' and direction='RECEIPT' order by id loop
  insert into public.treasury_transactions(voucher_number,transaction_date,direction,amount_piasters,payment_method,counterparty,category,description,student_id,status,reversal_of,approved_at,approved_by,created_by,updated_by,cashbox_id,payment_batch_id,journal_entry_id,cost_center_id,department_id,counter_account_code,organization_id)
  values('REV-'||t.voucher_number,p_reversal_date,'PAYMENT',t.amount_piasters,t.payment_method,t.counterparty,t.category,btrim(p_reason),t.student_id,'POSTED',t.id,now(),auth.uid(),auth.uid(),auth.uid(),t.cashbox_id,b.id,reversed_j,t.cost_center_id,t.department_id,t.counter_account_code,org) returning id into new_id;
  links:=links||jsonb_build_array(jsonb_build_object('table','treasury_transactions','original',t.id,'reversal',new_id));
 end loop;
 for k in select * from public.bank_transactions where payment_batch_id=p_batch and credit_piasters>0 order by id loop
  insert into public.bank_transactions(bank_account_id,transaction_date,value_date,debit_piasters,credit_piasters,description,bank_reference,scope,reconciliation_status,created_by,payment_batch_id,organization_id)
  values(k.bank_account_id,p_reversal_date,p_reversal_date,k.credit_piasters,0,'Receipt reversal: '||btrim(p_reason),k.bank_reference,k.scope,'BOOKS_ONLY',auth.uid(),b.id,org) returning id into new_id;
  links:=links||jsonb_build_array(jsonb_build_object('table','bank_transactions','original',k.id,'reversal',new_id));
 end loop;
 for r in select uniform_item_id,sum(quantity)::int quantity from public.student_stock_reservations where batch_id=p_batch and status='ISSUED' and uniform_item_id is not null group by uniform_item_id order by uniform_item_id loop
  update public.uniform_items set stock_quantity=stock_quantity+r.quantity where id=r.uniform_item_id;
 end loop;
 for r in select book_item_id,sum(quantity)::int quantity from public.student_stock_reservations where batch_id=p_batch and status='ISSUED' and book_item_id is not null group by book_item_id order by book_item_id loop
  update public.book_items set stock_quantity=stock_quantity+r.quantity where id=r.book_item_id;
 end loop;
 update public.student_stock_reservations set status='RELEASED',updated_at=now() where batch_id=p_batch and status='ISSUED';
 update public.student_payment_allocations set active=false,reversed_at=now(),reversed_by=auth.uid() where payment_id in(select id from public.student_payments where payment_batch_id=p_batch and effect_sign=1) and active;
 update public.student_charges c set status=case when coalesce((select sum(a.amount_piasters) from public.student_payment_allocations a where a.charge_id=c.id and a.active),0)>=c.amount_piasters then 'PAID' else 'OPEN' end,updated_at=now(),updated_by=auth.uid() where c.id in(select charge_id from public.student_payment_lines where batch_id=p_batch) and c.status not in('VOID','WAIVED');
 update public.transport_enrollments set status='CANCELLED',updated_at=now(),updated_by=auth.uid() where payment_batch_id=p_batch and status='ACTIVE';
 update public.student_payment_batches set status='REVERSED',reversed_at=now(),reversed_by=auth.uid(),reversal_reason=btrim(p_reason),updated_at=now(),updated_by=auth.uid() where id=p_batch;
 update public.student_payment_lines set status='REVERSED' where batch_id=p_batch;
 insert into public.student_payment_batch_reversals(batch_id,journal_entry_id,transaction_date,reason,goods_returned,movements,created_by) values(p_batch,reversed_j,p_reversal_date,btrim(p_reason),p_goods_returned,links,auth.uid());
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('student_payment_batches',p_batch::text,'REVERSE_BATCH',jsonb_build_object('journal_entry_id',reversed_j,'reason',btrim(p_reason)),auth.uid(),jsonb_build_object('movements',links,'goods_returned',p_goods_returned,'bank_refund_requires_reconciliation',true));
 return reversed_j;
end $$;
revoke all on function public.void_student_payment_batch(uuid,text),public.reverse_student_payment_batch(uuid,text,date,boolean) from public,anon;
grant execute on function public.void_student_payment_batch(uuid,text),public.reverse_student_payment_batch(uuid,text,date,boolean) to authenticated;

-- Do not let a standalone correction detach a batch's money from its receipt.
do $guard$
declare body text;
begin
 body:=pg_get_functiondef('private.reverse_financial_record(text,uuid,text,date)'::regprocedure);
 if position('IF NOT FOUND OR s.status' in body)=0 or position('IF NOT FOUND OR t.status' in body)=0 then raise exception 'Financial reversal definition changed';end if;
 body:=replace(body,'IF NOT FOUND OR s.status','IF s.payment_batch_id IS NOT NULL THEN RAISE EXCEPTION ''Use the unified receipt reversal'';END IF; IF NOT FOUND OR s.status');
 body:=replace(body,'IF NOT FOUND OR t.status','IF t.payment_batch_id IS NOT NULL THEN RAISE EXCEPTION ''Use the unified receipt reversal'';END IF; IF NOT FOUND OR t.status');
 body:=replace(body,'effect_sign,reversal_reason,gl_account_code)','effect_sign,reversal_reason,gl_account_code,organization_id)');
 body:=replace(body,'btrim(p_reason),e.gl_account_code) RETURNING','btrim(p_reason),e.gl_account_code,e.organization_id) RETURNING');
 body:=replace(body,'category_label,effect_sign,reversal_reason)','category_label,effect_sign,reversal_reason,organization_id)');
 body:=replace(body,'s.category_label,-1,btrim(p_reason)) RETURNING','s.category_label,-1,btrim(p_reason),s.organization_id) RETURNING');
 body:=replace(body,'reversal_reason,counter_account_code)','reversal_reason,counter_account_code,organization_id)');
 body:=replace(body,'btrim(p_reason),t.counter_account_code) RETURNING','btrim(p_reason),t.counter_account_code,t.organization_id) RETURNING');
 body:=replace(body,'CASE WHEN t.direction=''IN'' THEN ''OUT'' ELSE ''IN'' END','CASE WHEN t.direction=''RECEIPT'' THEN ''PAYMENT'' ELSE ''RECEIPT'' END');
 execute body;
 body:=pg_get_functiondef('private.create_source_journal(text,uuid,uuid)'::regprocedure);
 body:=replace(body,'status,reversal_of,created_by)','status,reversal_of,created_by,organization_id)');
 body:=replace(body,'coalesce(e.created_by,p_approver)) RETURNING','coalesce(e.created_by,p_approver),e.organization_id) RETURNING');
 body:=replace(body,'coalesce(s.created_by,p_approver)) RETURNING','coalesce(s.created_by,p_approver),s.organization_id) RETURNING');
 body:=replace(body,'coalesce(t.created_by,p_approver)) RETURNING','coalesce(t.created_by,p_approver),t.organization_id) RETURNING');
 body:=replace(replace(body,'t.direction=''IN''','t.direction=''RECEIPT'''),'t.direction=''OUT''','t.direction=''PAYMENT''');execute body;
 body:=pg_get_functiondef('private.reverse_journal_entry(uuid,text,date)'::regprocedure);
 body:=replace(body,'status,reversal_of,created_by)','status,reversal_of,created_by,organization_id)');
 body:=replace(body,'''DRAFT'',v.id,auth.uid()) RETURNING','''DRAFT'',v.id,auth.uid(),v.organization_id) RETURNING');
 execute body;
end $guard$;
create or replace function public.reverse_journal_entry(p_entry_id uuid,p_reason text,p_reversal_date date default current_date)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
 if exists(select 1 from public.journal_entries where id=p_entry_id and source_module='student_payment_batches') then raise exception 'Use the unified receipt reversal';end if;
 if exists(select 1 from public.journal_entries where id=p_entry_id and coalesce(source_module,'manual')<>'manual') then raise exception 'Reverse the original source transaction instead';end if;
 return private.reverse_journal_entry(p_entry_id,p_reason,p_reversal_date);
end $$;
create or replace function public.post_journal_entry(p_entry_id uuid)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if exists(select 1 from public.journal_entries where id=p_entry_id and source_module='student_payment_batches') then raise exception 'Use the unified receipt approval';end if;
 perform private.post_journal_entry(p_entry_id);
end $$;
commit;
