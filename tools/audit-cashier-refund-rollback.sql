-- Run ONLY on the independently verified Bradford Finance Staging project.
-- Synthetic records only; the whole transaction is rolled back. Sequences may advance.
begin;
set local statement_timeout = '20s';
create temp table audit_result(test text, passed boolean, detail text);
create temp table audit_context(actor uuid, readonly_actor uuid, organization_b uuid, student_b uuid, account_b uuid, own_account uuid, own_batch uuid);
grant select,update on audit_context to authenticated;
grant insert,select on audit_result to authenticated;

-- Verify the summary without changing or depending on imported customer rows.
do $$declare baseline numeric;after_total numeric;s uuid;a uuid;begin
 select total_revenue_piasters into baseline from public.v_finance_all_time_summary;
 s:=gen_random_uuid();insert into public.students(id,student_code,student_name,grade) values(s,'AUDIT-'||s,'Summary active','Grade 1');
 insert into public.student_accounts(student_id,academic_year,legacy_paid_piasters,source_meta) values(s,'2026-2027',12345,'{"superseded":false}');
 a:=gen_random_uuid();insert into public.students(id,student_code,student_name,grade) values(a,'AUDIT-'||a,'Summary archived','Grade 1');
 insert into public.student_accounts(student_id,academic_year,legacy_paid_piasters,source_meta) values(a,'2026-2027',45678,'{"superseded":true}');
 select total_revenue_piasters into after_total from public.v_finance_all_time_summary;
 insert into audit_result values('summary_excludes_archived_accounts',after_total-baseline=12345,'only active 123.45 EGP added; archived 456.78 excluded');
end $$;

