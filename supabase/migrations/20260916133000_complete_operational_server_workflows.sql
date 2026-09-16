-- Server-side state machines for operational records that previously had only
-- draft CRUD. Every transition is role-checked, row-locked and audited.

alter table public.goods_receipts drop constraint if exists goods_receipts_status_check;
alter table public.goods_receipts add constraint goods_receipts_status_check
 check(status in('DRAFT','SUBMITTED','APPROVED','POSTED','VOID')) not valid;
alter table public.goods_receipts validate constraint goods_receipts_status_check;

create or replace function public.procurement_rfq_action(p_id uuid,p_action text,p_reason text default null) returns text
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.procurement_rfqs%rowtype; v_role text:=public.current_finance_role()::text; v_next text;
begin
 select * into r from public.procurement_rfqs where id=p_id for update;
 if not found then raise exception 'RFQ not found'; end if;
 if p_action='ISSUE' and r.status='DRAFT' and v_role in('PROCUREMENT','OWNER','FINANCE_MANAGER') then v_next:='ISSUED';
 elsif p_action='CLOSE' and r.status='ISSUED' and v_role in('APPROVER','OWNER','FINANCE_MANAGER') then
  if not exists(select 1 from public.procurement_quote_decisions d where d.rfq_id=r.id and d.approved_at is not null) then raise exception 'Approved quote decision is required'; end if;
  v_next:='CLOSED';
 elsif p_action='CANCEL' and r.status in('DRAFT','ISSUED') and v_role in('PROCUREMENT','APPROVER','OWNER','FINANCE_MANAGER') then
  if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Cancellation reason is required'; end if;v_next:='CANCELLED';
 else raise exception 'Invalid RFQ transition or role';end if;
 update public.procurement_rfqs set status=v_next,updated_at=now(),updated_by=auth.uid() where id=r.id;
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata) values('procurement_rfqs',r.id::text,p_action,jsonb_build_object('status',r.status),jsonb_build_object('status',v_next),auth.uid(),jsonb_build_object('reason',p_reason));
 return v_next;
end$$;

create or replace function public.approve_procurement_quote_decision(p_id uuid,p_note text default null) returns void
language plpgsql security definer set search_path='public','private','pg_temp' as $$
begin
 if public.current_finance_role()::text not in('APPROVER','OWNER','FINANCE_MANAGER') then raise exception 'Not authorized';end if;
 update public.procurement_quote_decisions set approved_at=now(),approved_by=auth.uid(),decision_reason=coalesce(nullif(trim(p_note),''),decision_reason) where id=p_id and approved_at is null;
 if not found then raise exception 'Decision not found or already approved';end if;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by) values('procurement_quote_decisions',p_id::text,'APPROVE',jsonb_build_object('approved',true),auth.uid());
end$$;

create or replace function public.goods_receipt_action(p_id uuid,p_action text,p_reason text default null) returns text
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.goods_receipts%rowtype;v_role text:=public.current_finance_role()::text;v_next text;m uuid;w uuid;l record;
begin
 select * into r from public.goods_receipts where id=p_id for update;if not found then raise exception 'GRN not found';end if;
 if p_action='SUBMIT' and r.status='DRAFT' and v_role in('STOREKEEPER','PROCUREMENT','ACCOUNTANT','OWNER','FINANCE_MANAGER') then
  if not exists(select 1 from public.goods_receipt_lines where goods_receipt_id=r.id) then raise exception 'GRN has no lines';end if;v_next:='SUBMITTED';
 elsif p_action='APPROVE' and r.status='SUBMITTED' and v_role in('APPROVER','OWNER','FINANCE_MANAGER') then v_next:='APPROVED';
 elsif p_action='POST' and r.status='APPROVED' and v_role in('OWNER','FINANCE_MANAGER') then
  if exists(select 1 from public.goods_receipt_lines where goods_receipt_id=r.id and (inventory_item_id is null or warehouse_id is null)) then raise exception 'Every GRN line requires item and warehouse before posting';end if;
  for w in select distinct warehouse_id from public.goods_receipt_lines where goods_receipt_id=r.id loop
   insert into public.inventory_movements(movement_date,movement_type,to_warehouse_id,status,source_table,source_id,idempotency_key,reason,submitted_at,submitted_by,created_by,updated_by)
   values(r.receipt_date,'RECEIPT',w,'SUBMITTED','goods_receipts',r.id,'GRN:'||r.id||':'||w,'GRN '||r.grn_number,now(),auth.uid(),auth.uid(),auth.uid()) returning id into m;
   insert into public.inventory_movement_lines(movement_id,item_id,quantity,unit_cost_piasters,notes)
   select m,g.inventory_item_id,g.quantity_received,coalesce(p.unit_cost_piasters,0),g.notes from public.goods_receipt_lines g join public.purchase_order_lines p on p.id=g.purchase_order_line_id where g.goods_receipt_id=r.id and g.warehouse_id=w;
   perform public.post_inventory_movement(m);
  end loop;v_next:='POSTED';
 elsif p_action='VOID' and r.status in('DRAFT','SUBMITTED') and v_role in('STOREKEEPER','PROCUREMENT','OWNER','FINANCE_MANAGER') then
  if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Void reason is required';end if;v_next:='VOID';
 else raise exception 'Invalid GRN transition or role';end if;
 update public.goods_receipts set status=v_next,posted_at=case when v_next='POSTED' then now() else posted_at end,posted_by=case when v_next='POSTED' then auth.uid() else posted_by end where id=r.id;
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata) values('goods_receipts',r.id::text,p_action,jsonb_build_object('status',r.status),jsonb_build_object('status',v_next),auth.uid(),jsonb_build_object('reason',p_reason));return v_next;
end$$;

