begin;

-- Tighten child-row visibility to the same account boundary as the parent receipt.
drop policy if exists cashier_lines_read on public.student_payment_lines;
create policy cashier_lines_read on public.student_payment_lines for select to authenticated
using (exists (
  select 1 from public.student_payment_batches b
  where b.id=student_payment_lines.batch_id
    and (private.can_use_student_cashier(b.account_id) or public.is_dr_amany_payment_expense_approver())
));
drop policy if exists cashier_tenders_read on public.student_payment_tenders;
create policy cashier_tenders_read on public.student_payment_tenders for select to authenticated
using (exists (
  select 1 from public.student_payment_batches b
  where b.id=student_payment_tenders.batch_id
    and (private.can_use_student_cashier(b.account_id) or public.is_dr_amany_payment_expense_approver())
));
drop policy if exists cashier_reservations_read on public.student_stock_reservations;
create policy cashier_reservations_read on public.student_stock_reservations for select to authenticated
using (exists (
  select 1 from public.student_payment_batches b
  where b.id=student_stock_reservations.batch_id
    and (private.can_use_student_cashier(b.account_id) or public.is_dr_amany_payment_expense_approver())
));

create table if not exists public.ig_exam_subjects(
 id uuid primary key default gen_random_uuid(),
 awarding_body text not null check(length(btrim(awarding_body)) between 2 and 80),
 subject_code text not null check(length(btrim(subject_code)) between 1 and 40),
 subject_name text not null check(length(btrim(subject_name)) between 2 and 160),
 level text not null check(level in('OL','AS','A2','FULL_A_LEVEL')),
 active boolean not null default true,
 created_at timestamptz not null default now(),created_by uuid not null references auth.users(id),
 unique(awarding_body,subject_code,level)
);
create table if not exists public.ig_exam_entries(
 id uuid primary key default gen_random_uuid(),account_id uuid not null references public.student_accounts(id),
 subject_id uuid not null references public.ig_exam_subjects(id),session_code text not null,
 entry_type text not null check(entry_type in('FIRST_ENTRY','RETAKE','REMARK','LATE_ENTRY')),
 fee_piasters bigint not null check(fee_piasters>0),status text not null default 'DRAFT'
   check(status in('DRAFT','SUBMITTED','POSTED','REJECTED','REVERSED')),
 submitted_at timestamptz,submitted_by uuid references auth.users(id),approved_at timestamptz,
 approved_by uuid references auth.users(id),rejection_reason text,
 created_at timestamptz not null default now(),created_by uuid not null references auth.users(id),
 updated_at timestamptz not null default now(),updated_by uuid not null references auth.users(id),
 unique(account_id,subject_id,session_code,entry_type)
);
alter table public.student_payment_lines add column if not exists ig_exam_entry_id uuid references public.ig_exam_entries(id);
create index if not exists ig_exam_entries_account_idx on public.ig_exam_entries(account_id,session_code,status);
create index if not exists payment_lines_ig_entry_idx on public.student_payment_lines(ig_exam_entry_id) where ig_exam_entry_id is not null;

alter table public.ig_exam_subjects enable row level security;
alter table public.ig_exam_entries enable row level security;
revoke all on public.ig_exam_subjects,public.ig_exam_entries from anon,authenticated;
grant select on public.ig_exam_subjects,public.ig_exam_entries to authenticated;
create policy ig_subjects_read on public.ig_exam_subjects for select to authenticated using(true);
create policy ig_entries_read on public.ig_exam_entries for select to authenticated
using(private.can_use_student_cashier(account_id) or public.is_dr_amany_payment_expense_approver());

create or replace function public.create_ig_exam_entry(
 p_account uuid,p_awarding_body text,p_subject_code text,p_subject_name text,p_level text,
 p_session_code text,p_entry_type text,p_fee_piasters bigint
) returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare sid uuid;eid uuid;
begin
 if auth.uid() is null or not private.can_use_student_cashier(p_account) then raise exception 'Not authorized for this student';end if;
 if public.current_finance_role() not in('OWNER','FINANCE_MANAGER','IG_ACCOUNTANT') then raise exception 'IG fee-entry permission required';end if;
 if not exists(select 1 from public.student_accounts where id=p_account and upper(coalesce(division_code,''))='IG') then raise exception 'IG student account required';end if;
 if upper(p_level) not in('OL','AS','A2','FULL_A_LEVEL') or upper(p_entry_type) not in('FIRST_ENTRY','RETAKE','REMARK','LATE_ENTRY') or p_fee_piasters<=0 then raise exception 'Invalid IG entry';end if;
 select id into sid from public.ig_exam_subjects where upper(awarding_body)=upper(btrim(p_awarding_body)) and upper(subject_code)=upper(btrim(p_subject_code)) and level=upper(p_level);
 if sid is null then insert into public.ig_exam_subjects(awarding_body,subject_code,subject_name,level,created_by) values(btrim(p_awarding_body),upper(btrim(p_subject_code)),btrim(p_subject_name),upper(p_level),auth.uid()) returning id into sid;end if;
 insert into public.ig_exam_entries(account_id,subject_id,session_code,entry_type,fee_piasters,created_by,updated_by)
 values(p_account,sid,upper(btrim(p_session_code)),upper(p_entry_type),p_fee_piasters,auth.uid(),auth.uid()) returning id into eid;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by) values('ig_exam_entries',eid::text,'CREATE_DRAFT',jsonb_build_object('fee_piasters',p_fee_piasters),auth.uid());
 return eid;
end$$;

