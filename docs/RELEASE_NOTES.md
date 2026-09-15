# Bradford School ERP — release notes

## 4.3.0-phase2 — 2026-09-15

- Added the operational Procurement and Vendor center with searchable PR, RFQ, PO, receiving, bill, vendor and return registers.
- Added RFQ invitations, quote scoring, documented quotation exceptions, approval-limit configuration and quote decisions.
- Added server-side three-way matching and persisted match evidence.
- Added purchase returns and return lines without creating inventory movements before posting.
- Blocked vendor payments unless the bill is posted and matched or has an approved exception; added duplicate-payment protection.
- Tightened vendor and quotation write policies to authenticated finance roles and draft-only quotation changes.
- Staging UAT matched PR/PO/GRN/invoice totals and rolled back all test rows.

## 4.2.0-phase1 — 2026-09-15

- Added an operational Arabic RTL Admissions dashboard with search, draft creation, details, workflow actions and printing.
- Added 14 additive RLS-protected Admissions and Student Administration tables without changing existing rows.
- Added server-authorized transitions and append-only decision/audit history.
- Added idempotent enrollment that creates a student, zero-balance account and enrollment history atomically.
- Added national-ID/passport duplicate constraints and probable-match review support.
- No fee amount is inferred; approved fee plans remain a required activation input.
- Staging UAT passed DRAFT through ENROLLED and rolled back fully; an unauthorized role saw zero rows.

## 4.1.0-phase0 — 2026-09-14

Status: **NOT READY for full ERP production release**. The current Bradford Finance application remains available; this release establishes the controlled expansion baseline without applying a new database migration.

Added:

- Phase 0 production inventory, architecture roadmap, current ERD and data dictionary.
- Backup/restore gate documenting that the current Supabase Free plan has no platform project backup.
- Static verification for JavaScript syntax, canonical `index.html`, migration uniqueness, frontend secret patterns, localhost references and RLS declarations.
- GitHub Actions verification with read-only repository permissions and no production credentials.
- Independent backup-manifest verifier with automated tamper/count validation tests.
- Read-only Phase 1 database preflight for required contracts, duplicate keys, orphaned accounts and RLS state.
- Administrative runbook, role guides and evidence-based UAT checklist.
- Admissions/Student Administration Phase 1 implementation design.

Previously delivered and retained:

- Unified student cashier workflow and its additive migrations.
- Student, HR/payroll, transport, backup/UAT and exclusive-approval foundations already present in the repository.

Production database changes in this documentation/CI release: **none**.

Known release blockers:

- A complete production database backup and isolated restore test are required before the next migration. Supabase reported that project backups are unavailable on the current Free plan.
- The Phase 1 Admissions/Student Administration backend and UI are designed but not yet applied or presented as operational.
- The comprehensive security scan and full role-by-role Staging UAT require completion before a READY decision.

Rollback: documentation and CI changes can be reverted at Git level. No database rollback is needed because this release applies no database changes.
