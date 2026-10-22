-- Dr. Amany receives complete read-only financial visibility while her
-- existing approval RPCs remain the only write path granted to this role.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'student_accounts','treasury_transactions','bank_accounts','bank_transactions',
    'bank_reconciliations','bank_statement_snapshots','bank_statement_uploads',
    'fixed_assets','chart_of_accounts','journal_entries','journal_lines',
    'accounting_periods','partner_settings','audit_events','vendors','finance_documents',
    'transport_routes','transport_enrollments','transport_vehicles','transport_staff',
    'uniform_items','uniform_purchase_invoices','uniform_purchase_lines',
    'uniform_sales','uniform_sale_lines'
  ] loop
    execute format('grant select on public.%I to authenticated', v_table);
    execute format('drop policy if exists dr_amany_full_read on public.%I', v_table);
    execute format(
      'create policy dr_amany_full_read on public.%I for select to authenticated using (public.current_finance_role() = ''DR_AMANY_APPROVER''::public.finance_role)',
      v_table
    );
  end loop;
end
$$;
