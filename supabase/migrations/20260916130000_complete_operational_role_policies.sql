-- Additive least-privilege policies for the operational roles introduced in
-- 20260916121000. Existing finance/HR policies remain unchanged.

create policy procurement_specialist_rfqs_draft on public.procurement_rfqs
for all to authenticated
using (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT')
with check (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT');

create policy procurement_specialist_orders_draft on public.purchase_orders
for all to authenticated
using (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT' and public.can_access_organization(organization_id))
with check (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT' and public.can_access_organization(organization_id));

create policy procurement_specialist_bills_draft on public.vendor_bills
for all to authenticated
using (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT' and public.can_access_organization(organization_id))
with check (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT' and public.can_access_organization(organization_id));

create policy procurement_specialist_returns_draft on public.purchase_returns
for all to authenticated
using (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT')
with check (public.current_finance_role()::text='PROCUREMENT' and status='DRAFT');

create policy procurement_quote_decisions_create on public.procurement_quote_decisions
for insert to authenticated
with check (public.current_finance_role()::text in ('PROCUREMENT','OWNER','FINANCE_MANAGER'));

create policy procurement_quote_decisions_approve on public.procurement_quote_decisions
for update to authenticated
using (public.current_finance_role()::text in ('APPROVER','OWNER','FINANCE_MANAGER'))
with check (public.current_finance_role()::text in ('APPROVER','OWNER','FINANCE_MANAGER'));

create policy storekeeper_grn_draft on public.goods_receipts
for all to authenticated
using (public.current_finance_role()::text='STOREKEEPER' and status='DRAFT')
with check (public.current_finance_role()::text='STOREKEEPER' and status='DRAFT');

create policy storekeeper_inventory_counts_draft on public.inventory_counts
for all to authenticated
using (public.current_finance_role()::text='STOREKEEPER' and status='DRAFT')
with check (public.current_finance_role()::text='STOREKEEPER' and status='DRAFT');

create policy storekeeper_inventory_count_lines_draft on public.inventory_count_lines
for all to authenticated
using (public.current_finance_role()::text='STOREKEEPER' and exists(
 select 1 from public.inventory_counts c where c.id=count_id and c.status='DRAFT'
))
with check (public.current_finance_role()::text='STOREKEEPER' and exists(
 select 1 from public.inventory_counts c where c.id=count_id and c.status='DRAFT'
));

create policy operational_specialists_read_purchase_orders on public.purchase_orders
for select to authenticated
using (public.current_finance_role()::text in ('PROCUREMENT','STOREKEEPER','APPROVER') and public.can_access_organization(organization_id));

create policy operational_specialists_read_grn on public.goods_receipts
for select to authenticated
using (public.current_finance_role()::text in ('PROCUREMENT','STOREKEEPER','APPROVER'));

create policy operational_specialists_read_bills on public.vendor_bills
for select to authenticated
using (public.current_finance_role()::text in ('PROCUREMENT','APPROVER') and public.can_access_organization(organization_id));

create policy operational_specialists_read_rfqs on public.procurement_rfqs
for select to authenticated
using (public.current_finance_role()::text in ('PROCUREMENT','APPROVER'));

create policy operational_specialists_read_returns on public.purchase_returns
for select to authenticated
using (public.current_finance_role()::text in ('PROCUREMENT','STOREKEEPER','APPROVER'));

create policy operational_specialists_read_quote_decisions on public.procurement_quote_decisions
for select to authenticated
using (public.current_finance_role()::text in ('PROCUREMENT','APPROVER'));

