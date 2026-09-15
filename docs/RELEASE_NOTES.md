# Bradford School ERP — release notes

## 5.0.0-phase9 — 2026-09-15

- Replaced the reports link directory with a unified, RLS-backed report center.
- Added server-side date, status and supported text filters with exact result counts and 50-row pagination.
- Added student, collection, expense, vendor, inventory, asset, transport, payroll, IG, ledger and tax report sources.
- Added row details, current-page totals, Arabic RTL A4 printing/PDF and Excel-compatible CSV export.
- Added Arabic/English message infrastructure plus responsive loading, empty, error and unauthorized states.
- Kept sensitive data filtering in Supabase RLS; no service-role credential or privileged browser path was added.
- This phase is frontend-only and performs no Production data migration or automatic data correction.

## 4.9.0-phase8 — 2026-09-15

- Added Organization, School, Branch, Division, Academic Year and user-scope entities with RLS.
- Registered the existing MCIS school, main campus and American/IG/Administration divisions without changing operational values.
- Backfilled organization keys across core student, finance, procurement, inventory, transport, HR and ledger tables.
- Added restrictive organization policies and a trigger guard so existing permissive policies cannot cause cross-organization access.
- Scoped every currently active user to the existing MCIS organization to preserve current access after migration.
- Added an RTL school/branch hierarchy page with details, printing/PDF and CSV export.
- Staging UAT verified current MCIS access, denied an unassigned second organization and blocked a cross-tenant student insert, then rolled back the test tenant.

## 4.8.0-phase7 — 2026-09-15

- Added RLS-protected tax organization/branch settings, ETA item mappings, document queue, attempts and reconciliation registers.
- Added invoice, receipt, Credit Note and Debit Note document types with controlled lifecycle states.
- Added server-authorized READY validation and an auditable Sandbox processing RPC.
- Added a JWT-protected Edge Function that forwards the user identity and never contains ETA credentials or a service-role key.
- Sandbox processing refuses Production configuration and labels every response as simulation.
- Added an Arabic RTL tax-readiness center with search, details, printing/PDF and CSV export.
- Staging UAT validated DRAFT → READY → sandbox ACCEPTED, attempt history and audit evidence, then rolled back all test rows.

## 4.7.0-phase6 — 2026-09-15

- Completed server-side employee-import Preview with SHA-256, validation rows and race-safe employee-code duplicate prevention.
- Restricted final employee import confirmation to the designated HR Manager authority (Rehab); HR Officer can prepare Preview only.
- Completed biometric-file Preview with device validation, unlinked-user detection and punch-log duplicate prevention.
- Restricted biometric confirmation to the designated HR Manager and kept immutable raw logs outside payroll until reviewed movements are approved.
- Preserved the established payroll authority chain: HR Officer draft, Rehab HR approval, Dr. Amany final approval and designated Mahmoud disbursement-only action.
- Staging UAT verified one valid, one duplicate and one invalid employee row, blocked HR Officer confirmation, allowed designated HR Manager confirmation, then rolled back all rows.

## 4.6.0-phase5 — 2026-09-15

- Added route stops, scheduled trips and per-student boarding/alighting attendance.
- Added temporary route changes, vehicle documents and expiry alerts.
- Added vehicle maintenance, fuel and incident registers with immutable audit evidence.
- Added a security-invoker route occupancy view with capacity and over-capacity warnings.
- Added a disabled-by-default, provider-neutral integration contract for future GPS and parent applications; no live GPS is claimed.
- Added a searchable RTL transport operations center with details, printing/PDF and CSV export across operational registers.
- Kept transport accounting isolated: only existing POSTED student payments contribute to official transport revenue.
- Staging UAT verified route, vehicle, enrollment, trip, boarding attendance, occupancy and audit behavior, then rolled back all test rows.

## 4.5.0-phase4 — 2026-09-15

- Added RLS-protected asset maintenance, warranty, custody and immutable lifecycle registers.
- Added a security-invoker asset book-value view with monthly depreciation calculations.
- Added immutable cheque status history and a due/overdue alert view for incoming and outgoing cheques.
- Removed direct deletion privileges from approved asset and cheque lifecycle records.
- Added searchable Arabic RTL asset and cheque dashboards, row details, print/PDF and CSV export.
- Added guarded cheque cancellation and bounce actions with mandatory reasons and server-side authorization.
- Fixed authenticated execution of the existing private MFA enforcement helper without exposing administrative capability.
- Staging UAT verified asset acquisition/transfer/depreciation and cheque cancellation/history, then rolled back all test rows.

## 4.4.0-phase3 — 2026-09-15

- Added multi-warehouse general inventory, categories, SKU/barcode items, balances, movements, counts and stock-card reporting.
- Added weighted-average costing for receipts and transfers.
- Added server-side negative-stock prevention and POSTED-only balance effects.
- Added batch, serial and expiry fields for tracked items.
- Added nullable procurement receiving links without altering existing receipts.
- Added searchable RTL inventory registers with details, print/PDF and CSV export.
- Staging UAT posted a receipt, verified quantity/cost, rejected an over-issue and rolled back all test rows.

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
