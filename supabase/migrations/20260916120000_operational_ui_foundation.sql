-- Bradford ERP operational UI foundation.
-- Additive only: private attachments plus idempotent draft creation RPCs.

create table if not exists public.operation_attachments (
  id uuid primary key default gen_random_uuid(),
  source_table text not null check (source_table ~ '^[a-z_]+$'),
  source_id uuid not null,
  document_type text not null check (length(btrim(document_type)) between 2 and 80),
  description text,
  document_date date,
  bucket_id text not null default 'erp-private-documents',
  object_path text not null,
  original_filename text not null,
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  size_bytes bigint not null check (size_bytes between 1 and 10485760),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','CORRECTION')),
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  uploaded_at timestamptz not null default now(),
  unique(source_table,source_id,sha256)
);

alter table public.operation_attachments enable row level security;
revoke all on public.operation_attachments from anon;
grant select,insert on public.operation_attachments to authenticated;

drop policy if exists operation_attachments_read on public.operation_attachments;
create policy operation_attachments_read on public.operation_attachments for select to authenticated
using (public.current_finance_role()::text in ('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','TREASURY','TREASURY_MANAGER','CASHIER','HR_MANAGER','HR_OFFICER','STOREKEEPER','PROCUREMENT','APPROVER','AUDITOR','DR_AMANY_APPROVER'));

drop policy if exists operation_attachments_insert on public.operation_attachments;
create policy operation_attachments_insert on public.operation_attachments for insert to authenticated
with check (uploaded_by=auth.uid() and public.current_finance_role()::text not in ('READ_ONLY','AUDITOR'));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('erp-private-documents','erp-private-documents',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists erp_private_documents_read on storage.objects;
create policy erp_private_documents_read on storage.objects for select to authenticated
using (bucket_id='erp-private-documents' and public.current_finance_role()::text not in ('READ_ONLY'));

drop policy if exists erp_private_documents_insert on storage.objects;
create policy erp_private_documents_insert on storage.objects for insert to authenticated
with check (bucket_id='erp-private-documents' and (storage.foldername(name))[1]=auth.uid()::text and public.current_finance_role()::text not in ('READ_ONLY','AUDITOR'));

create or replace function public.create_purchase_requisition_draft(
  p_department text,p_purpose text,p_estimated_total_piasters bigint,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare v_id uuid; v_role text:=public.current_finance_role();
begin
  if v_role not in ('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','PROCUREMENT') then raise exception 'Not authorized'; end if;
  if length(btrim(p_purpose))<3 or p_estimated_total_piasters<0 then raise exception 'Invalid requisition'; end if;
  perform pg_advisory_xact_lock(hashtextextended('pr:'||auth.uid()::text||':'||p_idempotency_key,0));
  select id into v_id from public.purchase_requisitions where review_note='IDEMPOTENCY:'||p_idempotency_key and requested_by=auth.uid();
  if v_id is not null then return v_id; end if;
  insert into public.purchase_requisitions(department,purpose,estimated_total_piasters,status,requested_by,review_note)
  values(nullif(btrim(p_department),''),btrim(p_purpose),p_estimated_total_piasters,'DRAFT',auth.uid(),'IDEMPOTENCY:'||p_idempotency_key) returning id into v_id;
  return v_id;
end$$;

create or replace function public.create_inventory_movement_draft(
  p_movement_type text,p_from_warehouse uuid,p_to_warehouse uuid,p_item uuid,p_quantity numeric,p_unit_cost_piasters bigint,p_reason text,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare v_id uuid; v_role text:=public.current_finance_role();
begin
  if v_role not in ('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','STOREKEEPER') then raise exception 'Not authorized'; end if;
  if p_movement_type not in ('RECEIPT','ISSUE','RETURN_IN','RETURN_OUT','TRANSFER','ADJUSTMENT_IN','ADJUSTMENT_OUT','DAMAGE','WASTE','COUNT') or p_quantity<=0 then raise exception 'Invalid movement'; end if;
  if p_movement_type='TRANSFER' and (p_from_warehouse is null or p_to_warehouse is null or p_from_warehouse=p_to_warehouse) then raise exception 'Invalid transfer warehouses'; end if;
  if p_movement_type in ('ISSUE','RETURN_OUT','ADJUSTMENT_OUT','DAMAGE','WASTE') and p_from_warehouse is null then raise exception 'Source warehouse required'; end if;
  if p_movement_type in ('RECEIPT','RETURN_IN','ADJUSTMENT_IN','COUNT') and p_to_warehouse is null then raise exception 'Destination warehouse required'; end if;
  insert into public.inventory_movements(movement_type,from_warehouse_id,to_warehouse_id,status,idempotency_key,reason,created_by,updated_by)
  values(p_movement_type,p_from_warehouse,p_to_warehouse,'DRAFT',p_idempotency_key,nullif(btrim(p_reason),''),auth.uid(),auth.uid())
  on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into v_id;
  if not exists(select 1 from public.inventory_movement_lines where movement_id=v_id) then
    insert into public.inventory_movement_lines(movement_id,item_id,quantity,unit_cost_piasters) values(v_id,p_item,p_quantity,greatest(p_unit_cost_piasters,0));
  end if;
  return v_id;
end$$;

revoke all on function public.create_purchase_requisition_draft(text,text,bigint,text) from public,anon;
revoke all on function public.create_inventory_movement_draft(text,uuid,uuid,uuid,numeric,bigint,text,text) from public,anon;
grant execute on function public.create_purchase_requisition_draft(text,text,bigint,text) to authenticated;
grant execute on function public.create_inventory_movement_draft(text,uuid,uuid,uuid,numeric,bigint,text,text) to authenticated;

create index if not exists operation_attachments_source_idx on public.operation_attachments(source_table,source_id,uploaded_at desc);