do $$
declare u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();o uuid:=gen_random_uuid();s uuid:=gen_random_uuid();a uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,raw_user_meta_data) values(u,'audit-'||u||'@example.invalid','{}'),(r,'audit-'||r||'@example.invalid','{}');
 update public.user_profiles set role='ACCOUNTANT',active=true where user_id=u;
 update public.user_profiles set role='READ_ONLY',active=true where user_id=r;
 insert into public.erp_user_scopes(user_id,organization_id) values(u,public.default_organization_id()),(r,public.default_organization_id());
 insert into public.erp_organizations(id,organization_code,organization_name) values(o,'AUDIT-'||o,'Disposable audit tenant');
 insert into public.students(id,student_code,student_name,grade,organization_id) values(s,'AUDIT-'||s,'Disposable audit student','Grade 1',o);
 insert into public.student_accounts(id,student_id,academic_year,organization_id) values(a,s,'2026-2027',o);
 insert into audit_context(actor,readonly_actor,organization_b,student_b,account_b) values(u,r,o,s,a);
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','aal','aal1')::text,true) from audit_context;
set local role authenticated;
do $$
declare s uuid;a uuid;b uuid;b2 uuid;visible integer;before_count integer;msg text;step text:='create student';k text:=gen_random_uuid()::text;
begin
 begin
  s:=public.create_student_with_account('AUDIT-'||gen_random_uuid(),'Audit correct input','Grade 1','2026-2027',null,'Test guardian',null,null,null,null);
  step:='read student account';
  select id into a from public.student_accounts where student_id=s;
  insert into audit_result select 'student_atomic_zero_account',a is not null and total_due_piasters=0 and legacy_paid_piasters=0 and legacy_remaining_piasters=0,'one student and zero-value account' from public.student_accounts where id=a;
  begin
   perform public.create_student_with_account((select student_code from public.students where id=s),'Duplicate','Grade 1','2026-2027');
   insert into audit_result values('duplicate_code_denied',false,'duplicate accepted');
  exception when others then insert into audit_result values('duplicate_code_denied',true,sqlerrm);end;
  begin
   perform public.create_student_with_account('','Empty code','Grade 1','2026-2027');
   insert into audit_result values('empty_code_denied',false,'empty accepted');
  exception when others then insert into audit_result values('empty_code_denied',true,sqlerrm);end;
  begin
   perform public.create_student_with_account('AUDIT-BAD-'||gen_random_uuid(),'Bad email','Grade 1','2026-2027',null,null,null,null,'invalid',null);
   insert into audit_result values('invalid_email_denied',false,'invalid accepted');
  exception when others then insert into audit_result values('invalid_email_denied',true,sqlerrm);end;
  step:='create cashier batch';
  b:=public.create_student_payment_batch(a,current_date,k,'[{"category":"TUITION","description":"Synthetic fee","paid_now_piasters":12345}]','[{"method":"CASH","amount_piasters":12345}]');
  step:='replay cashier batch';
  b2:=public.create_student_payment_batch(a,current_date,k,'[{"category":"TUITION","description":"Synthetic fee","paid_now_piasters":12345}]','[{"method":"CASH","amount_piasters":12345}]');
  insert into audit_result values('same_key_replay_one_batch',b=b2,'same id returned');
  begin
   perform public.create_student_payment_batch(a,current_date,k,'[{"category":"TUITION","paid_now_piasters":1}]','[{"method":"CASH","amount_piasters":1}]');
   insert into audit_result values('same_key_changed_payload_denied',false,'changed payload accepted');
  exception when others then insert into audit_result values('same_key_changed_payload_denied',true,sqlerrm);end;
  insert into audit_result select 'draft_no_financial_effect',not exists(select 1 from public.student_payments where account_id=a and status='POSTED'),'draft leaves posted ledger unchanged';
  step:='submit cashier batch';
  perform public.submit_student_payment_batch(b);
  perform public.submit_student_payment_batch(b);
  step:='read cashier batch';
  insert into audit_result select 'submit_batch',status='SUBMITTED','submitted once; repeated submission is a no-op' from public.student_payment_batches where id=b;
  update audit_context set own_account=a,own_batch=b;
  select count(*) into before_count from public.student_payment_batches;
  begin
   perform public.create_student_payment_batch(a,current_date,gen_random_uuid()::text,'[{"category":"TUITION","paid_now_piasters":5000}]','[{"method":"CASH","amount_piasters":4900}]');
   insert into audit_result values('unbalanced_tenders_denied',false,'mismatch accepted');
  exception when others then insert into audit_result values('unbalanced_tenders_denied',true,sqlerrm);end;
  begin
   perform public.create_student_payment_batch(a,current_date,gen_random_uuid()::text,'[{"category":"TUITION","paid_now_piasters":5000}]','[{"method":"BANK_TRANSFER","amount_piasters":5000}]');
   insert into audit_result values('noncash_missing_bank_denied',false,'non-cash without bank accepted');
  exception when others then insert into audit_result values('noncash_missing_bank_denied',sqlerrm like '%Bank account is required%',sqlerrm);end;
  b2:=gen_random_uuid();
  perform public.create_manual_journal_draft(b2,current_date,'Synthetic atomic journal','1100','1300',12345);
  perform public.create_manual_journal_draft(b2,current_date,'Synthetic atomic journal','1100','1300',12345);
  insert into audit_result select 'manual_journal_atomic_replay',count(*)=2 and sum(debit_piasters)=12345 and sum(credit_piasters)=12345,'one replayed draft; exactly two balanced lines' from public.journal_lines where entry_id=b2;
  begin
   perform public.create_manual_journal_draft(b2,current_date,'Synthetic atomic journal','1100','1300',999);
   insert into audit_result values('manual_journal_changed_replay_denied',false,'changed replay accepted');
  exception when others then insert into audit_result values('manual_journal_changed_replay_denied',true,sqlerrm);end;
  b2:=gen_random_uuid();
  begin
   perform public.create_manual_journal_draft(b2,current_date,'Synthetic invalid journal','1100','AUDIT-NONEXISTENT',12345);
   insert into audit_result values('manual_invalid_account_no_residue',false,'invalid account accepted');
  exception when others then insert into audit_result select 'manual_invalid_account_no_residue',not exists(select 1 from public.journal_entries where id=b2),'invalid account leaves no header';end;
  insert into audit_result select 'failed_batch_no_residue',count(*)=before_count,'batch count unchanged after failed RPC' from public.student_payment_batches;
 exception when others then insert into audit_result values('student_and_cashier_workflow',false,step||': '||sqlerrm);end;
 select count(*) into visible from public.student_accounts where id=(select account_b from audit_context);
 insert into audit_result values('cross_tenant_select_denied',visible=0,'foreign account invisible via RLS');
 begin
  b:=public.create_student_payment_batch((select account_b from audit_context),current_date,gen_random_uuid()::text,'[{"category":"TUITION","paid_now_piasters":100}]','[{"method":"CASH","amount_piasters":100}]');
  insert into audit_result values('cross_tenant_rpc_denied',false,'SECURITY DEFINER accepted another tenant account');
 exception when others then insert into audit_result values('cross_tenant_rpc_denied',true,sqlerrm);end;
