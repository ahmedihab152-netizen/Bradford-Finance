begin;

-- Canonical Grade / Program configuration. The rows are organization master
-- data, not operational or financial test data.
create table if not exists public.grade_program_config (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id),
  school_id uuid not null references public.erp_schools(id),
  grade_name text not null check (grade_name in (
    'KG1','KG2','Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6',
    'Grade 7','Grade 8','Grade 9','Grade 10','Grade 11','Grade 12'
  )),
  grade_sort_order integer not null check (grade_sort_order between 1 and 14),
  program text not null check (program in ('AMERICAN','IG')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  unique (school_id,grade_name,program),
  check (grade_name not in ('KG1','KG2') or program='AMERICAN')
);
alter table public.grade_program_config enable row level security;
revoke all on public.grade_program_config from public,anon,authenticated;
grant select,insert,update on public.grade_program_config to authenticated;

create policy grade_program_read on public.grade_program_config for select to authenticated
using (public.can_access_organization(organization_id));
create policy grade_program_owner_insert on public.grade_program_config for insert to authenticated
with check (public.current_finance_role()::text='OWNER' and public.can_access_organization(organization_id));
create policy grade_program_owner_update on public.grade_program_config for update to authenticated
using (public.current_finance_role()::text='OWNER' and public.can_access_organization(organization_id))
with check (public.current_finance_role()::text='OWNER' and public.can_access_organization(organization_id));

insert into public.grade_program_config(organization_id,school_id,grade_name,grade_sort_order,program)
select s.organization_id,s.id,g.grade_name,g.sort_order,p.program
from public.erp_schools s
cross join (values ('KG1',1),('KG2',2),('Grade 1',3),('Grade 2',4),('Grade 3',5),
 ('Grade 4',6),('Grade 5',7),('Grade 6',8),('Grade 7',9),('Grade 8',10),
 ('Grade 9',11),('Grade 10',12),('Grade 11',13),('Grade 12',14)) g(grade_name,sort_order)
cross join (values ('AMERICAN'),('IG')) p(program)
where s.school_code='MCIS' and (g.grade_name not in ('KG1','KG2') or p.program='AMERICAN')
on conflict(school_id,grade_name,program) do nothing;

create or replace function public.canonical_grade(p_grade text) returns text
language sql immutable strict set search_path='' as $$
 select case regexp_replace(upper(btrim(p_grade)),'[ ._-]+','','g')
  when 'KG1' then 'KG1' when 'KG2' then 'KG2'
  when 'GR1' then 'Grade 1' when 'GRADE1' then 'Grade 1'
  when 'GR2' then 'Grade 2' when 'GRADE2' then 'Grade 2'
  when 'GR3' then 'Grade 3' when 'GRADE3' then 'Grade 3'
  when 'GR4' then 'Grade 4' when 'GRADE4' then 'Grade 4'
  when 'GR5' then 'Grade 5' when 'GRADE5' then 'Grade 5'
  when 'GR6' then 'Grade 6' when 'GRADE6' then 'Grade 6'
  when 'GR7' then 'Grade 7' when 'GRADE7' then 'Grade 7'
  when 'GR8' then 'Grade 8' when 'GRADE8' then 'Grade 8'
  when 'GR9' then 'Grade 9' when 'GRADE9' then 'Grade 9'
  when 'GR10' then 'Grade 10' when 'GRADE10' then 'Grade 10'
  when 'GR11' then 'Grade 11' when 'GRADE11' then 'Grade 11'
  when 'GR12' then 'Grade 12' when 'GRADE12' then 'Grade 12'
  else null end
$$;
revoke all on function public.canonical_grade(text) from public,anon;
grant execute on function public.canonical_grade(text) to authenticated;

alter table public.students
 add column if not exists source_grade text,
 add column if not exists program text check(program in ('AMERICAN','IG')),
 add column if not exists program_review_required boolean not null default true;

-- Preserve the source label before canonicalizing. Only an explicit existing
-- division_code is accepted as a confirmed Program; nothing is inferred.
update public.students s set
 source_grade=coalesce(s.source_grade,s.grade),
 normalized_grade=public.canonical_grade(s.grade),
 grade=coalesce(public.canonical_grade(s.grade),s.grade),
 grade_sort_order=case public.canonical_grade(s.grade)
  when 'KG1' then 1 when 'KG2' then 2 when 'Grade 1' then 3 when 'Grade 2' then 4
  when 'Grade 3' then 5 when 'Grade 4' then 6 when 'Grade 5' then 7 when 'Grade 6' then 8
  when 'Grade 7' then 9 when 'Grade 8' then 10 when 'Grade 9' then 11 when 'Grade 10' then 12
  when 'Grade 11' then 13 when 'Grade 12' then 14 else null end,
 grade_review_required=(public.canonical_grade(s.grade) is null),
 program=case when upper(btrim(a.division_code)) in ('AMERICAN','IG') then upper(btrim(a.division_code)) else s.program end,
 program_review_required=not coalesce(upper(btrim(coalesce(a.division_code,s.program))) in ('AMERICAN','IG'),false)
