begin;
create or replace function private.hr_movement_guard() returns trigger
language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare role_now public.finance_role:=public.current_finance_role();workflow boolean:=current_setting('bradford.hr_movement_workflow',true)='1';
begin
 if tg_op='DELETE' then raise exception 'Employee movements are immutable; cancel or adjust instead';end if;
 if old.status='INCLUDED_IN_PAYROLL' then raise exception 'Movement already included in payroll; create an adjustment';end if;
 if not workflow then
  if role_now not in('HR_OFFICER','HR_MANAGER') or old.status not in('DRAFT','RETURNED_FOR_CORRECTION') then raise exception 'Only draft or returned movements can be edited directly';end if;
  if new.status is distinct from old.status or new.approved_amount_piasters is distinct from old.approved_amount_piasters or new.reviewed_at is distinct from old.reviewed_at or new.reviewed_by is distinct from old.reviewed_by then raise exception 'Use HR movement workflow for review fields';end if;
 end if;
 new.updated_at:=now();new.updated_by:=auth.uid();return new;
end$$;

create or replace function private.hr_movement_direct_audit() returns trigger language plpgsql security definer set search_path='public','private','pg_temp' as $$
begin
 if current_setting('bradford.hr_movement_workflow',true)<>'1' then perform private.hr_audit('hr_employee_movements',new.id,'UPDATE_DRAFT',to_jsonb(old),to_jsonb(new));end if;
 return new;
end$$;
drop trigger if exists hr_movement_direct_audit on public.hr_employee_movements;
create trigger hr_movement_direct_audit after update on public.hr_employee_movements for each row execute function private.hr_movement_direct_audit();
commit;