end $$;
reset role;
-- Use the existing configured approver identity only as an in-transaction claims
-- context; no login credentials or real user rows are changed.
select set_config('request.jwt.claims',jsonb_build_object('sub',approver_user_id,'role','authenticated','aal','aal1')::text,true) from public.approval_authorities where scope='PAYMENTS_EXPENSES' and active;
set local role authenticated;
do $$
declare b uuid;msg text;approved boolean:=false;
begin
 select own_batch into b from audit_context;
 if b is null then insert into audit_result values('approval_workflow',false,'creation prerequisite failed');return;end if;
 begin
  perform public.review_student_payment_batch(b,'REJECT','Synthetic rejection');
  insert into audit_result values('aal1_review_denied',false,'review allowed without MFA');
 exception when others then insert into audit_result values('aal1_review_denied',sqlerrm like '%MFA%',sqlerrm);end;
 perform set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}'::jsonb)::text,true);
 begin
  perform public.review_student_payment_batch(b,'APPROVE',null);
  select status='POSTED' into approved from public.student_payment_batches where id=b;
  insert into audit_result values('approval_posts_batch',approved,'POSTED after AAL2 approval');
 exception when others then insert into audit_result values('approval_posts_batch',false,sqlerrm);end;
end $$;
reset role;
-- Independent operator assertions avoid making the test depend on approver read grants.
insert into audit_result
 select 'posted_journal_balanced',count(*)=1 and bool_and(d=12345 and c=12345),'123.45 EGP debit equals credit'
 from(select e.id,sum(l.debit_piasters)d,sum(l.credit_piasters)c from public.journal_entries e join public.journal_lines l on l.entry_id=e.id where e.source_module='student_payment_batches' and e.source_id=(select own_batch from audit_context) and e.status='POSTED' group by e.id)x;
insert into audit_result select 'posted_cash_matches_receipt',coalesce(sum(amount_piasters),0)=12345,'cash movement equals receipt' from public.treasury_transactions where payment_batch_id=(select own_batch from audit_context) and status='POSTED';
select set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','aal','aal1')::text,true) from audit_context;
set local role authenticated;
-- Additional synthetic receipt cancellation/refund acceptance checks.
-- The enclosing audit transaction is rolled back.
do $$declare d uuid;begin
 begin
  perform public.reverse_student_payment_batch((select own_batch from audit_context),'Accountant attempt',current_date,false);
  insert into audit_result values('accountant_refund_denied',false,'accepted');
 exception when others then insert into audit_result values('accountant_refund_denied',sqlerrm like '%Only Finance Admin%',sqlerrm);end;
 d:=public.create_student_payment_batch((select own_account from audit_context),current_date,gen_random_uuid()::text,'[{"category":"TUITION","paid_now_piasters":123}]','[{"method":"CASH","amount_piasters":123}]');
 perform public.void_student_payment_batch(d,'Synthetic cancellation');perform public.void_student_payment_batch(d,'Synthetic cancellation');
 insert into audit_result select 'draft_cancel_replay',status='VOID' and voided_by=auth.uid(),'same cancellation is a no-op' from public.student_payment_batches where id=d;
 insert into audit_result select 'draft_cancel_no_money',not exists(select 1 from public.student_payments where payment_batch_id=d),'cancelled before approval';
 begin perform public.submit_student_payment_batch(d);insert into audit_result values('cancelled_cannot_submit',false,'accepted');exception when others then insert into audit_result values('cancelled_cannot_submit',true,sqlerrm);end;
