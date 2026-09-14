# Backup and restore runbook

## Independent integrity verification

After downloading an OWNER export, verify it outside the browser before copying it to protected backup storage:

```text
npm run verify:backup -- Bradford_Finance_Backup_YYYY-MM-DD.json
```

The command recalculates SHA-256 from the exact JSON payload and verifies its UTF-8 byte size, table count, row count, table-array structure and Production label. A non-zero exit code means the file must not be used for restore. This integrity check detects corruption or alteration; it does not replace encryption, access controls, a database-native backup, Storage-object export, or an isolated restore test.

Run `tools/phase1-preflight.sql` using a read-only SQL session before the backup and against the isolated restored database. Resolve every missing required object, duplicate account/year, orphaned account and RLS failure before applying Phase 1.

## Current production status — 2026-09-14

The Supabase dashboard reports **Free Plan — scheduled backups unavailable**. `backup_manifests` and `restore_test_runs` currently contain no verified run. This is a hard migration release gate, not a cosmetic warning.

Choose and complete one safe path before the next migration:

1. Upgrade the project to Pro and use **Restore to new project** for the rehearsal; or
2. Provide a short-lived database connection/password to an authorized operator and run `supabase db dump`/`pg_dump` over SSL into encrypted off-site storage, then restore into an isolated local or staging database.

Never put the database password or a Supabase access token in Git, `index.html`, browser storage, CI logs or the backup manifest. Database backups do not contain Storage objects; private buckets require a separate encrypted object export.

Required manifest fields: source project reference, PostgreSQL version, UTC start/end, tool version, encrypted artifact location, byte size, SHA-256, schema/table counts, Storage-object manifest hash, operator and verification result.

Required restore rehearsal: isolated target only, outbound integrations disabled, schema count comparison, critical table row-count comparison, balanced journals, orphan checks, RLS role-denial tests, application smoke test, result recorded in `restore_test_runs`, then destroy or lock the rehearsal environment according to retention policy.

1. An OWNER exports JSON through the application. The browser calculates SHA-256 and records only the manifest (name, size, table/row counts, hash).
2. Before restore, select the file again. The application recomputes SHA-256 and verifies the embedded manifest, table list, and row counts.
3. Restore is never executed from this Production browser. Provision a separate Supabase Staging project/branch without Production data and apply the repository migrations.
4. Import the verified payload into Staging with a server-side operator process using a Staging-only service-role secret. Never expose that secret to the browser.
5. Record a `restore_test_runs` row with target `STAGING`; the database constraint rejects any other target. Verify schema, row counts, RLS, and representative read-only reports, then mark PASSED/FAILED with evidence.
6. A Production recovery is a separately approved incident procedure using Supabase platform backups. This application does not offer a Production restore button.

Quarterly restore test: export, verify hash, restore to isolated Staging, compare table and row counts, run RLS negative tests for READ_ONLY/AUDITOR, run financial balance checks, record the outcome, then dispose of Staging according to retention policy.
