create or replace function public.ig_cost_center_id() returns uuid
language sql stable security definer set search_path='public','pg_temp' as $$
  select id from public.cost_centers where upper(code)='IG' and active limit 1
$$;

create or replace function private.force_ig_scope() returns trigger
language plpgsql security definer set search_path='public','private','pg_temp' as $$
begin
  if public.current_finance_role()='IG_ACCOUNTANT' then
    if tg_table_name in ('student_accounts','student_payments') then
      new.division_code := 'IG';
    end if;
    new.cost_center_id := public.ig_cost_center_id();
  end if;
  return new;
end $$;

create trigger student_accounts_force_ig before insert or update on public.student_accounts
for each row execute function private.force_ig_scope();
create trigger student_payments_force_ig before insert or update on public.student_payments
for each row execute function private.force_ig_scope();
create trigger student_charges_force_ig before insert or update on public.student_charges
for each row execute function private.force_ig_scope();
create trigger expenses_force_ig before insert or update on public.expenses
for each row execute function private.force_ig_scope();

create policy students_ig_read on public.students for select to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and exists(
  select 1 from public.student_accounts a where a.student_id=students.id and upper(a.division_code)='IG'
));
create policy student_accounts_ig_read on public.student_accounts for select to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and upper(division_code)='IG');
create policy student_accounts_ig_insert on public.student_accounts for insert to authenticated
with check (public.current_finance_role()='IG_ACCOUNTANT' and upper(division_code)='IG' and cost_center_id=public.ig_cost_center_id());
create policy student_accounts_ig_update on public.student_accounts for update to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and upper(division_code)='IG')
with check (upper(division_code)='IG' and cost_center_id=public.ig_cost_center_id());
create policy student_payments_ig_read on public.student_payments for select to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and upper(division_code)='IG');
create policy student_payments_ig_insert on public.student_payments for insert to authenticated
with check (public.current_finance_role()='IG_ACCOUNTANT' and upper(division_code)='IG' and cost_center_id=public.ig_cost_center_id());
create policy student_payments_ig_update_draft on public.student_payments for update to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and upper(division_code)='IG' and status in ('DRAFT','SUBMITTED'))
with check (upper(division_code)='IG' and cost_center_id=public.ig_cost_center_id() and status in ('DRAFT','SUBMITTED'));
create policy student_charges_ig_read on public.student_charges for select to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and cost_center_id=public.ig_cost_center_id());
create policy student_charges_ig_write on public.student_charges for all to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and cost_center_id=public.ig_cost_center_id() and posting_status in ('DRAFT','SUBMITTED'))
with check (cost_center_id=public.ig_cost_center_id() and posting_status in ('DRAFT','SUBMITTED'));
create policy expenses_ig_read on public.expenses for select to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and cost_center_id=public.ig_cost_center_id());
create policy expenses_ig_insert on public.expenses for insert to authenticated
with check (public.current_finance_role()='IG_ACCOUNTANT' and cost_center_id=public.ig_cost_center_id() and status='DRAFT');
create policy expenses_ig_update_draft on public.expenses for update to authenticated
using (public.current_finance_role()='IG_ACCOUNTANT' and cost_center_id=public.ig_cost_center_id() and status in ('DRAFT','SUBMITTED'))
with check (cost_center_id=public.ig_cost_center_id() and status in ('DRAFT','SUBMITTED'));

revoke all on function public.ig_cost_center_id() from public,anon;
grant execute on function public.ig_cost_center_id() to authenticated;