end $$;
reset role;
-- Synthetic finance manager has only tenant A: admin role is not a tenant bypass.
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal','aal2')::text,true) from public.user_profiles where role='OWNER' and active limit 1;
update public.user_profiles set role='FINANCE_MANAGER' where user_id=(select actor from audit_context);
insert into public.student_payment_batches(account_id,student_id,receipt_number,verification_code,idempotency_key,transaction_date,total_piasters,created_by,updated_by)
 select account_b,student_b,'AUDIT-B-'||gen_random_uuid(),gen_random_uuid()::text,gen_random_uuid()::text,current_date,1,actor,actor from audit_context;
create temp table audit_foreign_batch as select id from public.student_payment_batches where receipt_number like 'AUDIT-B-%';
grant select on audit_foreign_batch to authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','aal','aal2')::text,true) from audit_context;
set local role authenticated;
do $$begin
 begin perform public.reverse_student_payment_batch((select id from audit_foreign_batch limit 1),'Foreign reversal',current_date,false);insert into audit_result values('cross_scope_admin_refund_denied',false,'accepted');exception when others then insert into audit_result values('cross_scope_admin_refund_denied',sqlerrm like '%not found or not authorized%',sqlerrm);end;
end $$;
reset role;
-- OWNER is used as an in-transaction claims context only; no credentials are changed.
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal','aal1')::text,true) from public.user_profiles where role='OWNER' and active limit 1;
set local role authenticated;
do $$declare b uuid:=(select own_batch from audit_context);j uuid;j2 uuid;begin
 insert into audit_result select 'db_paid_counts_collection_once',legacy_paid_piasters-opening_paid_piasters=12345,'database aggregate includes the 123.45 EGP collection exactly once' from public.student_accounts where id=(select own_account from audit_context);
 begin perform public.reverse_student_payment_batch(b,'Synthetic cash refund',current_date,false);insert into audit_result values('refund_mfa_required',false,'accepted');exception when others then insert into audit_result values('refund_mfa_required',sqlerrm like '%MFA%',sqlerrm);end;
 perform set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"aal":"aal2"}')::text,true);
 begin perform public.reverse_financial_record('student_payments',(select id from public.student_payments where payment_batch_id=b limit 1),'Detached correction',current_date);insert into audit_result values('standalone_payment_reverse_denied',false,'accepted');exception when others then insert into audit_result values('standalone_payment_reverse_denied',sqlerrm like '%unified receipt reversal%',sqlerrm);end;
 begin perform public.reverse_journal_entry((select id from public.journal_entries where source_module='student_payment_batches' and source_id=b),'Detached correction',current_date);insert into audit_result values('standalone_journal_reverse_denied',false,'accepted');exception when others then insert into audit_result values('standalone_journal_reverse_denied',sqlerrm like '%unified receipt reversal%',sqlerrm);end;
 j:=public.reverse_student_payment_batch(b,'Synthetic cash refund',current_date,false);j2:=public.reverse_student_payment_batch(b,'Synthetic cash refund',current_date,false);
 insert into audit_result values('refund_exact_replay_once',j=j2,'same reversal journal returned');
 begin perform public.reverse_student_payment_batch(b,'Changed refund reason',current_date,false);insert into audit_result values('refund_changed_replay_denied',false,'accepted');exception when others then insert into audit_result values('refund_changed_replay_denied',true,sqlerrm);end;
 insert into audit_result select 'refunded_student_net_zero',sum(amount_piasters*effect_sign)=0,'original REVERSED plus signed POSTED reversal' from public.student_payments where payment_batch_id=b and status in('POSTED','REVERSED');
 insert into audit_result select 'refunded_stored_total_zero',legacy_paid_piasters=opening_paid_piasters,'stored paid returns to opening paid' from public.student_accounts where id=(select own_account from audit_context);
 insert into audit_result select 'refunded_cash_net_zero',sum(case direction when 'RECEIPT' then amount_piasters else -amount_piasters end)=0 and count(*)=2,'123.45 receipt and 123.45 payment' from public.treasury_transactions where payment_batch_id=b and status='POSTED';
 insert into audit_result select 'refunded_journal_cash_net_zero',sum(l.debit_piasters-l.credit_piasters)=0,'original journal retained alongside reversal' from public.journal_lines l join public.journal_entries e on e.id=l.entry_id where l.account_code='1100' and (e.id=j or (e.source_module='student_payment_batches' and e.source_id=b));
 insert into audit_result select 'refund_audit_and_links',jsonb_array_length(movements)=2 and exists(select 1 from public.audit_events where record_id=b::text and action='REVERSE_BATCH'),'payment and treasury IDs retained' from public.student_payment_batch_reversals where batch_id=b;