create or replace function public.inventory_count_action(p_id uuid,p_action text,p_reason text default null) returns text
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.inventory_counts%rowtype;v_role text:=public.current_finance_role()::text;v_next text;m uuid;l record;
begin
 select * into r from public.inventory_counts where id=p_id for update;if not found then raise exception 'Count not found';end if;
 if p_action='SUBMIT' and r.status='DRAFT' and v_role in('STOREKEEPER','ACCOUNTANT','OWNER','FINANCE_MANAGER') then
  if not exists(select 1 from public.inventory_count_lines where count_id=r.id) then raise exception 'Count has no lines';end if;v_next:='SUBMITTED';
 elsif p_action='APPROVE' and r.status='SUBMITTED' and v_role in('APPROVER','OWNER','FINANCE_MANAGER') then v_next:='APPROVED';
 elsif p_action='POST' and r.status='APPROVED' and v_role in('OWNER','FINANCE_MANAGER') then
  for l in select * from public.inventory_count_lines where count_id=r.id and variance<>0 loop
   insert into public.inventory_movements(movement_date,movement_type,from_warehouse_id,to_warehouse_id,status,source_table,source_id,idempotency_key,reason,submitted_at,submitted_by,created_by,updated_by)
   values(r.count_date,case when l.variance>0 then 'ADJUSTMENT_IN' else 'ADJUSTMENT_OUT' end,case when l.variance<0 then r.warehouse_id end,case when l.variance>0 then r.warehouse_id end,'SUBMITTED','inventory_counts',r.id,'COUNT:'||r.id||':'||l.id,'Count '||r.count_number,now(),auth.uid(),auth.uid(),auth.uid()) returning id into m;
   insert into public.inventory_movement_lines(movement_id,item_id,quantity,unit_cost_piasters) values(m,l.item_id,abs(l.variance),0);
   perform public.post_inventory_movement(m);
  end loop;v_next:='POSTED';
 elsif p_action='CANCEL' and r.status in('DRAFT','SUBMITTED') and v_role in('STOREKEEPER','ACCOUNTANT','OWNER','FINANCE_MANAGER') then
  if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Cancellation reason is required';end if;v_next:='CANCELLED';
 else raise exception 'Invalid count transition or role';end if;
 update public.inventory_counts set status=v_next,approved_at=case when v_next='APPROVED' then now() else approved_at end,approved_by=case when v_next='APPROVED' then auth.uid() else approved_by end where id=r.id;
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata) values('inventory_counts',r.id::text,p_action,jsonb_build_object('status',r.status),jsonb_build_object('status',v_next),auth.uid(),jsonb_build_object('reason',p_reason));return v_next;
end$$;

