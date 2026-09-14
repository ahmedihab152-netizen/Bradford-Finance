begin;

-- Unified student cashier. This migration creates no operational rows and changes
-- no historic balances. Official effects are created only by the approval RPC.
create sequence if not exists public.student_payment_batch_receipt_seq;

alter table public.students add column if not exists section text;
alter table public.students add column if not exists normalized_grade text;
alter table public.students add column if not exists grade_sort_order integer;
alter table public.students add column if not exists grade_review_required boolean not null default false;

create table if not exists public.grade_mapping_review_queue(
  id uuid primary key default gen_random_uuid(), student_id uuid not null unique references public.students(id),
  original_grade text, proposed_grade text, proposed_sort_order integer,
  status text not null default 'PENDING' check(status in('PENDING','APPROVED','REJECTED')),
  reviewed_at timestamptz, reviewed_by uuid references auth.users(id), review_note text,
  created_at timestamptz not null default now()
);

create table if not exists public.book_items(
  id uuid primary key default gen_random_uuid(), sku text not null unique, item_name text not null,
  grade text, division_code text check(division_code in('AMERICAN','IG')),
  selling_price_piasters bigint not null default 0 check(selling_price_piasters>=0),
  stock_quantity integer not null default 0 check(stock_quantity>=0), active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid references auth.users(id)
);
create table if not exists public.book_packages(
  id uuid primary key default gen_random_uuid(), package_code text not null unique, package_name text not null,
  grade text not null, division_code text not null check(division_code in('AMERICAN','IG')),
  active boolean not null default true, created_at timestamptz not null default now(), created_by uuid references auth.users(id)
);
create table if not exists public.book_package_lines(
  id uuid primary key default gen_random_uuid(), package_id uuid not null references public.book_packages(id),
  book_item_id uuid not null references public.book_items(id), quantity integer not null check(quantity>0),
  unique(package_id,book_item_id)
);

