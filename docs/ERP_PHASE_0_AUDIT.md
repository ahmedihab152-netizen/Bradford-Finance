# Bradford School ERP — Phase 0 audit

Date: 2026-09-14  
Production project: `yrdypwatutpceiligfzl`  
Audited revision: `920432d1b78039f2867e978bddfe715ba0080d82`

## Release gate

**BLOCKED — no verified restorable backup exists.** The Supabase dashboard reports that the project is on the Free plan and scheduled backups are unavailable. No ERP migration may be applied until one of the backup gates in `BACKUP_RESTORE.md` has completed and its manifest and restore test are recorded.

## Current architecture

- Static RTL browser application served by GitHub Pages (`index.html`, `cashier.js`, `hr-operations.js`).
- Supabase Auth supplies sessions and MFA; the browser uses a publishable key only.
- PostgreSQL/RLS is the authorization boundary. Sensitive workflows are implemented by guarded RPCs and audit triggers.
- Existing production domains include finance, students, IG, HR/payroll, transport, uniform, fixed assets, procurement skeletons, cheques, backup metadata and UAT metadata.
- Production contains 509 students/accounts, 909 historical student payments, 1,642 expenses, 142 assets, 134 HR employees and 12,927 audit events at audit time.
- Storage contains seven buckets and no objects at audit time. Database backups do not cover future Storage objects; off-site object backup must be independent.

## Existing capabilities to preserve

- Student cashier with Dr Amany-exclusive final approval and atomic posting.
- HR/payroll workflow with HR manager review, Dr Amany approval and separate payment recording.
- IG cost-center isolation overlays.
- Transport routes/enrollments and uniform stock.
- Double-entry journals, period locks, approval limits and immutable/audited financial workflows.
- Owner-only backup manifest and staging-only restore-test metadata.

## Material gaps found

1. There is no verified database backup or restore point. `backup_manifests` and `restore_test_runs` are empty.
2. The repository has no automated test runner/package manifest; current checks are migration/UAT scripts and browser smoke tests.
3. Admissions and Student Administration are not implemented as complete operational modules.
4. Procurement tables exist, but RFQ comparison, complete three-way-match UI and end-to-end workflow tests are incomplete.
5. General multi-warehouse inventory is absent; uniform/books are domain-specific.
6. Cheques, asset lifecycle and transport tables exist partly, but not the requested complete operational workflows.
7. Multi-school tenant keys and tenant-scoped RLS are not yet present.
8. Tax tables exist partly, but no secure ETA adapter/queue Edge Function is deployed.
9. The UI still contains `alert()` and `prompt()` calls and uses client-side bulk loading in several screens.
10. Supabase advisors report privileged-function and performance-policy warnings that require review before expanding exposed RPCs.
11. Public signup remains visible. New-profile restrictions exist, but Auth provider settings and inactive-account enforcement require a dedicated role test.

## Non-negotiable invariants

- Never rewrite or delete historical financial, student, HR, audit or source-import data.
- Additive migrations only; every migration includes rollback notes and a rehearsal on staging.
- No official financial effect before final approval and posting.
- No tenant is introduced until every relevant table and RPC carries and validates organization/school/branch scope.
- No service-role key, database password, ETA credential, GPS credential or mail credential in frontend or Git.
- Private documents use private buckets and short-lived signed URLs after server-side authorization.
- Each sensitive transition records actor, prior state, new state, reason and timestamp.

## Phase 0 exit criteria

- A logical or platform backup exists outside Production, with encrypted storage and SHA-256 manifest.
- A restore succeeds in an isolated project/local stack and row/schema invariants pass.
- Security scan and RLS role matrix are complete.
- Data dictionary and ERD are generated from the post-backup baseline.
- Baseline JavaScript, accounting balance, period lock and production smoke tests pass.

