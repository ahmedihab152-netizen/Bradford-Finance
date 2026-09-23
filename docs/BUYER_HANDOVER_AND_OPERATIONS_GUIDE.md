# Bradford ERP — Buyer Handover and Operations Guide

## Handover package

The buyer must receive controlled access to the GitHub repository, Supabase organization/project, DNS/Cloudflare account, Resend account, Android Play Console and Apple App Store Connect. Transfer access through each provider's team/role mechanism; never send passwords, API keys, recovery codes or signing keys in chat or source control.

Required artifacts:

- source commit and release tag;
- applied migration list and generated database types;
- Admin Guide, Role Guides, Data Dictionary, backup/restore runbook and UAT checklist;
- latest database backup manifest and successful isolated restore-test report;
- separate encrypted Storage-object inventory and backup;
- Android signed AAB provenance and iOS archive/TestFlight provenance;
- privacy policy, terms, support and account-deletion procedure;
- list of external services, owners, renewal dates and monthly costs.

## Safe daily operation

1. Administrators create accounts; public signup remains disabled.
2. Assign the minimum role, organization and capability scope. Require MFA for approvals and sensitive operations.
3. Financial and payroll drafts do not affect official balances. Only approved/posted server-side transitions may do so.
4. Dr Amany performs only the configured final approvals. Payroll cashiers record payment only after approval and cannot change payroll values.
5. Never delete posted financial or paid payroll records. Correct them with the documented reversal/adjustment workflow.
6. Keep `biometric_sync_enabled=false` unless the physical device health check and matched-punch test pass.
7. Review Security Advisor, failed Auth attempts, denied RLS actions, pending approvals, unbalanced journals, missing documents and backup freshness every business day.

## Release procedure

1. Freeze the release candidate and record the Git commit.
2. Confirm a fresh database backup and separate Storage backup.
3. Restore to isolated Staging and validate hashes, row counts, schema, RLS and journals.
4. Apply additive migrations to Staging in order; stop on the first failure.
5. Run automated tests and named-role browser UAT. Roll back/delete only isolated UAT rows and prove residue is zero.
6. Recheck Production counts, apply the reviewed migrations, and recheck counts before deploying the frontend.
7. Deploy the immutable frontend commit, wait for Pages/custom-domain publication, then perform read-only smoke tests on desktop and mobile.
8. If any release gate fails, stop; do not partially continue or edit live data to make the test pass.

## Backup and disaster recovery

- Keep 7 daily, 4 weekly and 12 monthly encrypted copies outside Production.
- Record filename, environment, byte size, table/row counts and SHA-256 in the backup manifest.
- Back up Storage objects separately; database backups contain Storage metadata, not object contents.
- Restore only to a new project/branch. Disable outbound email, tax, push and biometric integrations during rehearsal.
- Verify critical table counts, foreign keys, RLS denial tests, balanced journals, signed-file access and app smoke tests before any cutover decision.
- OWNER authorization is required for a restore; no direct restore over live Production is permitted.

## Incident response

Disable the affected write path, preserve audit evidence, record the incident window, rotate exposed server-side credentials, and notify the designated owner. Do not erase suspicious rows or logs. Recovery must use an isolated restore and an approved cutover plan.

## Commercial acceptance checklist

The buyer signs only when the final audit reports PASS for SMTP/recovery, physical biometric integration, named-role UAT, payroll and approvals, private attachments, audit trail, database plus Storage backup/restore, Android/iOS device QA, security advisors, Production/Staging schema parity and production smoke tests.

