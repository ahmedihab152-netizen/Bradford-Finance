begin;

alter table public.students add column if not exists student_phone text;
alter table public.students add column if not exists guardian_name text;
alter table public.students add column if not exists guardian_phone text;
alter table public.students add column if not exists guardian_phone_alt text;
alter table public.students add column if not exists student_email text;
alter table public.students add column if not exists address text;
alter table public.student_accounts alter column opening_paid_piasters set default 0;
alter table public.student_accounts alter column opening_remaining_piasters set default 0;
alter table public.student_accounts alter column opening_due_piasters set default 0;

alter table public.students drop constraint if exists students_email_format;
alter table public.students add constraint students_email_format check (student_email is null or student_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$');

create or replace function public.create_student_with_account(
 p_student_code text,p_student_name text,p_grade text,p_academic_year text,
 p_student_phone text default null,p_guardian_name text default null,
 p_guardian_phone text default null,p_guardian_phone_alt text default null,
 p_student_email text default null,p_address text default null
) returns uuid language plpgsql security invoker set search_path='public','pg_temp' as $$
declare v_student_id uuid; v_role public.finance_role;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 v_role:=public.current_finance_role();
 if v_role not in ('OWNER','CEO','FINANCE_MANAGER','ACCOUNTANT','ADMISSION') then raise exception 'Not authorized to create students'; end if;
 if nullif(btrim(p_student_code),'') is null or nullif(btrim(p_student_name),'') is null then raise exception 'Student code and name are required'; end if;
 if nullif(btrim(p_academic_year),'') is null then raise exception 'Academic year is required'; end if;
 insert into public.students(student_code,student_name,grade,status,student_phone,guardian_name,guardian_phone,guardian_phone_alt,student_email,address,joined_year,created_by,updated_by)
 values(upper(btrim(p_student_code)),btrim(p_student_name),nullif(btrim(p_grade),''),'ACTIVE',nullif(btrim(p_student_phone),''),nullif(btrim(p_guardian_name),''),nullif(btrim(p_guardian_phone),''),nullif(btrim(p_guardian_phone_alt),''),nullif(lower(btrim(p_student_email)),''),nullif(btrim(p_address),''),nullif(split_part(p_academic_year,'-',1),'')::integer,auth.uid(),auth.uid())
 returning id into v_student_id;
 insert into public.student_accounts(student_id,academic_year,created_by,updated_by)
 values(v_student_id,btrim(p_academic_year),auth.uid(),auth.uid());
 return v_student_id;
exception when unique_violation then raise exception 'Student code already exists';
end $$;

revoke all on function public.create_student_with_account(text,text,text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.create_student_with_account(text,text,text,text,text,text,text,text,text,text) to authenticated;

commit;