end $$;
reset role;
create temp table audit_refund_stock(book uuid,uniform uuid,bank uuid,charge uuid,batch uuid,cancel_batch uuid);
grant select,update on audit_refund_stock to authenticated;
do $$declare bk uuid;un uuid;ba uuid;ch uuid;begin
 insert into public.book_items(sku,item_name,stock_quantity,selling_price_piasters) values('AUDIT-'||gen_random_uuid(),'Synthetic book',10,2000) returning id into bk;
 insert into public.uniform_items(sku,item_name,stock_quantity,selling_price_piasters) values('AUDIT-'||gen_random_uuid(),'Synthetic uniform',10,6000) returning id into un;
 insert into public.bank_accounts(bank_name,account_label,gl_account_code) values('AUDIT bank','Disposable test account','1200') returning id into ba;
 insert into public.student_charges(account_id,due_date,category,amount_piasters,posting_status) values((select own_account from audit_context),current_date,'TUITION',10000,'POSTED') returning id into ch;
 insert into audit_refund_stock(book,uniform,bank,charge) values(bk,un,ba,ch);
end $$;
set local role authenticated;
do $$declare b uuid;c uuid;begin
 b:=public.create_student_payment_batch((select own_account from audit_context),current_date,gen_random_uuid()::text,
 jsonb_build_array(jsonb_build_object('category','BOOKS','paid_now_piasters',4000,'book_item_id',(select book from audit_refund_stock),'quantity',2),jsonb_build_object('category','UNIFORM','paid_now_piasters',6000,'uniform_item_id',(select uniform from audit_refund_stock),'quantity',1),jsonb_build_object('category','TUITION','paid_now_piasters',10000,'charge_id',(select charge from audit_refund_stock))),
 jsonb_build_array(jsonb_build_object('method','CASH','amount_piasters',8000),jsonb_build_object('method','QNB','amount_piasters',12000,'bank_account_id',(select bank from audit_refund_stock))));
 perform public.submit_student_payment_batch(b);
 c:=public.create_student_payment_batch((select own_account from audit_context),current_date,gen_random_uuid()::text,jsonb_build_array(jsonb_build_object('category','BOOKS','paid_now_piasters',2000,'book_item_id',(select book from audit_refund_stock),'quantity',1)),'[{"method":"CASH","amount_piasters":2000}]');
 perform public.void_student_payment_batch(c,'Cancel stock reservation');
 insert into audit_result select 'draft_cancel_releases_stock',status='RELEASED','stock reservation released before issue' from public.student_stock_reservations where batch_id=c;
 update audit_refund_stock set batch=b,cancel_batch=c;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',approver_user_id,'role','authenticated','aal','aal2')::text,true) from public.approval_authorities where scope='PAYMENTS_EXPENSES' and active;
set local role authenticated;
select public.review_student_payment_batch((select batch from audit_refund_stock),'APPROVE',null);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal','aal2')::text,true) from public.user_profiles where role='OWNER' and active limit 1;
set local role authenticated;
do $$declare b uuid:=(select batch from audit_refund_stock);begin
 insert into audit_result select 'split_payment_and_stock_issued',stock_quantity=8,'two books issued exactly once' from public.book_items where id=(select book from audit_refund_stock);
 insert into audit_result select 'allocated_charge_paid',status='PAID','full tuition allocation marks charge paid' from public.student_charges where id=(select charge from audit_refund_stock);
 begin perform public.reverse_student_payment_batch(b,'No returned stock',current_date,false);insert into audit_result values('stock_return_confirmation_required',false,'accepted');exception when others then insert into audit_result values('stock_return_confirmation_required',sqlerrm like '%returned stock%',sqlerrm);end;
 begin perform public.reverse_student_payment_batch(b,'Future refund date',current_date+1,true);insert into audit_result values('refund_future_date_denied',false,'accepted');exception when others then insert into audit_result values('refund_future_date_denied',sqlerrm like '%valid reversal date%',sqlerrm);end;
