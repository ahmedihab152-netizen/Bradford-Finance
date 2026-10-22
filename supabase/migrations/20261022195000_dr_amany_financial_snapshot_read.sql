grant select on public.finance_settings to authenticated;

drop policy if exists dr_amany_snapshot_read on public.finance_settings;
create policy dr_amany_snapshot_read
on public.finance_settings
for select
to authenticated
using (
  public.current_finance_role() = 'DR_AMANY_APPROVER'::public.finance_role
);
