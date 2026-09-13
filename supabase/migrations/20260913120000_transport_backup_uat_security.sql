begin;

-- Bradford Finance: transport hardening, auditable backup metadata, and isolated UAT.
-- This migration never inserts, changes, or deletes operational finance/transport rows.

alter table public.transport_routes enable row level security;
alter table public.transport_vehicles enable row level security;
alter table public.transport_staff enable row level security;
alter table public.transport_enrollments enable row level security;

revoke all on public.transport_routes, public.transport_vehicles, public.transport_staff, public.transport_enrollments from anon, authenticated;
grant select on public.transport_routes, public.transport_vehicles, public.transport_staff, public.transport_enrollments to authenticated;
grant insert, update on public.transport_routes, public.transport_vehicles, public.transport_staff, public.transport_enrollments to authenticated;

-- Existing policies remain the row-level authority. Explicit grants above remove DELETE,
-- TRUNCATE, REFERENCES and TRIGGER from browser roles. Posted finance remains separate.

create table if not exists public.backup_manifests (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  byte_size bigint not null check (byte_size > 0),
  table_count integer not null check (table_count >= 0),
  row_count bigint not null check (row_count >= 0),
  environment text not null default 'PRODUCTION' check (environment in ('PRODUCTION','STAGING')),
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id)
);

create table if not exists public.restore_test_runs (
  id uuid primary key default gen_random_uuid(),
  backup_manifest_id uuid not null references public.backup_manifests(id),
  target_environment text not null check (target_environment = 'STAGING'),
  status text not null check (status in ('PLANNED','RUNNING','PASSED','FAILED')),
  integrity_verified boolean not null default false,
  schema_verified boolean not null default false,
  row_counts_verified boolean not null default false,
  rls_verified boolean not null default false,
  notes text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id)
);

create table if not exists public.uat_runs (
  id uuid primary key default gen_random_uuid(),
  scenario text not null default 'PAYMENT_EXPENSE_APPROVAL',
  status text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','POSTED','FAILED','CANCELLED')),
  payment_state text not null default 'DRAFT' check (payment_state in ('DRAFT','SUBMITTED','POSTED')),
  expense_state text not null default 'DRAFT' check (expense_state in ('DRAFT','SUBMITTED','POSTED')),
  isolated boolean not null default true check (isolated),
  print_payment_ok boolean not null default false,
  print_expense_ok boolean not null default false,
  role_results jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users(id)
);

create table if not exists public.uat_steps (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.uat_runs(id) on delete cascade,
  step_key text not null,
  acting_role text not null,
  result text not null check (result in ('PASS','FAIL','PENDING','BLOCKED')),
  evidence text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  unique(run_id, step_key)
);

alter table public.backup_manifests enable row level security;
alter table public.restore_test_runs enable row level security;
alter table public.uat_runs enable row level security;
alter table public.uat_steps enable row level security;

revoke all on public.backup_manifests, public.restore_test_runs, public.uat_runs, public.uat_steps from anon, authenticated;
grant select, insert on public.backup_manifests to authenticated;
grant select, insert, update on public.restore_test_runs, public.uat_runs, public.uat_steps to authenticated;

drop policy if exists backup_manifests_owner_select on public.backup_manifests;
create policy backup_manifests_owner_select on public.backup_manifests for select to authenticated
using (public.current_finance_role() = 'OWNER'::public.finance_role);
drop policy if exists backup_manifests_owner_insert on public.backup_manifests;
create policy backup_manifests_owner_insert on public.backup_manifests for insert to authenticated
with check (public.current_finance_role() = 'OWNER'::public.finance_role and created_by = (select auth.uid()));

drop policy if exists restore_test_runs_owner_select on public.restore_test_runs;
create policy restore_test_runs_owner_select on public.restore_test_runs for select to authenticated
using (public.current_finance_role() = 'OWNER'::public.finance_role);
drop policy if exists restore_test_runs_owner_insert on public.restore_test_runs;
create policy restore_test_runs_owner_insert on public.restore_test_runs for insert to authenticated
with check (public.current_finance_role() = 'OWNER'::public.finance_role and target_environment = 'STAGING' and created_by = (select auth.uid()));
drop policy if exists restore_test_runs_owner_update on public.restore_test_runs;
create policy restore_test_runs_owner_update on public.restore_test_runs for update to authenticated
using (public.current_finance_role() = 'OWNER'::public.finance_role)
with check (public.current_finance_role() = 'OWNER'::public.finance_role and target_environment = 'STAGING');

drop policy if exists uat_runs_finance_select on public.uat_runs;
create policy uat_runs_finance_select on public.uat_runs for select to authenticated
using (public.current_finance_role() in ('OWNER','FINANCE_MANAGER','ACCOUNTANT'));
drop policy if exists uat_runs_finance_insert on public.uat_runs;
create policy uat_runs_finance_insert on public.uat_runs for insert to authenticated
with check (public.current_finance_role() = 'OWNER' and created_by = (select auth.uid()) and updated_by = (select auth.uid()) and isolated);
drop policy if exists uat_runs_finance_update on public.uat_runs;
create policy uat_runs_finance_update on public.uat_runs for update to authenticated
using (public.current_finance_role() in ('OWNER','FINANCE_MANAGER','ACCOUNTANT'))
with check (isolated and updated_by = (select auth.uid()));

drop policy if exists uat_steps_finance_select on public.uat_steps;
create policy uat_steps_finance_select on public.uat_steps for select to authenticated
using (public.current_finance_role() in ('OWNER','FINANCE_MANAGER','ACCOUNTANT'));
drop policy if exists uat_steps_finance_insert on public.uat_steps;
create policy uat_steps_finance_insert on public.uat_steps for insert to authenticated
with check (public.current_finance_role() in ('OWNER','FINANCE_MANAGER','ACCOUNTANT') and created_by = (select auth.uid()));
drop policy if exists uat_steps_finance_update on public.uat_steps;
create policy uat_steps_finance_update on public.uat_steps for update to authenticated
using (public.current_finance_role() in ('OWNER','FINANCE_MANAGER','ACCOUNTANT'))
with check (public.current_finance_role() in ('OWNER','FINANCE_MANAGER','ACCOUNTANT'));

create index if not exists transport_routes_search_idx on public.transport_routes (academic_year, status, route_code);
create index if not exists transport_vehicles_route_idx on public.transport_vehicles (route_id, status);
create index if not exists transport_staff_vehicle_idx on public.transport_staff (vehicle_id, status);
create index if not exists transport_enrollments_student_idx on public.transport_enrollments (student_id, academic_year, status);
create index if not exists restore_test_runs_latest_idx on public.restore_test_runs (created_at desc);
create index if not exists uat_runs_latest_idx on public.uat_runs (created_at desc);

comment on table public.backup_manifests is 'OWNER-only metadata for client exports; backup contents remain outside the database.';
comment on table public.restore_test_runs is 'Audit log for restore rehearsals. Constraint prevents Production targets.';
comment on table public.uat_runs is 'Isolated workflow simulation; never joined into official finance totals.';

commit;