end $$;
reset role;
-- Force failure after payments, journals, bank and stock have been changed.
create function public.audit_refund_fail() returns trigger language plpgsql as $$begin raise exception 'Injected refund failure';end$$;
create trigger audit_refund_fail before insert on public.student_payment_batch_reversals for each row execute function public.audit_refund_fail();
set local role authenticated;
do $$declare b uuid:=(select batch from audit_refund_stock);begin
 begin perform public.reverse_student_payment_batch(b,'Forced rollback refund',current_date,true);insert into audit_result values('mid_refund_failure_caught',false,'unexpected success');exception when others then insert into audit_result values('mid_refund_failure_caught',sqlerrm like '%Injected refund failure%',sqlerrm);end;
 insert into audit_result select 'failed_refund_all_or_nothing',status='POSTED' and not exists(select 1 from public.student_payment_batch_reversals where batch_id=b) and (select stock_quantity from public.book_items where id=(select book from audit_refund_stock))=8 and (select count(*) from public.student_payments where payment_batch_id=b)=3 and (select count(*) from public.bank_transactions where payment_batch_id=b)=1,'no reversal rows or stock changes survive a failure at the final insert' from public.student_payment_batches where id=b;
end $$;
reset role;
drop trigger audit_refund_fail on public.student_payment_batch_reversals;
drop function public.audit_refund_fail();
do $$begin
 begin
  insert into public.accounting_periods(period_code,start_date,end_date,status) values('AUDIT-'||gen_random_uuid(),current_date,current_date,'LOCKED');
  perform public.reverse_student_payment_batch((select batch from audit_refund_stock),'Locked period refund',current_date,true);
  raise exception 'Unexpected refund acceptance';
 exception when others then insert into audit_result values('refund_locked_period_denied',sqlerrm ilike '%locked%',sqlerrm);end;
end $$;
set local role authenticated;
select public.reverse_student_payment_batch((select batch from audit_refund_stock),'Synthetic stock refund',current_date,true);
insert into audit_result select 'stock_restored_exactly',stock_quantity=10,'book stock restored from 8 to 10' from public.book_items where id=(select book from audit_refund_stock);
insert into audit_result select 'uniform_restored_exactly',stock_quantity=10,'uniform stock restored from 9 to 10' from public.uniform_items where id=(select uniform from audit_refund_stock);
insert into audit_result select 'split_bank_refund_balanced',sum(credit_piasters-debit_piasters)=0 and count(*)=2,'120.00 EGP bank credit and reversing debit' from public.bank_transactions where payment_batch_id=(select batch from audit_refund_stock);
insert into audit_result select 'split_cash_refund_balanced',sum(case direction when 'RECEIPT' then amount_piasters else -amount_piasters end)=0 and count(*)=2,'80.00 EGP cash receipt and reversing payment' from public.treasury_transactions where payment_batch_id=(select batch from audit_refund_stock) and status='POSTED';
insert into audit_result select 'charge_reopened_after_refund',status='OPEN' and not exists(select 1 from public.student_payment_allocations where charge_id=c.id and active),'charge remains due; previous allocation inactive' from public.student_charges c where id=(select charge from audit_refund_stock);
insert into audit_result select 'split_refund_all_links',jsonb_array_length(movements)=5,'3 student movements, cash and bank linked to originals' from public.student_payment_batch_reversals where batch_id=(select batch from audit_refund_stock);
insert into audit_result select 'all_refunds_student_paid_zero',legacy_paid_piasters=opening_paid_piasters,'both full refunds return student paid to opening balance' from public.student_accounts where id=(select own_account from audit_context);
reset role;