create table if not exists public.student_payment_batches(
  id uuid primary key default gen_random_uuid(), account_id uuid not null references public.student_accounts(id),
  student_id uuid not null references public.students(id), receipt_number text not null unique,
  verification_code text not null unique, idempotency_key text not null unique,
  transaction_date date not null default current_date,
  status text not null default 'DRAFT' check(status in('DRAFT','SUBMITTED','POSTED','REJECTED','REVERSED')),
  total_piasters bigint not null check(total_piasters>0), notes text,
  created_at timestamptz not null default now(), created_by uuid not null references auth.users(id),
  submitted_at timestamptz, submitted_by uuid references auth.users(id),
  approved_at timestamptz, approved_by uuid references auth.users(id),
  rejected_at timestamptz, rejected_by uuid references auth.users(id), rejection_reason text,
  reversed_at timestamptz, reversed_by uuid references auth.users(id), reversal_reason text,
  updated_at timestamptz not null default now(), updated_by uuid not null references auth.users(id)
);
create table if not exists public.student_payment_lines(
  id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.student_payment_batches(id),
  student_id uuid not null references public.students(id), account_id uuid not null references public.student_accounts(id),
  category text not null check(category in('TUITION','APPLICATION','BOOKS','TRANSPORT','UNIFORM','ACTIVITY','EXAMS','OTHER')),
  description text not null, due_piasters bigint not null default 0 check(due_piasters>=0),
  paid_now_piasters bigint not null check(paid_now_piasters>0), charge_id uuid references public.student_charges(id),
  transport_enrollment_id uuid references public.transport_enrollments(id),
  uniform_item_id uuid references public.uniform_items(id), uniform_size text, quantity integer check(quantity is null or quantity>0),
  book_item_id uuid references public.book_items(id), book_package_id uuid references public.book_packages(id),
  department_id uuid references public.departments(id), cost_center_id uuid references public.cost_centers(id),
  status text not null default 'DRAFT' check(status in('DRAFT','SUBMITTED','POSTED','REJECTED','REVERSED')),
  legacy_payment_id uuid references public.student_payments(id), created_at timestamptz not null default now(),
  unique(batch_id,id)
);
create table if not exists public.student_payment_tenders(
  id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.student_payment_batches(id),
  method text not null check(method in('CASH','VISA_POS','QNB','BANK_OTHER','TRANSFER')),
  amount_piasters bigint not null check(amount_piasters>0), reference text,
  cashbox_id uuid references public.cashboxes(id), bank_account_id uuid references public.bank_accounts(id),
  created_at timestamptz not null default now()
);
create table if not exists public.student_stock_reservations(
  id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.student_payment_batches(id),
  line_id uuid not null references public.student_payment_lines(id), item_type text not null check(item_type in('UNIFORM','BOOK')),
  uniform_item_id uuid references public.uniform_items(id), book_item_id uuid references public.book_items(id),
  quantity integer not null check(quantity>0), status text not null default 'RESERVED' check(status in('RESERVED','ISSUED','RELEASED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(line_id)
);

alter table public.student_payments add column if not exists payment_batch_id uuid references public.student_payment_batches(id);
alter table public.student_payments add column if not exists payment_line_id uuid references public.student_payment_lines(id);
alter table public.transport_enrollments add column if not exists payment_batch_id uuid references public.student_payment_batches(id);
alter table public.treasury_transactions add column if not exists payment_batch_id uuid references public.student_payment_batches(id);
alter table public.bank_transactions add column if not exists payment_batch_id uuid references public.student_payment_batches(id);
create unique index if not exists student_payments_payment_line_uidx on public.student_payments(payment_line_id) where payment_line_id is not null;
create index if not exists payment_batches_account_idx on public.student_payment_batches(account_id,created_at desc);
create index if not exists payment_batches_status_idx on public.student_payment_batches(status,submitted_at);
create index if not exists payment_lines_batch_idx on public.student_payment_lines(batch_id);
create index if not exists payment_lines_charge_idx on public.student_payment_lines(charge_id) where charge_id is not null;

alter table public.grade_mapping_review_queue enable row level security;
alter table public.book_items enable row level security; alter table public.book_packages enable row level security;
alter table public.book_package_lines enable row level security; alter table public.student_payment_batches enable row level security;
alter table public.student_payment_lines enable row level security; alter table public.student_payment_tenders enable row level security;
alter table public.student_stock_reservations enable row level security;
revoke all on public.grade_mapping_review_queue,public.book_items,public.book_packages,public.book_package_lines,
  public.student_payment_batches,public.student_payment_lines,public.student_payment_tenders,public.student_stock_reservations from anon,authenticated;
grant select on public.grade_mapping_review_queue,public.book_items,public.book_packages,public.book_package_lines,
  public.student_payment_batches,public.student_payment_lines,public.student_payment_tenders,public.student_stock_reservations to authenticated;

create or replace function private.can_use_student_cashier(p_account uuid) returns boolean language sql stable security definer
set search_path='public','private','pg_temp' as $$
 select case when public.current_finance_role()='IG_ACCOUNTANT' then exists(
   select 1 from public.student_accounts a where a.id=p_account and upper(coalesce(a.division_code,''))='IG'
 ) else public.current_finance_role() in ('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','TREASURY') end
$$;
revoke all on function private.can_use_student_cashier(uuid) from public,anon,authenticated;

create policy cashier_batches_read on public.student_payment_batches for select to authenticated
 using(private.can_use_student_cashier(account_id) or public.is_dr_amany_payment_expense_approver());
create policy cashier_lines_read on public.student_payment_lines for select to authenticated
 using(exists(select 1 from public.student_payment_batches b where b.id=batch_id));
create policy cashier_tenders_read on public.student_payment_tenders for select to authenticated
 using(exists(select 1 from public.student_payment_batches b where b.id=batch_id));
create policy cashier_reservations_read on public.student_stock_reservations for select to authenticated
 using(exists(select 1 from public.student_payment_batches b where b.id=batch_id));
create policy books_read on public.book_items for select to authenticated using(true);
create policy book_packages_read on public.book_packages for select to authenticated using(true);
create policy book_package_lines_read on public.book_package_lines for select to authenticated using(true);
create policy grade_review_owner_read on public.grade_mapping_review_queue for select to authenticated
 using(public.current_finance_role() in('OWNER','ADMISSION'));

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
 values(p_account_id,v_student,'BF-'||to_char(coalesce(p_transaction_date,current_date),'YYYY')||'-'||lpad(nextval('public.student_payment_batch_receipt_seq')::text,7,'0'),upper(substr(encode(gen_random_bytes(8),'hex'),1,12)),p_idempotency_key,coalesce(p_transaction_date,current_date),v_total,nullif(btrim(p_notes),''),auth.uid(),auth.uid()) returning id into v_batch;
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
     perform 1 from public.uniform_items where id=v_uniform and active and stock_quantity>=v_qty for update;
     if not found then raise exception 'Insufficient uniform stock';end if;
     if (select stock_quantity-coalesce(sum(r.quantity) filter(where r.status='RESERVED'),0) from public.uniform_items i left join public.student_stock_reservations r on r.uniform_item_id=i.id where i.id=v_uniform group by i.stock_quantity)<v_qty then raise exception 'Uniform stock already reserved';end if;
     insert into public.student_stock_reservations(batch_id,line_id,item_type,uniform_item_id,quantity) values(v_batch,v_line_id,'UNIFORM',v_uniform,v_qty);
   elsif v_book is not null then
     perform 1 from public.book_items where id=v_book and active and stock_quantity>=v_qty for update;if not found then raise exception 'Insufficient book stock';end if;
     insert into public.student_stock_reservations(batch_id,line_id,item_type,book_item_id,quantity) values(v_batch,v_line_id,'BOOK',v_book,v_qty);
   end if;
 end loop;
 for v_tender in select * from jsonb_array_elements(p_tenders) loop
   insert into public.student_payment_tenders(batch_id,method,amount_piasters,reference,cashbox_id,bank_account_id)
   values(v_batch,upper(v_tender->>'method'),(v_tender->>'amount_piasters')::bigint,nullif(v_tender->>'reference',''),nullif(v_tender->>'cashbox_id','')::uuid,nullif(v_tender->>'bank_account_id','')::uuid);
 end loop;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('student_payment_batches',v_batch::text,'CREATE_DRAFT',jsonb_build_object('total_piasters',v_total),auth.uid(),jsonb_build_object('idempotency_key',p_idempotency_key));
 return v_batch;
end$$;

create or replace function public.submit_student_payment_batch(p_batch uuid) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare b public.student_payment_batches%rowtype;begin
 if auth.uid() is null then raise exception 'Authentication required';end if;select * into b from public.student_payment_batches where id=p_batch for update;
 if not found or not private.can_use_student_cashier(b.account_id) or b.status<>'DRAFT' then raise exception 'Draft not found or not authorized';end if;
 if b.created_by<>auth.uid() and public.current_finance_role() not in('OWNER','FINANCE_MANAGER') then raise exception 'You can only submit your own draft';end if;
 update public.student_payment_batches set status='SUBMITTED',submitted_at=now(),submitted_by=auth.uid(),updated_at=now(),updated_by=auth.uid() where id=p_batch;
 update public.student_payment_lines set status='SUBMITTED' where batch_id=p_batch;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by) values('student_payment_batches',p_batch::text,'SUBMIT',jsonb_build_object('status','SUBMITTED'),auth.uid());
end$$;

create or replace function public.review_student_payment_batch(p_batch uuid,p_action text,p_reason text default null) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare b public.student_payment_batches%rowtype;l public.student_payment_lines%rowtype;t public.student_payment_tenders%rowtype;v_pay uuid;v_method public.payment_method;v_je uuid;v_no int:=0;v_asset text;v_receivable text:='1300';begin
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
   if l.uniform_item_id is not null then update public.uniform_items set stock_quantity=stock_quantity-coalesce(l.quantity,0) where id=l.uniform_item_id and stock_quantity>=coalesce(l.quantity,0);if not found then raise exception 'Uniform stock changed; entire approval rolled back';end if;end if;
   if l.book_item_id is not null then update public.book_items set stock_quantity=stock_quantity-coalesce(l.quantity,0) where id=l.book_item_id and stock_quantity>=coalesce(l.quantity,0);if not found then raise exception 'Book stock changed; entire approval rolled back';end if;end if;
   select case when count(*)=1 then case max(method) when 'CASH' then 'CASH'::public.payment_method when 'QNB' then 'QNB'::public.payment_method when 'VISA_POS' then 'VISA_POS'::public.payment_method else 'OTHER'::public.payment_method end else 'OTHER'::public.payment_method end into v_method from public.student_payment_tenders where batch_id=p_batch;
   insert into public.student_payments(account_id,transaction_date,amount_piasters,payment_method,receipt_number,notes,status,payment_category,category_label,created_by,updated_by,submitted_at,submitted_by,approved_at,approved_by,division_code,cost_center_id,payment_batch_id,payment_line_id)
   select b.account_id,b.transaction_date,l.paid_now_piasters,v_method,b.receipt_number,b.notes,'DRAFT',case when l.category in('TUITION','APPLICATION','BOOKS','ACTIVITY','TRANSPORT') then l.category else 'OTHER' end,l.description,b.created_by,auth.uid(),b.submitted_at,b.submitted_by,now(),auth.uid(),a.division_code,coalesce(l.cost_center_id,a.cost_center_id),b.id,l.id from public.student_accounts a where a.id=b.account_id returning id into v_pay;
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
   if t.method='CASH' then
     insert into public.treasury_transactions(voucher_number,transaction_date,direction,amount_piasters,payment_method,counterparty,category,description,student_id,status,approved_by,approved_at,created_by,updated_by,cashbox_id,payment_batch_id)
     values(b.receipt_number,b.transaction_date,'IN',t.amount_piasters,'CASH','Student receipt','STUDENT_PAYMENT','Unified receipt '||b.receipt_number,b.student_id,'POSTED',auth.uid(),now(),b.created_by,auth.uid(),t.cashbox_id,b.id);
   elsif t.bank_account_id is not null then
     insert into public.bank_transactions(bank_account_id,transaction_date,value_date,debit_piasters,credit_piasters,description,bank_reference,scope,reconciliation_status,created_by,payment_batch_id)
     values(t.bank_account_id,b.transaction_date,b.transaction_date,0,t.amount_piasters,'Unified student receipt '||b.receipt_number,t.reference,'SCHOOL','BOOKS_ONLY',auth.uid(),b.id);
   end if;
 end loop;
 insert into public.journal_lines(entry_id,line_no,account_code,debit_piasters,credit_piasters,description) values(v_je,v_no+1,v_receivable,0,b.total_piasters,'Student receivable settlement');
 perform set_config('bradford.workflow','1',true);update public.journal_entries set status='POSTED',posted_at=now(),posted_by=auth.uid() where id=v_je;
 update public.student_stock_reservations set status='ISSUED',updated_at=now() where batch_id=p_batch and status='RESERVED';
 update public.student_payment_batches set status='POSTED',approved_at=now(),approved_by=auth.uid(),updated_at=now(),updated_by=auth.uid() where id=p_batch;update public.student_payment_lines set status='POSTED' where batch_id=p_batch;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('student_payment_batches',p_batch::text,'APPROVE_POST',jsonb_build_object('status','POSTED','journal_entry_id',v_je),auth.uid(),jsonb_build_object('all_lines_posted',true));
end$$;

revoke all on function public.create_student_payment_batch(uuid,date,text,jsonb,jsonb,text),public.submit_student_payment_batch(uuid),public.review_student_payment_batch(uuid,text,text) from public,anon;
grant execute on function public.create_student_payment_batch(uuid,date,text,jsonb,jsonb,text),public.submit_student_payment_batch(uuid),public.review_student_payment_batch(uuid,text,text) to authenticated;

comment on table public.student_payment_batches is 'Atomic unified cashier receipt; only POSTED batches have official effects.';
comment on table public.student_stock_reservations is 'Pending uniform/book reservation; no physical stock decrement before Dr Amany approval.';
commit;
