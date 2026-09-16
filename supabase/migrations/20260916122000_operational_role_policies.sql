create or replace function private.can_use_student_cashier(p_account uuid) returns boolean
language sql stable security definer set search_path='public','private','pg_temp' as $$
 select case
  when public.current_finance_role()::text='IG_ACCOUNTANT' then exists(select 1 from public.student_accounts a where a.id=p_account and upper(coalesce(a.division_code,''))='IG')
  else public.current_finance_role()::text in ('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','TREASURY','CASHIER')
 end
$$;
revoke all on function private.can_use_student_cashier(uuid) from public,anon,authenticated;

create policy students_cashier_read on public.students for select to authenticated using(public.current_finance_role()::text='CASHIER');
create policy accounts_cashier_read on public.student_accounts for select to authenticated using(public.current_finance_role()::text='CASHIER');
create policy bank_accounts_cashier_read on public.bank_accounts for select to authenticated using(public.current_finance_role()::text='CASHIER');

create policy treasury_manager_read on public.treasury_transactions for select to authenticated using(public.current_finance_role()::text='TREASURY_MANAGER');
create policy treasury_manager_insert on public.treasury_transactions for insert to authenticated with check(public.current_finance_role()::text='TREASURY_MANAGER' and status='DRAFT');
create policy cheques_treasury_manager_read on public.cheques for select to authenticated using(public.current_finance_role()::text='TREASURY_MANAGER');
create policy cheques_treasury_manager_write on public.cheques for all to authenticated using(public.current_finance_role()::text='TREASURY_MANAGER' and status='DRAFT') with check(public.current_finance_role()::text='TREASURY_MANAGER' and status='DRAFT');

create policy inventory_storekeeper_items_read on public.inventory_items for select to authenticated using(public.current_finance_role()::text='STOREKEEPER');
create policy inventory_storekeeper_warehouses_read on public.inventory_warehouses for select to authenticated using(public.current_finance_role()::text='STOREKEEPER');
create policy inventory_storekeeper_balances_read on public.inventory_balances for select to authenticated using(public.current_finance_role()::text='STOREKEEPER');
create policy inventory_storekeeper_movements_read on public.inventory_movements for select to authenticated using(public.current_finance_role()::text='STOREKEEPER');
create policy inventory_storekeeper_lines_read on public.inventory_movement_lines for select to authenticated using(public.current_finance_role()::text='STOREKEEPER');

create policy procurement_specialist_pr_read on public.purchase_requisitions for select to authenticated using(public.current_finance_role()::text='PROCUREMENT');
create policy procurement_specialist_quotes_read on public.vendor_quotations for select to authenticated using(public.current_finance_role()::text='PROCUREMENT');
create policy procurement_specialist_vendors_read on public.vendors for select to authenticated using(public.current_finance_role()::text='PROCUREMENT');
create policy procurement_specialist_quotes_write on public.vendor_quotations for all to authenticated using(public.current_finance_role()::text='PROCUREMENT' and status='DRAFT') with check(public.current_finance_role()::text='PROCUREMENT' and status='DRAFT');
create policy procurement_specialist_vendors_write on public.vendors for all to authenticated using(public.current_finance_role()::text='PROCUREMENT') with check(public.current_finance_role()::text='PROCUREMENT');

create policy designated_approver_requests_read on public.approval_requests for select to authenticated using(public.current_finance_role()::text='APPROVER');
create policy designated_approver_actions_read on public.approval_actions for select to authenticated using(public.current_finance_role()::text='APPROVER');