reset role;
reset role;
create temp table audit_transport_refund(route uuid,batch uuid,enrollment uuid,dependent uuid);
grant select,update on audit_transport_refund to authenticated;
with r as(insert into public.transport_routes(route_code,route_name,academic_year,annual_fee_piasters) values('AUDIT-'||gen_random_uuid(),'Synthetic refund route','2026-2027',5000) returning id) insert into audit_transport_refund(route) select id from r;
set local role authenticated;
do $$declare b uuid;d uuid;begin
 b:=public.create_student_payment_batch((select own_account from audit_context),current_date,gen_random_uuid()::text,jsonb_build_array(jsonb_build_object('category','TRANSPORT','paid_now_piasters',5000,'transport_route_id',(select route from audit_transport_refund),'pickup_point','Synthetic stop','transport_fee_piasters',5000)),'[{"method":"CASH","amount_piasters":5000}]');
 perform public.submit_student_payment_batch(b);
 update audit_transport_refund set batch=b,enrollment=(select transport_enrollment_id from public.student_payment_lines where batch_id=b);
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',approver_user_id,'role','authenticated','aal','aal2')::text,true) from public.approval_authorities where scope='PAYMENTS_EXPENSES' and active;
set local role authenticated;
select public.review_student_payment_batch((select batch from audit_transport_refund),'APPROVE',null);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal','aal2')::text,true) from public.user_profiles where role='OWNER' and active limit 1;
set local role authenticated;
insert into audit_result select 'transport_activated_after_approval',status='ACTIVE','new paid enrollment activated' from public.transport_enrollments where id=(select enrollment from audit_transport_refund);
do $$declare d uuid;begin
 d:=public.create_student_payment_batch((select own_account from audit_context),current_date,gen_random_uuid()::text,jsonb_build_array(jsonb_build_object('category','TRANSPORT','paid_now_piasters',1000,'transport_enrollment_id',(select enrollment from audit_transport_refund))),'[{"method":"CASH","amount_piasters":1000}]');
 update audit_transport_refund set dependent=d;
 begin perform public.reverse_student_payment_batch((select batch from audit_transport_refund),'Transport dependency refund',current_date,false);insert into audit_result values('transport_dependent_receipt_blocks_refund',false,'accepted');exception when others then insert into audit_result values('transport_dependent_receipt_blocks_refund',sqlerrm like '%Another receipt uses%',sqlerrm);end;
 perform public.void_student_payment_batch(d,'Cancel dependent draft');
 perform public.reverse_student_payment_batch((select batch from audit_transport_refund),'Synthetic transport refund',current_date,false);
