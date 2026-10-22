create table if not exists public.erp_source_files(
 id uuid primary key default gen_random_uuid(),
 file_key text not null unique,
 file_name text not null,
 sha256 text not null,
 category text not null,
 academic_year text,
 size_bytes bigint not null default 0,
 row_count integer not null default 0,
 imported_count integer not null default 0,
 status text not null default 'VALIDATED' check(status in('VALIDATED','IMPORTED','DUPLICATE','SUPERSEDED','FAILED')),
 duplicate_of uuid references public.erp_source_files(id),
 active boolean not null default true,
 metadata jsonb not null default '{}'::jsonb,
 imported_at timestamptz,
 created_at timestamptz not null default now()
);

create table if not exists public.erp_source_rows(
 id bigint generated always as identity primary key,
 source_file_id uuid not null references public.erp_source_files(id),
 sheet_name text not null,
 source_row integer not null,
 record_type text not null,
 external_key text,
 normalized_data jsonb not null default '{}'::jsonb,
 row_hash text not null,
 validation_status text not null default 'VALID' check(validation_status in('VALID','DUPLICATE','NEEDS_REVIEW','INVALID')),
 validation_errors text[] not null default '{}',
 imported_at timestamptz not null default now(),
 unique(source_file_id,sheet_name,source_row,record_type,external_key)
);

create index if not exists erp_source_rows_file_idx on public.erp_source_rows(source_file_id,record_type);
create index if not exists erp_source_rows_external_idx on public.erp_source_rows(external_key);
create index if not exists erp_source_rows_hash_idx on public.erp_source_rows(row_hash);

alter table public.erp_source_files enable row level security;
alter table public.erp_source_rows enable row level security;
revoke all on public.erp_source_files,public.erp_source_rows from anon,authenticated;
grant select on public.erp_source_files,public.erp_source_rows to authenticated;

drop policy if exists erp_source_files_read on public.erp_source_files;
create policy erp_source_files_read on public.erp_source_files for select to authenticated
using(public.current_finance_role() in('OWNER','CEO','FINANCE_MANAGER','AUDITOR','DR_AMANY_APPROVER'));

drop policy if exists erp_source_rows_read on public.erp_source_rows;
create policy erp_source_rows_read on public.erp_source_rows for select to authenticated
using(public.current_finance_role() in('OWNER','CEO','FINANCE_MANAGER','AUDITOR','DR_AMANY_APPROVER'));
