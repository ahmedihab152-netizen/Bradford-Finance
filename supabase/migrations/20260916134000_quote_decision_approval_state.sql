alter table public.procurement_quote_decisions add column if not exists status text;
update public.procurement_quote_decisions set status=case when approved_at is not null then 'APPROVED' else 'DRAFT' end where status is null;
alter table public.procurement_quote_decisions alter column status set default 'DRAFT';
alter table public.procurement_quote_decisions alter column status set not null;
alter table public.procurement_quote_decisions drop constraint if exists procurement_quote_decisions_status_check;
alter table public.procurement_quote_decisions add constraint procurement_quote_decisions_status_check check(status in('DRAFT','APPROVED','REJECTED'));
alter table public.procurement_quote_decisions alter column approved_by drop not null;
alter table public.procurement_quote_decisions alter column approved_at drop default;

create or replace function public.approve_procurement_quote_decision(p_id uuid,p_note text default null) returns void
language plpgsql security definer set search_path='public','private','pg_temp' as $$
begin
 if public.current_finance_role()::text not in('APPROVER','OWNER','FINANCE_MANAGER') then raise exception 'Not authorized';end if;
 update public.procurement_quote_decisions set status='APPROVED',approved_at=now(),approved_by=auth.uid(),decision_reason=coalesce(nullif(trim(p_note),''),decision_reason) where id=p_id and status='DRAFT';
 if not found then raise exception 'Decision not found or not DRAFT';end if;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by) values('procurement_quote_decisions',p_id::text,'APPROVE',jsonb_build_object('status','APPROVED'),auth.uid());
end$$;

create or replace function public.reject_procurement_quote_decision(p_id uuid,p_reason text) returns void
language plpgsql security definer set search_path='public','private','pg_temp' as $$
begin
 if public.current_finance_role()::text not in('APPROVER','OWNER','FINANCE_MANAGER') then raise exception 'Not authorized';end if;
 if coalesce(length(trim(p_reason)),0)<3 then raise exception 'Reason is required';end if;
 update public.procurement_quote_decisions set status='REJECTED',decision_reason=p_reason,approved_at=null,approved_by=null where id=p_id and status='DRAFT';
 if not found then raise exception 'Decision not found or not DRAFT';end if;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('procurement_quote_decisions',p_id::text,'REJECT',jsonb_build_object('status','REJECTED'),auth.uid(),jsonb_build_object('reason',p_reason));
end$$;

revoke all on function public.reject_procurement_quote_decision(uuid,text) from public,anon;
grant execute on function public.reject_procurement_quote_decision(uuid,text) to authenticated;