end $$;
insert into audit_result select 'transport_cancelled_after_full_refund',status='CANCELLED','only the enrollment created by this receipt is cancelled' from public.transport_enrollments where id=(select enrollment from audit_transport_refund);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','aal','aal2')::text,true) from public.user_profiles where role='OWNER' and active limit 1;
set local role authenticated;
do $$declare t uuid;rv uuid;j uuid;base bigint;begin
 select live_treasury_delta_piasters into base from public.v_live_cash_position;
 insert into public.treasury_transactions(transaction_date,direction,amount_piasters,payment_method,counterparty,category,description,status,counter_account_code,created_by,updated_by) values(current_date,'RECEIPT',500,'CASH','Synthetic counterparty','TEST','Workflow test','DRAFT','1300',auth.uid(),auth.uid()) returning id into t;
 perform public.submit_financial_record('treasury_transactions',t);
 insert into audit_result select 'treasury_submit_rpc_executes',status='SUBMITTED','actual authenticated caller reaches scoped private implementation' from public.treasury_transactions where id=t;
 perform public.approve_financial_record('treasury_transactions',t,'Synthetic approval');
 insert into audit_result select 'treasury_approve_and_cash_direction',status='POSTED' and (select live_treasury_delta_piasters-base from public.v_live_cash_position)=500,'RECEIPT increases cash by 5.00 EGP' from public.treasury_transactions where id=t;
 rv:=public.reverse_financial_record('treasury_transactions',t,'Synthetic treasury reversal',current_date);
 insert into audit_result select 'treasury_reverse_direction_correct',direction='PAYMENT' and reversal_of=t and status='POSTED','opposite direction is valid for the actual schema' from public.treasury_transactions where id=rv;
 insert into audit_result select 'treasury_reversal_report_returns_zero',live_treasury_delta_piasters=base,'cash position returns to its independent baseline' from public.v_live_cash_position;
 insert into public.treasury_transactions(transaction_date,direction,amount_piasters,payment_method,counterparty,category,description,status,counter_account_code,created_by,updated_by) values(current_date,'PAYMENT',200,'CASH','Synthetic counterparty','TEST','Rejection test','DRAFT','1300',auth.uid(),auth.uid()) returning id into t;
 perform public.submit_financial_record('treasury_transactions',t);
 perform public.reject_financial_record('treasury_transactions',t,'Synthetic rejection');
 insert into audit_result select 'treasury_reject_returns_draft',status='DRAFT','rejected pending record is editable again' from public.treasury_transactions where id=t;
 perform public.void_financial_draft('treasury_transactions',t,'Synthetic void reason');
 insert into audit_result select 'treasury_void_rpc_executes',status='VOID','draft cancelled without posting' from public.treasury_transactions where id=t;
 j:=public.create_manual_journal_draft(gen_random_uuid(),current_date,'Synthetic journal RPC permissions','1100','1300',321);
 perform public.post_journal_entry(j);
 rv:=public.reverse_journal_entry(j,'Synthetic manual reversal',current_date);
 insert into audit_result select 'manual_post_and_reverse_authenticated',sum(l.debit_piasters-l.credit_piasters)=0,'both private delegates execute for authorized caller' from public.journal_lines l where l.account_code='1100' and l.entry_id in(j,rv);
end $$;
reset role;
create temp table audit_foreign_journal(id uuid);
grant select on audit_foreign_journal to authenticated;
select set_config('request.jwt.claims','{}',true);
with created as(insert into public.journal_entries(transaction_date,description,status,organization_id,created_by) select current_date,'Synthetic foreign journal','DRAFT',organization_b,actor from audit_context returning id) insert into audit_foreign_journal select id from created;
select set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','aal','aal2')::text,true) from audit_context;
set local role authenticated;
do $$begin
 begin perform public.post_journal_entry((select id from audit_foreign_journal));insert into audit_result values('scoped_admin_foreign_journal_denied',false,'accepted');exception when others then insert into audit_result values('scoped_admin_foreign_journal_denied',sqlerrm like '%organization scope denied%',sqlerrm);end;
 begin perform public.submit_financial_record('students',gen_random_uuid());insert into audit_result values('financial_workflow_table_allowlist',false,'accepted');exception when others then insert into audit_result values('financial_workflow_table_allowlist',sqlerrm like '%Unsupported financial table%',sqlerrm);end;
end $$;
reset role;
insert into audit_result select 'private_workflow_exec_authenticated_only',bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')),'seven intended private delegates; anonymous still denied' from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in('submit_financial_record','approve_financial_record','reject_financial_record','void_financial_draft','reverse_financial_record','post_journal_entry','reverse_journal_entry');
select set_config('request.jwt.claims',jsonb_build_object('sub',readonly_actor,'role','authenticated','aal','aal1')::text,true) from audit_context;
set local role authenticated;
do $$begin
 begin
  perform public.create_student_with_account('AUDIT-READONLY-'||gen_random_uuid(),'Denied','Grade 1','2026-2027');
  insert into audit_result values('readonly_create_denied',false,'write allowed');
 exception when others then insert into audit_result values('readonly_create_denied',true,sqlerrm);end;
end $$;
insert into audit_result select 'readonly_historical_data_denied',count(*)=0,'legacy import is not public to all authenticated users' from public.historical_revenue_entries;
insert into audit_result select 'readonly_refund_register_hidden',count(*)=0,'refund register follows batch row security' from public.student_payment_batch_reversals;
reset role;
select jsonb_agg(to_jsonb(r)) results from audit_result r;
rollback;
