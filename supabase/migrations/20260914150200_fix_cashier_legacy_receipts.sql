begin;
create or replace function public.review_student_payment_batch(p_batch uuid,p_action text,p_reason text default null) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare b public.student_payment_batches%rowtype;l public.student_payment_lines%rowtype;t public.student_payment_tenders%rowtype;v_pay uuid;v_method public.payment_method;v_je uuid;v_no int:=0;v_legacy_no int:=0;v_asset text;v_receivable text:='1300';begin
 if auth.uid() is null or not public.is_dr_amany_payment_expense_approver() then raise exception 'Only Dr. Amany Hussein can approve or reject';end if;
 select * into b from public.student_payment_batches where id=p_batch for update;if not found or b.status<>'SUBMITTED' then raise exception 'Only submitted batches can be reviewed';end if;
 if upper(p_action)='REJECT' then
   if p_reason is null or length(btrim(p_reason))<3 then raise exception 'Rejection reason is required';end if;
   update public.student_payment_batches set status='REJECTED',rejected_at=now(),rejected_by=auth.uid(),rejection_reason=btrim(p_reason),updated_at=now(),updated_by=auth.uid() where id=p_batch;
   update public.student_payment_lines set status='REJECTED' where batch_id=p_batch;update public.student_stock_reservations set status='RELEASED',updated_at=now() where batch_id=p_batch and status='RESERVED';
   update public.transport_enrollments set status='CANCELLED',updated_at=now(),updated_by=auth.uid() where payment_batch_id=p_batch and status='SUSPENDED';
   insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('student_payment_batches',p_batch::text,'REJECT',jsonb_build_object('status','REJECTED'),auth.uid(),jsonb_build_object('reason',btrim(p_reason)));return;
 end if;
 if upper(p_action)<>'APPROVE' then raise exception 'Unsupported action';end if;
 perform private.assert_open_accounting_period(b.transaction_date);
 for l in select * from public.student_payment_lines where batch_id=p_batch order by created_at,id for update loop
   v_legacy_no:=v_legacy_no+1;
   if l.uniform_item_id is not null then update public.uniform_items set stock_quantity=stock_quantity-coalesce(l.quantity,0) where id=l.uniform_item_id and stock_quantity>=coalesce(l.quantity,0);if not found then raise exception 'Uniform stock changed; entire approval rolled back';end if;end if;
   if l.book_item_id is not null then update public.book_items set stock_quantity=stock_quantity-coalesce(l.quantity,0) where id=l.book_item_id and stock_quantity>=coalesce(l.quantity,0);if not found then raise exception 'Book stock changed; entire approval rolled back';end if;end if;
   select case when count(*)=1 then case max(method) when 'CASH' then 'CASH'::public.payment_method when 'QNB' then 'QNB'::public.payment_method when 'VISA_POS' then 'VISA_POS'::public.payment_method else 'OTHER'::public.payment_method end else 'OTHER'::public.payment_method end into v_method from public.student_payment_tenders where batch_id=p_batch;
   insert into public.student_payments(account_id,transaction_date,amount_piasters,payment_method,receipt_number,notes,status,payment_category,category_label,created_by,updated_by,submitted_at,submitted_by,approved_at,approved_by,division_code,cost_center_id,payment_batch_id,payment_line_id)
   select b.account_id,b.transaction_date,l.paid_now_piasters,v_method,b.receipt_number||'-'||lpad(v_legacy_no::text,2,'0'),b.notes,'DRAFT',case when l.category in('TUITION','APPLICATION','BOOKS','ACTIVITY','TRANSPORT') then l.category else 'OTHER' end,l.description,b.created_by,auth.uid(),b.submitted_at,b.submitted_by,now(),auth.uid(),a.division_code,coalesce(l.cost_center_id,a.cost_center_id),b.id,l.id from public.student_accounts a where a.id=b.account_id returning id into v_pay;
   perform set_config('bradford.workflow','1',true);update public.student_payments set status='POSTED' where id=v_pay;
   if l.charge_id is not null then
     insert into public.student_payment_allocations(payment_id,charge_id,amount_piasters,created_by) values(v_pay,l.charge_id,l.paid_now_piasters,auth.uid());
     update public.student_charges c set status=case when (select coalesce(sum(a.amount_piasters),0) from public.student_payment_allocations a where a.charge_id=c.id and a.active)>=c.amount_piasters then 'PAID' else 'OPEN' end,updated_at=now(),updated_by=auth.uid() where c.id=l.charge_id;
   end if;
   if l.transport_enrollment_id is not null then update public.transport_enrollments set status='ACTIVE',updated_at=now(),updated_by=auth.uid() where id=l.transport_enrollment_id and payment_batch_id=p_batch and status='SUSPENDED';end if;
   update public.student_payment_lines set legacy_payment_id=v_pay where id=l.id;
 end loop;
 insert into public.journal_entries(transaction_date,description,source_module,source_id,status,created_by) values(b.transaction_date,'Unified student receipt '||b.receipt_number,'student_payment_batches',b.id,'DRAFT',auth.uid()) returning id into v_je;
 for t in select * from public.student_payment_tenders where batch_id=p_batch loop
   v_no:=v_no+1;select case when t.method='CASH' then coalesce((select gl_account_code from public.cashboxes where id=t.cashbox_id),'1100') else coalesce((select gl_account_code from public.bank_accounts where id=t.bank_account_id),'1200') end into v_asset;
   insert into public.journal_lines(entry_id,line_no,account_code,debit_piasters,credit_piasters,description) values(v_je,v_no,v_asset,t.amount_piasters,0,'Receipt '||t.method);
   if t.method='CASH' then insert into public.treasury_transactions(voucher_number,transaction_date,direction,amount_piasters,payment_method,counterparty,category,description,student_id,status,approved_by,approved_at,created_by,updated_by,cashbox_id,payment_batch_id) values(b.receipt_number,b.transaction_date,'RECEIPT',t.amount_piasters,'CASH','Student receipt','STUDENT_PAYMENT','Unified receipt '||b.receipt_number,b.student_id,'POSTED',auth.uid(),now(),b.created_by,auth.uid(),t.cashbox_id,b.id);
   elsif t.bank_account_id is not null then insert into public.bank_transactions(bank_account_id,transaction_date,value_date,debit_piasters,credit_piasters,description,bank_reference,scope,reconciliation_status,created_by,payment_batch_id) values(t.bank_account_id,b.transaction_date,b.transaction_date,0,t.amount_piasters,'Unified student receipt '||b.receipt_number,t.reference,'SCHOOL','BOOKS_ONLY',auth.uid(),b.id);end if;
 end loop;
 insert into public.journal_lines(entry_id,line_no,account_code,debit_piasters,credit_piasters,description) values(v_je,v_no+1,v_receivable,0,b.total_piasters,'Student receivable settlement');
 perform set_config('bradford.workflow','1',true);update public.journal_entries set status='POSTED',posted_at=now(),posted_by=auth.uid() where id=v_je;
 update public.student_stock_reservations set status='ISSUED',updated_at=now() where batch_id=p_batch and status='RESERVED';
 update public.student_payment_batches set status='POSTED',approved_at=now(),approved_by=auth.uid(),updated_at=now(),updated_by=auth.uid() where id=p_batch;update public.student_payment_lines set status='POSTED' where batch_id=p_batch;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('student_payment_batches',p_batch::text,'APPROVE_POST',jsonb_build_object('status','POSTED','journal_entry_id',v_je),auth.uid(),jsonb_build_object('all_lines_posted',true));
end$$;
revoke all on function public.review_student_payment_batch(uuid,text,text) from public,anon;
grant execute on function public.review_student_payment_batch(uuid,text,text) to authenticated;
commit;
