# Bradford School ERP — Admin guide

## Production boundaries

The published application is a static GitHub Pages frontend connected to Supabase. Never place a `service_role` key, database password, tax credential, mail credential, or backup encryption key in `index.html`, browser storage, GitHub Actions variables exposed to pull requests, or committed files. Administrative database work must be performed through reviewed additive migrations and server-side functions.

Production data must not be used for destructive testing. Approved financial and payroll records are immutable; corrections use the documented cancellation or reversal workflow. A migration may be released only after a complete backup and a successful restore test in a separate environment.

## Release procedure

1. Confirm `git status` is clean and `main` is current.
2. Record the production baseline with `supabase/tools/production-baseline.sql` using a read-only SQL session.
3. Confirm a fresh encrypted backup exists outside Production, its manifest contains a SHA-256 digest, and the most recent isolated restore test passed.
4. Review every new migration for forward-only behavior, RLS, grants, audit coverage, idempotency, rollback/compensation, and compatibility with existing rows.
5. Apply migrations first to an isolated Staging project and run role/workflow tests there.
6. Run `npm test`, complete the affected entries in `docs/UAT_CHECKLIST.md`, and inspect the browser console at desktop and mobile widths.
7. Apply the reviewed migration to Production only after all gates pass. Re-run the read-only baseline and compare counts/invariants.
8. Push the tested frontend commit to `main`, wait for GitHub Pages, then perform a non-destructive published smoke test.
9. Update `docs/RELEASE_NOTES.md` with the commit, migrations, evidence, limitations, and rollback route.

## Account administration

- Supabase Authentication owns identities. Do not create a duplicate Auth identity to repair a profile.
- A new signup remains inactive/read-only until an authorized administrator links and approves its profile.
- Assign roles by immutable Auth `user_id`, not by a display name. Normalize email only for lookup and verify the selected UUID before writing.
- Scope access by organization, school, branch, division, academic year, department, and cost center when those dimensions exist.
- Approval authority is independent of broad administrative visibility. OWNER is not an implicit substitute for an exclusive named approver.
- Require MFA for final approvals, bank-detail changes, backup/restore initiation, and other designated sensitive operations.

## Operational monitoring

The OWNER system-check page and database queries should monitor connection/auth health, RLS failures, unbalanced journals, orphaned records, duplicates, pending approvals, missing expense/asset documents, and backup/restore-test freshness. A green UI indicator is not proof by itself: retain query output or an immutable audit reference for each release.

Escalate immediately when any of these occur: an unbalanced posted journal, a non-POSTED record affecting official totals, cross-scope data visibility, an approved record being editable/deletable, a leaked credential, a failed backup digest, or a restore test performed against Production.

## Incident and recovery

Disable the affected write path without deleting evidence. Preserve audit logs and record the incident window. Rotate exposed secrets server-side. Recovery must target a new isolated project first; validate the manifest digest, row counts, referential integrity, RLS, storage-object inventory, and application smoke tests before a separately approved cutover. See `docs/BACKUP_RESTORE.md` for the current backup gate and runbook.