create or replace function public.submit_ig_exam_entry(p_entry uuid) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.ig_exam_entries%rowtype;begin
 select * into r from public.ig_exam_entries where id=p_entry for update;
 if not found or r.status<>'DRAFT' or not private.can_use_student_cashier(r.account_id) then raise exception 'Draft not found or not authorized';end if;
 update public.ig_exam_entries set status='SUBMITTED',submitted_at=now(),submitted_by=auth.uid(),updated_at=now(),updated_by=auth.uid() where id=p_entry;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by) values('ig_exam_entries',p_entry::text,'SUBMIT',jsonb_build_object('status','SUBMITTED'),auth.uid());
end$$;

create or replace function public.review_ig_exam_entry(p_entry uuid,p_action text,p_reason text default null) returns void language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare r public.ig_exam_entries%rowtype;s text;begin
 if auth.uid() is null or not public.is_dr_amany_payment_expense_approver() then raise exception 'Only Dr. Amany Hussein can approve or reject';end if;
 select * into r from public.ig_exam_entries where id=p_entry for update;if not found or r.status<>'SUBMITTED' then raise exception 'Only submitted entries can be reviewed';end if;
 if upper(p_action)='APPROVE' then s:='POSTED';elsif upper(p_action)='REJECT' and length(btrim(coalesce(p_reason,'')))>=3 then s:='REJECTED';else raise exception 'Valid action/reason required';end if;
 update public.ig_exam_entries set status=s,approved_at=case when s='POSTED' then now() end,approved_by=case when s='POSTED' then auth.uid() end,rejection_reason=case when s='REJECTED' then btrim(p_reason) end,updated_at=now(),updated_by=auth.uid() where id=p_entry;
 insert into public.audit_events(table_name,record_id,action,new_data,changed_by,metadata) values('ig_exam_entries',p_entry::text,case when s='POSTED' then 'APPROVE_POST' else 'REJECT' end,jsonb_build_object('status',s),auth.uid(),jsonb_build_object('reason',p_reason));
end$$;

create or replace function public.create_ig_exam_payment_batch(
 p_account_id uuid,p_transaction_date date,p_idempotency_key text,p_lines jsonb,p_tenders jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path='public','private','pg_temp' as $$
declare b uuid;x jsonb;clean jsonb:='[]'::jsonb;entry public.ig_exam_entries%rowtype;paid bigint;
begin
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one IG subject is required';end if;
 if jsonb_array_length(p_lines)<>(select count(distinct x->>'ig_exam_entry_id') from jsonb_array_elements(p_lines)x) then raise exception 'Duplicate IG subject line';end if;
 for x in select * from jsonb_array_elements(p_lines) loop
  select * into entry from public.ig_exam_entries where id=(x->>'ig_exam_entry_id')::uuid and account_id=p_account_id and status='POSTED';
  if not found then raise exception 'Approved IG entry not found';end if;
  paid:=(x->>'paid_now_piasters')::bigint;
  if paid<=0 or paid>entry.fee_piasters-coalesce((select sum(l.paid_now_piasters) from public.student_payment_lines l where l.ig_exam_entry_id=entry.id and l.status='POSTED'),0) then raise exception 'IG payment exceeds outstanding fee';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('category','EXAMS','description',x->>'description','due_piasters',entry.fee_piasters,'paid_now_piasters',paid,'cost_center_id',public.ig_cost_center_id()));
 end loop;
 b:=public.create_student_payment_batch(p_account_id,p_transaction_date,p_idempotency_key,clean,p_tenders,p_notes);
 for x in select * from jsonb_array_elements(p_lines) loop
  update public.student_payment_lines set ig_exam_entry_id=(x->>'ig_exam_entry_id')::uuid
   where id=(select l.id from public.student_payment_lines l where l.batch_id=b and l.ig_exam_entry_id is null
    and l.description=x->>'description' and l.paid_now_piasters=(x->>'paid_now_piasters')::bigint limit 1);
  if not found then raise exception 'Unable to link IG subject line';end if;
 end loop;
 return b;
end$$;

create or replace view public.v_ig_exam_entry_balances with (security_invoker=true) as
select e.id,e.account_id,e.session_code,e.entry_type,e.fee_piasters,e.status,e.created_at,
 s.awarding_body,s.subject_code,s.subject_name,s.level,
 coalesce(sum(l.paid_now_piasters) filter(where l.status='POSTED'),0)::bigint paid_piasters,
 greatest(e.fee_piasters-coalesce(sum(l.paid_now_piasters) filter(where l.status='POSTED'),0),0)::bigint remaining_piasters
from public.ig_exam_entries e join public.ig_exam_subjects s on s.id=e.subject_id
left join public.student_payment_lines l on l.ig_exam_entry_id=e.id
group by e.id,s.id;

revoke all on function public.create_ig_exam_entry(uuid,text,text,text,text,text,text,bigint),public.submit_ig_exam_entry(uuid),public.review_ig_exam_entry(uuid,text,text),public.create_ig_exam_payment_batch(uuid,date,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.create_ig_exam_entry(uuid,text,text,text,text,text,text,bigint),public.submit_ig_exam_entry(uuid),public.review_ig_exam_entry(uuid,text,text),public.create_ig_exam_payment_batch(uuid,date,text,jsonb,jsonb,text) to authenticated;
grant select on public.v_ig_exam_entry_balances to authenticated;
comment on table public.ig_exam_entries is 'IG examination fee obligations, distinct from school tuition. Only POSTED payment lines reduce their balance.';
commit;
