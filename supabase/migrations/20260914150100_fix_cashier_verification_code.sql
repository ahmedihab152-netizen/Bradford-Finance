begin;
create or replace function public.create_student_payment_batch(
 p_account_id uuid,p_transaction_date date,p_idempotency_key text,p_lines jsonb,p_tenders jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare v_batch uuid;v_student uuid;v_total bigint;v_tenders bigint;v_line jsonb;v_tender jsonb;v_line_id uuid;
 v_cat text;v_amount bigint;v_due bigint;v_charge uuid;v_uniform uuid;v_book uuid;v_qty int;v_existing uuid;v_transport uuid;v_route uuid;
begin
 if auth.uid() is null or not private.can_use_student_cashier(p_account_id) then raise exception 'Not authorized for this student';end if;
 if nullif(btrim(p_idempotency_key),'') is null then raise exception 'Idempotency key is required';end if;
 select id into v_existing from public.student_payment_batches where idempotency_key=p_idempotency_key;
 if v_existing is not null then return v_existing;end if;
 select student_id into v_student from public.student_accounts where id=p_account_id for share;
 if v_student is null then raise exception 'Student account not found';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one payment line is required';end if;
 select coalesce(sum((x->>'paid_now_piasters')::bigint),0) into v_total from jsonb_array_elements(p_lines)x;
 select coalesce(sum((x->>'amount_piasters')::bigint),0) into v_tenders from jsonb_array_elements(p_tenders)x;
 if v_total<=0 or v_total<>v_tenders then raise exception 'Payment methods total must equal line total';end if;
 insert into public.student_payment_batches(account_id,student_id,receipt_number,verification_code,idempotency_key,transaction_date,total_piasters,notes,created_by,updated_by)
 values(p_account_id,v_student,'BF-'||to_char(coalesce(p_transaction_date,current_date),'YYYY')||'-'||lpad(nextval('public.student_payment_batch_receipt_seq')::text,7,'0'),upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),p_idempotency_key,coalesce(p_transaction_date,current_date),v_total,nullif(btrim(p_notes),''),auth.uid(),auth.uid()) returning id into v_batch;
 for v_line in select * from jsonb_array_elements(p_lines) loop
   v_cat:=upper(v_line->>'category');v_amount:=(v_line->>'paid_now_piasters')::bigint;v_due:=coalesce((v_line->>'due_piasters')::bigint,0);
   v_charge:=nullif(v_line->>'charge_id','')::uuid;v_uniform:=nullif(v_line->>'uniform_item_id','')::uuid;v_book:=nullif(v_line->>'book_item_id','')::uuid;v_qty:=nullif(v_line->>'quantity','')::int;
   if v_cat not in('TUITION','APPLICATION','BOOKS','TRANSPORT','UNIFORM','ACTIVITY','EXAMS','OTHER') or v_amount<=0 then raise exception 'Invalid payment line';end if;
   if v_charge is not null and not exists(select 1 from public.student_charges where id=v_charge and account_id=p_account_id and posting_status='POSTED') then raise exception 'Charge does not belong to student or is not posted';end if;
   if v_due>0 and v_amount>v_due and public.current_finance_role() not in('OWNER','FINANCE_MANAGER') then raise exception 'Payment exceeds outstanding amount';end if;
   v_transport:=nullif(v_line->>'transport_enrollment_id','')::uuid;
   if v_cat='TRANSPORT' and v_transport is null then
     v_route:=nullif(v_line->>'transport_route_id','')::uuid;
     if v_route is null or nullif(btrim(v_line->>'pickup_point'),'') is null or coalesce((v_line->>'transport_fee_piasters')::bigint,0)<=0 then raise exception 'Complete transport route, pickup point and fee';end if;
     if not exists(select 1 from public.transport_routes r join public.student_accounts a on a.id=p_account_id where r.id=v_route and r.status='ACTIVE' and r.academic_year=a.academic_year) then raise exception 'Transport route is not active for this academic year';end if;
     insert into public.transport_enrollments(student_id,academic_year,route_id,vehicle_id,pickup_point,guardian_phone,fee_piasters,status,created_by,updated_by,payment_batch_id)
     select v_student,a.academic_year,v_route,nullif(v_line->>'transport_vehicle_id','')::uuid,btrim(v_line->>'pickup_point'),s.guardian_phone,(v_line->>'transport_fee_piasters')::bigint,'SUSPENDED',auth.uid(),auth.uid(),v_batch from public.student_accounts a join public.students s on s.id=v_student where a.id=p_account_id returning id into v_transport;
   end if;
   if v_cat='UNIFORM' and (v_uniform is null or coalesce(v_qty,0)<=0) then raise exception 'Uniform item and quantity are required';end if;
   if v_cat='BOOKS' and v_book is not null and coalesce(v_qty,0)<=0 then raise exception 'Book quantity is required';end if;
   insert into public.student_payment_lines(batch_id,student_id,account_id,category,description,due_piasters,paid_now_piasters,charge_id,transport_enrollment_id,uniform_item_id,uniform_size,quantity,book_item_id,book_package_id,department_id,cost_center_id)
   values(v_batch,v_student,p_account_id,v_cat,coalesce(nullif(v_line->>'description',''),v_cat),v_due,v_amount,v_charge,v_transport,v_uniform,v_line->>'uniform_size',v_qty,v_book,nullif(v_line->>'book_package_id','')::uuid,nullif(v_line->>'department_id','')::uuid,nullif(v_line->>'cost_center_id','')::uuid) returning id into v_line_id;
   if v_uniform is not null then
     perform 1 from public.uniform_items where id=v_uniform and active and stock_quantity>=v_qty for update;if not found then raise exception 'Insufficient uniform stock';end if;
     if (select stock_quantity-coalesce(sum(r.quantity) filter(where r.status='RESERVED'),0) from public.uniform_items i left join public.student_stock_reservations r on r.uniform_item_id=i.id where i.id=v_uniform group by i.stock_quantity)<v_qty then raise exception 'Uniform stock already reserved';end if;
     insert into public.student_stock_reservations(batch_id,line_id,item_type,uniform_item_id,quantity) values(v_batch,v_line_id,'UNIFORM',v_uniform,v_qty);
   elsif v_book is not null then
     perform 1 from public.book_items where id=v_book and active and stock_quantity>=v_qty for update;if not found then raise exception 'Insufficient book stock';end if;
     if (select stock_quantity-coalesce(sum(r.quantity) filter(where r.status='RESERVED'),0) from public.book_items i left join public.student_stock_reservations r on r.book_item_id=i.id where i.id=v_book group by i.stock_quantity)<v_qty then raise exception 'Book stock already reserved';end if;
     insert into public.student_stock_reservations(batch_id,line_id,item_type,book_item_id,quantity) values(v_batch,v_line_id,'BOOK',v_book,v_qty);
   end if;
 end loop;
 for v_tender in select * from jsonb_array_elements(p_tenders) loop
   if upper(v_tender->>'method')<>'CASH' and nullif(v_tender->>'bank_account_id','') is null then raise exception 'Bank account is required for non-cash payment';end if;
   insert into public.student_payment_tenders(batch_id,method,amount_piasters,reference,cashbox_id,bank_account_id)
   values(v_batch,upper(v_tender->>'method'),(v_tender->>'amount_piasters')::bigint,nullif(v_tender->>'reference',''),nullif(v_tender->>'cashbox_id','')::uuid,nullif(v_tender->>'bank_account_id','')::uuid);
 end loop;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('student_payment_batches',v_batch::text,'CREATE_DRAFT',jsonb_build_object('total_piasters',v_total),auth.uid(),jsonb_build_object('idempotency_key',p_idempotency_key));
 return v_batch;
end$$;
revoke all on function public.create_student_payment_batch(uuid,date,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.create_student_payment_batch(uuid,date,text,jsonb,jsonb,text) to authenticated;
commit;
