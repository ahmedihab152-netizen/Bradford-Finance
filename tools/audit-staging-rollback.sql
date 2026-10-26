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
select set_config('request.jwt.claims',jsonb_build_object('sub',readonly_actor,'role','authenticated','aal','aal1')::text,true) from audit_context;
set local role authenticated;
do $$begin
 begin
  perform public.create_student_with_account('AUDIT-READONLY-'||gen_random_uuid(),'Denied','Grade 1','2026-2027');
  insert into audit_result values('readonly_create_denied',false,'write allowed');
 exception when others then insert into audit_result values('readonly_create_denied',true,sqlerrm);end;
end $$;
insert into audit_result select 'readonly_historical_data_denied',count(*)=0,'legacy import is not public to all authenticated users' from public.historical_revenue_entries;
reset role;
select jsonb_agg(to_jsonb(r)) results from audit_result r;
rollback;