from public.student_accounts a where a.student_id=s.id;

alter table public.admission_applications
 add column if not exists organization_id uuid references public.erp_organizations(id),
 add column if not exists school_id uuid references public.erp_schools(id),
 add column if not exists source_requested_grade text,
 add column if not exists grade_review_required boolean not null default false,
 add column if not exists program_review_required boolean not null default false;
update public.admission_applications set
 organization_id=coalesce(organization_id,public.default_organization_id()),
 school_id=coalesce(school_id,(select id from public.erp_schools where organization_id=public.default_organization_id() and active order by created_at limit 1)),
 source_requested_grade=coalesce(source_requested_grade,requested_grade),
 requested_grade=coalesce(public.canonical_grade(requested_grade),requested_grade),
 grade_review_required=(public.canonical_grade(requested_grade) is null),
 division=case when division='BRITISH' then 'IG' else division end;
alter table public.admission_applications alter column organization_id set default public.default_organization_id();
alter table public.admission_applications alter column organization_id set not null;
alter table public.admission_applications alter column school_id set not null;
alter table public.admission_applications drop constraint if exists admission_applications_division_check;
alter table public.admission_applications add constraint admission_applications_division_check check(division in ('AMERICAN','IG'));

create or replace function private.validate_grade_program() returns trigger
language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_grade text;v_program text;v_org uuid;v_school uuid;
begin
 v_grade:=public.canonical_grade(case when tg_table_name='students' then new.grade else new.requested_grade end);
 v_program:=upper(btrim(case when tg_table_name='students' then new.program else new.division end));
 v_org:=coalesce(new.organization_id,public.default_organization_id());
 v_school:=case when tg_table_name='admission_applications' then new.school_id else null end;
 if v_school is null then select id into v_school from public.erp_schools where organization_id=v_org and active order by created_at limit 1;end if;
 if v_grade is null then raise exception 'A canonical Grade is required';end if;
 if v_program not in ('AMERICAN','IG') then raise exception 'Program AMERICAN or IG is required';end if;
 if not exists(select 1 from public.grade_program_config c where c.organization_id=v_org and c.school_id=v_school and c.grade_name=v_grade and c.program=v_program and c.active) then
  raise exception 'The selected Grade / Program combination is inactive';
 end if;
 if tg_table_name='students' then
  new.source_grade:=coalesce(new.source_grade,new.grade);new.grade:=v_grade;new.normalized_grade:=v_grade;
  new.grade_review_required:=false;new.program:=v_program;new.program_review_required:=false;
 else
  new.source_requested_grade:=coalesce(new.source_requested_grade,new.requested_grade);new.requested_grade:=v_grade;
  new.division:=v_program;new.grade_review_required:=false;new.program_review_required:=false;
 end if;
 return new;
end$$;
drop trigger if exists validate_student_grade_program on public.students;
create trigger validate_student_grade_program before insert or update of grade,program on public.students
for each row when (new.program is not null) execute function private.validate_grade_program();
drop trigger if exists validate_admission_grade_program on public.admission_applications;
create trigger validate_admission_grade_program before insert or update of requested_grade,division,organization_id,school_id on public.admission_applications
for each row execute function private.validate_grade_program();
revoke all on function private.validate_grade_program() from public,anon,authenticated;

-- Bind the existing Auth identity to the real MCIS school scope. No Auth user
-- is created and no password is touched.
update public.user_profiles p set role='DR_AMANY_APPROVER',active=true,updated_at=now()
from auth.users u where p.user_id=u.id and lower(u.email)='amanyhussienelz@gmail.com';
insert into public.hr_user_capabilities(user_id,capability,active)
select id,'DR_AMANY_APPROVER',true from auth.users where lower(email)='amanyhussienelz@gmail.com'
on conflict(user_id,capability) do update set active=true;
update public.erp_user_scopes us set school_id=s.id,active=true
from auth.users u,public.erp_schools s
where us.user_id=u.id and lower(u.email)='amanyhussienelz@gmail.com'
 and us.organization_id=s.organization_id and s.school_code='MCIS';

-- Read access only. Existing tenant restrictive policies still apply.
create policy dr_amany_students_read on public.students for select to authenticated
using(public.has_hr_capability('DR_AMANY_APPROVER'));
create policy dr_amany_employees_read on public.hr_employees for select to authenticated
using(public.has_hr_capability('DR_AMANY_APPROVER'));
create policy dr_amany_leave_read on public.hr_leave_requests for select to authenticated
using(public.has_hr_capability('DR_AMANY_APPROVER'));
create policy dr_amany_admissions_read on public.admission_applications for select to authenticated
using(public.has_hr_capability('DR_AMANY_APPROVER') and public.can_access_organization(organization_id));
create policy dr_amany_approval_requests_read on public.approval_requests for select to authenticated
using(public.has_hr_capability('DR_AMANY_APPROVER'));

