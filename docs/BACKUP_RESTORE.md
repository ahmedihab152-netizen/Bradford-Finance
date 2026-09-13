# Backup and restore runbook

1. An OWNER exports JSON through the application. The browser calculates SHA-256 and records only the manifest (name, size, table/row counts, hash).
2. Before restore, select the file again. The application recomputes SHA-256 and verifies the embedded manifest, table list, and row counts.
3. Restore is never executed from this Production browser. Provision a separate Supabase Staging project/branch without Production data and apply the repository migrations.
4. Import the verified payload into Staging with a server-side operator process using a Staging-only service-role secret. Never expose that secret to the browser.
5. Record a `restore_test_runs` row with target `STAGING`; the database constraint rejects any other target. Verify schema, row counts, RLS, and representative read-only reports, then mark PASSED/FAILED with evidence.
6. A Production recovery is a separately approved incident procedure using Supabase platform backups. This application does not offer a Production restore button.

Quarterly restore test: export, verify hash, restore to isolated Staging, compare table and row counts, run RLS negative tests for READ_ONLY/AUDITOR, run financial balance checks, record the outcome, then dispose of Staging according to retention policy.
