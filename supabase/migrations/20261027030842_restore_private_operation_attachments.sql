begin;
-- The production deployment lacked this table and private bucket. Existing
-- legacy rows, if any, must already have an organization; no backfill is made.
create table if not exists public.operation_attachments (
 id uuid primary key default gen_random_uuid(),source_table text not null check(source_table ~ '^[a-z_]+$'),source_id uuid not null,
 document_type text not null check(length(btrim(document_type)) between 2 and 80),description text,document_date date,
 bucket_id text not null default 'erp-private-documents',object_path text not null,original_filename text not null,
 mime_type text not null check(mime_type in('application/pdf','image/jpeg','image/png')),
 size_bytes bigint not null check(size_bytes between 1 and 10485760),sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 status text not null default 'ACTIVE' check(status in('ACTIVE','CORRECTION')),
 uploaded_by uuid not null default auth.uid() references auth.users(id),uploaded_at timestamptz not null default now(),
 organization_id uuid not null default public.default_organization_id() references public.erp_organizations(id),
 unique(source_table,source_id,sha256)
);
alter table public.operation_attachments add column if not exists organization_id uuid default public.default_organization_id() references public.erp_organizations(id);
alter table public.operation_attachments alter column organization_id set not null;
alter table public.operation_attachments enable row level security;
revoke all on public.operation_attachments from public,anon,authenticated;
grant select,insert on public.operation_attachments to authenticated;
create index if not exists operation_attachments_source_idx on public.operation_attachments(source_table,source_id,uploaded_at desc);
create index if not exists operation_attachments_org_idx on public.operation_attachments(organization_id,source_table,source_id);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('erp-private-documents','erp-private-documents',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Invoker rights preserve the source table's own RLS and permission checks.
-- Source tables without tenant IDs are explicitly restricted to the legacy school.
create or replace function private.can_access_operation_source(p_table text,p_id uuid,p_org uuid)
returns boolean language plpgsql stable security invoker set search_path='' as $$
declare role_name text; allowed boolean; visible boolean;
begin
 if auth.uid() is null or p_id is null or p_org is null or not public.can_access_organization(p_org) then return false;end if;
 if p_table not in('asset_disposals','asset_maintenance','asset_transfers','goods_receipts','hr_attendance','hr_compensation_items','hr_cover_assignments','hr_employee_documents','hr_leave_requests','inventory_counts','procurement_rfqs','purchase_orders','purchase_returns','transport_staff','transport_trips','transport_vehicles','vendor_bills') then return false;end if;
 role_name:=public.current_finance_role()::text;
 allowed:=case
  when role_name in('OWNER','CEO','AUDITOR') then true
  when role_name in('HR_MANAGER','HR_OFFICER','PAYROLL_CASHIER') then p_table like 'hr\_%' escape '\'
  when role_name in('FINANCE_MANAGER','ACCOUNTANT') then p_table not like 'hr\_%' escape '\'
  when role_name='STOREKEEPER' then p_table in('inventory_counts','goods_receipts')
  when role_name='PROCUREMENT' then p_table in('procurement_rfqs','purchase_orders','purchase_returns','goods_receipts','vendor_bills')
  else false end;
 if not allowed or not has_table_privilege(current_user,format('public.%I',p_table),'SELECT') then return false;end if;
 execute format('select exists(select 1 from public.%I t where t.id=$1 and coalesce(to_jsonb(t)->>''organization_id'',public.default_organization_id()::text)=$2::text)',p_table) into visible using p_id,p_org;
 return coalesce(visible,false);
end $$;
revoke all on function private.can_access_operation_source(text,uuid,uuid) from public,anon;
grant execute on function private.can_access_operation_source(text,uuid,uuid) to authenticated;
-- This helper must bypass metadata RLS solely to decide if the uploader's own
-- object is unreferenced; a hidden linked attachment must never be deleted.
create or replace function private.is_own_orphan_operation_object(p_bucket text,p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and p_bucket='erp-private-documents'
  and (storage.foldername(p_path))[1]=auth.uid()::text
  and not exists(select 1 from public.operation_attachments a where a.bucket_id=p_bucket and a.object_path=p_path)
$$;
revoke all on function private.is_own_orphan_operation_object(text,text) from public,anon;
grant execute on function private.is_own_orphan_operation_object(text,text) to authenticated;

drop policy if exists operation_attachments_read on public.operation_attachments;
create policy operation_attachments_read on public.operation_attachments for select to authenticated
using(private.can_access_operation_source(source_table,source_id,organization_id));
drop policy if exists operation_attachments_insert on public.operation_attachments;
create policy operation_attachments_insert on public.operation_attachments for insert to authenticated
with check(uploaded_by=auth.uid() and bucket_id='erp-private-documents'
 and public.current_finance_role()::text not in('READ_ONLY','AUDITOR','DR_AMANY_APPROVER')
 and split_part(object_path,'/',1)=auth.uid()::text and split_part(object_path,'/',2)=source_table and split_part(object_path,'/',3)=source_id::text
 and private.can_access_operation_source(source_table,source_id,organization_id)
 and exists(select 1 from storage.objects o where o.bucket_id=operation_attachments.bucket_id and o.name=operation_attachments.object_path));

drop policy if exists erp_private_documents_read on storage.objects;
create policy erp_private_documents_read on storage.objects for select to authenticated
using(bucket_id='erp-private-documents' and (private.is_own_orphan_operation_object(bucket_id,name) or exists(select 1 from public.operation_attachments a where a.bucket_id=objects.bucket_id and a.object_path=objects.name)));
drop policy if exists erp_private_documents_insert on storage.objects;
create policy erp_private_documents_insert on storage.objects for insert to authenticated
with check(bucket_id='erp-private-documents' and split_part(name,'/',1)=auth.uid()::text
 and public.current_finance_role()::text not in('READ_ONLY','AUDITOR','DR_AMANY_APPROVER')
 and case when split_part(name,'/',3) ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
 then private.can_access_operation_source(split_part(name,'/',2),split_part(name,'/',3)::uuid,public.default_organization_id()) else false end);
drop policy if exists erp_private_documents_delete_orphan on storage.objects;
create policy erp_private_documents_delete_orphan on storage.objects for delete to authenticated
using(private.is_own_orphan_operation_object(bucket_id,name));
commit;
