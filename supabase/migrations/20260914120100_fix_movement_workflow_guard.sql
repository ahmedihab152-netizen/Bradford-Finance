create or replace function private.hr_movement_guard() returns trigger
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare
  role_now public.finance_role:=public.current_finance_role();
  workflow boolean:=current_setting('bradford.hr_movement_workflow',true)='1';
begin
  if tg_op='DELETE' then raise exception 'Employee movements are immutable; cancel or adjust instead';end if;
  if old.status='INCLUDED_IN_PAYROLL' then raise exception 'Movement already included in payroll; create an adjustment';end if;
  if not workflow and role_now='HR_OFFICER' and old.status not in ('DRAFT','RETURNED_FOR_CORRECTION') then
    raise exception 'HR Officer can edit drafts only';
  end if;
  if new.status is distinct from old.status and not workflow then raise exception 'Use HR movement workflow';end if;
  new.updated_at:=now();new.updated_by:=auth.uid();return new;
end$$;