create or replace function public.hr_operational_action(p_table text,p_id uuid,p_action text,p_reason text default null) returns text
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare v_role text:=public.current_finance_role()::text;v_old text;v_next text;
begin
 if p_table not in('hr_leave_requests','hr_cover_assignments','hr_compensation_items') then raise exception 'Unsupported HR table';end if;
 execute format('select status from public.%I where id=$1 for update',p_table) into v_old using p_id;if v_old is null then raise exception 'HR record not found';end if;
 if p_action='SUBMIT' and v_old in('DRAFT','RETURNED_FOR_CORRECTION') and v_role in('HR_OFFICER','HR_MANAGER') then v_next:='SUBMITTED';
 elsif p_action='APPROVE' and v_old='SUBMITTED' and v_role in('HR_MANAGER') then v_next:='APPROVED';
 elsif p_action='REJECT' and v_old='SUBMITTED' and v_role='HR_MANAGER' then if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Reason is required';end if;v_next:='REJECTED';
 elsif p_action='RETURN' and v_old='SUBMITTED' and v_role='HR_MANAGER' then if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Reason is required';end if;v_next:='RETURNED_FOR_CORRECTION';
 else raise exception 'Invalid HR transition or role';end if;
 execute format('update public.%I set status=$1 where id=$2',p_table) using v_next,p_id;
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata) values(p_table,p_id::text,p_action,jsonb_build_object('status',v_old),jsonb_build_object('status',v_next),auth.uid(),jsonb_build_object('reason',p_reason));return v_next;
end$$;

create or replace function public.asset_maintenance_action(p_id uuid,p_action text,p_reason text default null) returns text
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.asset_maintenance%rowtype;v_role text:=public.current_finance_role()::text;v_next text;
begin select * into r from public.asset_maintenance where id=p_id for update;if not found then raise exception 'Maintenance not found';end if;
 if p_action='START' and r.status in('OPEN','SCHEDULED') and v_role in('ACCOUNTANT','OWNER','FINANCE_MANAGER') then v_next:='IN_PROGRESS';
 elsif p_action='COMPLETE' and r.status='IN_PROGRESS' and v_role in('OWNER','FINANCE_MANAGER') then v_next:='COMPLETED';
 elsif p_action='CANCEL' and r.status in('OPEN','SCHEDULED','IN_PROGRESS') and v_role in('ACCOUNTANT','OWNER','FINANCE_MANAGER') then if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Reason is required';end if;v_next:='CANCELLED';
 else raise exception 'Invalid maintenance transition or role';end if;
 update public.asset_maintenance set status=v_next,completed_date=case when v_next='COMPLETED' then current_date else completed_date end,updated_at=now(),updated_by=auth.uid() where id=r.id;
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata) values('asset_maintenance',r.id::text,p_action,jsonb_build_object('status',r.status),jsonb_build_object('status',v_next),auth.uid(),jsonb_build_object('reason',p_reason));return v_next;end$$;

create or replace function public.transport_trip_action(p_id uuid,p_action text,p_reason text default null) returns text
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.transport_trips%rowtype;v_role text:=public.current_finance_role()::text;v_next text;
begin select * into r from public.transport_trips where id=p_id for update;if not found then raise exception 'Trip not found';end if;
 if v_role not in('OWNER','FINANCE_MANAGER','ACCOUNTANT','ADMISSION') then raise exception 'Not authorized';end if;
 if p_action='BOARD' and r.status='PLANNED' then v_next:='BOARDING';elsif p_action='START' and r.status='BOARDING' then v_next:='IN_PROGRESS';elsif p_action='COMPLETE' and r.status='IN_PROGRESS' then v_next:='COMPLETED';elsif p_action='CANCEL' and r.status in('PLANNED','BOARDING','IN_PROGRESS') then if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Reason is required';end if;v_next:='CANCELLED';else raise exception 'Invalid trip transition';end if;
 update public.transport_trips set status=v_next,started_at=case when v_next='IN_PROGRESS' then now() else started_at end,completed_at=case when v_next='COMPLETED' then now() else completed_at end,updated_at=now(),updated_by=auth.uid() where id=r.id;
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata) values('transport_trips',r.id::text,p_action,jsonb_build_object('status',r.status),jsonb_build_object('status',v_next),auth.uid(),jsonb_build_object('reason',p_reason));return v_next;end$$;

revoke all on function public.procurement_rfq_action(uuid,text,text),public.approve_procurement_quote_decision(uuid,text),public.goods_receipt_action(uuid,text,text),public.inventory_count_action(uuid,text,text),public.hr_operational_action(text,uuid,text,text),public.asset_maintenance_action(uuid,text,text),public.transport_trip_action(uuid,text,text) from public,anon;
grant execute on function public.procurement_rfq_action(uuid,text,text),public.approve_procurement_quote_decision(uuid,text),public.goods_receipt_action(uuid,text,text),public.inventory_count_action(uuid,text,text),public.hr_operational_action(text,uuid,text,text),public.asset_maintenance_action(uuid,text,text),public.transport_trip_action(uuid,text,text) to authenticated;

