alter table public.operation_attachments
 add column if not exists organization_id uuid references public.erp_organizations(id) default public.default_organization_id();
update public.operation_attachments set organization_id=public.default_organization_id() where organization_id is null;
alter table public.operation_attachments alter column organization_id set not null;

create or replace function private.can_read_operation_attachment(p_source_table text,p_organization uuid) returns boolean
language sql stable security definer set search_path='public','private','pg_temp' as $$
 select public.can_access_organization(p_organization) and case
  when public.current_finance_role()::text in ('OWNER','CEO','AUDITOR') then true
  when public.current_finance_role()::text in ('HR_MANAGER','HR_OFFICER','PAYROLL_CASHIER') then p_source_table like 'hr\_%' escape '\' or p_source_table in ('payroll_runs','payroll_payments')
  when public.current_finance_role()::text='CASHIER' then p_source_table in ('students','student_accounts','student_payment_batches')
  when public.current_finance_role()::text='STOREKEEPER' then p_source_table like 'inventory\_%' escape '\'
  when public.current_finance_role()::text='PROCUREMENT' then p_source_table like 'purchase\_%' escape '\' or p_source_table like 'vendor\_%' escape '\' or p_source_table in ('vendors','goods_receipts')
  when public.current_finance_role()::text in ('TREASURY','TREASURY_MANAGER') then p_source_table in ('treasury_transactions','cheques','bank_transactions')
  when public.current_finance_role()::text in ('FINANCE_MANAGER','ACCOUNTANT') then p_source_table not like 'hr\_%' escape '\'
  when public.current_finance_role()::text='APPROVER' then p_source_table in ('approval_requests','approval_actions')
  else false end
$$;
revoke all on function private.can_read_operation_attachment(text,uuid) from public,anon,authenticated;

drop policy if exists operation_attachments_read on public.operation_attachments;
create policy operation_attachments_read on public.operation_attachments for select to authenticated
using(private.can_read_operation_attachment(source_table,organization_id));

drop policy if exists operation_attachments_insert on public.operation_attachments;
create policy operation_attachments_insert on public.operation_attachments for insert to authenticated
with check(uploaded_by=auth.uid() and public.can_access_organization(organization_id) and public.current_finance_role()::text not in ('READ_ONLY','AUDITOR','DR_AMANY_APPROVER'));

drop policy if exists erp_private_documents_read on storage.objects;
create policy erp_private_documents_read on storage.objects for select to authenticated
using(bucket_id='erp-private-documents' and exists(select 1 from public.operation_attachments a where a.bucket_id=bucket_id and a.object_path=name and private.can_read_operation_attachment(a.source_table,a.organization_id)));

create index if not exists operation_attachments_org_idx on public.operation_attachments(organization_id,source_table,source_id);

