create or replace function private.can_edit_inventory_count(p_count uuid) returns boolean
language sql stable security definer set search_path='public','private','pg_temp' as $$
 select exists(select 1 from public.inventory_counts c where c.id=p_count and c.status='DRAFT')
   and public.current_finance_role()::text in ('STOREKEEPER','OWNER','FINANCE_MANAGER','ACCOUNTANT')
$$;
revoke all on function private.can_edit_inventory_count(uuid) from public,anon,authenticated;
grant execute on function private.can_edit_inventory_count(uuid) to authenticated;

drop policy if exists storekeeper_inventory_count_lines_draft on public.inventory_count_lines;
create policy storekeeper_inventory_count_lines_draft on public.inventory_count_lines
for all to authenticated
using (private.can_edit_inventory_count(count_id))
with check (private.can_edit_inventory_count(count_id));