alter table public.hr_leave_requests
 add column if not exists decided_at timestamptz,
 add column if not exists decided_by uuid references auth.users(id),
 add column if not exists rejection_reason text;

create or replace function public.amany_decide_admission(p_application uuid,p_action text,p_reason text default null)
returns void language plpgsql security definer set search_path='public','pg_temp' as $$
declare a public.admission_applications%rowtype;v_status text;v_action text:=upper(btrim(p_action));
begin
 if auth.uid() is null or not public.has_hr_capability('DR_AMANY_APPROVER') then raise exception 'Dr Amany approval capability required';end if;
 select * into a from public.admission_applications where id=p_application for update;
 if not found or not public.can_access_organization(a.organization_id) then raise exception 'Application not found or outside scope';end if;
 if a.status<>'ASSESSED' then raise exception 'Only ASSESSED applications can be decided';end if;
 if v_action='APPROVE' then v_status:='ACCEPTED';
 elsif v_action='REJECT' then if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Rejection reason is required';end if;v_status:='REJECTED';
 else raise exception 'Action must be APPROVE or REJECT';end if;
 update public.admission_applications set status=v_status,status_reason=case when v_status='REJECTED' then btrim(p_reason) else null end,
  decided_at=now(),decided_by=auth.uid(),updated_at=now(),updated_by=auth.uid(),version=version+1 where id=a.id;
 insert into public.admission_reviews(application_id,from_status,to_status,reason,created_by) values(a.id,a.status,v_status,p_reason,auth.uid());
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by,metadata)
 values('admission_applications',a.id::text,v_action,jsonb_build_object('status',a.status),jsonb_build_object('status',v_status),auth.uid(),jsonb_build_object('reason',p_reason,'approved_role','DR_AMANY_APPROVER'));
end$$;

create or replace function public.amany_decide_leave(p_request uuid,p_action text,p_reason text default null)
returns void language plpgsql security definer set search_path='public','pg_temp' as $$
declare r public.hr_leave_requests%rowtype;v_status text;v_action text:=upper(btrim(p_action));
begin
 if auth.uid() is null or not public.has_hr_capability('DR_AMANY_APPROVER') then raise exception 'Dr Amany approval capability required';end if;
 select * into r from public.hr_leave_requests where id=p_request for update;
 if not found then raise exception 'Leave request not found';end if;
 if r.status not in ('SUBMITTED','PENDING') then raise exception 'Only pending requests can be decided';end if;
 if v_action='APPROVE' then v_status:='APPROVED';
 elsif v_action='REJECT' then if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Rejection reason is required';end if;v_status:='REJECTED';
 else raise exception 'Action must be APPROVE or REJECT';end if;
 update public.hr_leave_requests set status=v_status,review_note=coalesce(nullif(btrim(p_reason),''),review_note),
  rejection_reason=case when v_status='REJECTED' then btrim(p_reason) else null end,decided_at=now(),decided_by=auth.uid() where id=r.id;
 perform private.hr_audit('hr_leave_requests',r.id,v_action,to_jsonb(r),jsonb_build_object('status',v_status,'reason',p_reason,'actor',auth.uid()));
end$$;

revoke all on function public.amany_decide_admission(uuid,text,text),public.amany_decide_leave(uuid,text,text) from public,anon;
grant execute on function public.amany_decide_admission(uuid,text,text),public.amany_decide_leave(uuid,text,text) to authenticated;

create or replace function private.audit_grade_program_config() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_events(table_name,record_id,action,old_data,new_data,changed_by)
 values('grade_program_config',coalesce(new.id,old.id)::text,tg_op,case when tg_op='INSERT' then null else to_jsonb(old) end,
  case when tg_op='DELETE' then null else to_jsonb(new) end,auth.uid());
 return coalesce(new,old);
end$$;
create trigger audit_grade_program_config after insert or update or delete on public.grade_program_config
for each row execute function private.audit_grade_program_config();
revoke all on function private.audit_grade_program_config() from public,anon,authenticated;

insert into public.audit_events(table_name,record_id,action,new_data,metadata)
select 'user_profiles',u.id::text,'DR_AMANY_SCOPE_REPAIRED',jsonb_build_object('role','DR_AMANY_APPROVER','school_code','MCIS'),
 jsonb_build_object('password_changed',false,'financial_data_changed',false)
from auth.users u where lower(u.email)='amanyhussienelz@gmail.com';

commit;
