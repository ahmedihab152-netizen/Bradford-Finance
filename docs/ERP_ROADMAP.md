# Bradford School ERP — implementation roadmap

This roadmap is dependency ordered. A phase is not released when its database, RLS, audit, integration and rollback tests are incomplete.

## Phase 0 — audit, backup and architecture

Freeze the current production baseline, create and restore-test a complete backup, finish the security/RLS matrix, generate the data dictionary and ERD, and establish an automated test harness. No schema changes before the backup gate.

## Phase 1 — admissions and student administration

Deliver public application intake through a rate-limited Edge Function, private document upload, reviewer/approver workflow, duplicate review and an atomic enrollment RPC that creates the student, account and approved charge plan. Add family accounts, class capacity, promotion history and service history without rewriting existing students.

## Phase 2 — vendors and procurement

Extend the existing vendor, requisition, PO, receipt, bill and payment structures. Add RFQs, quote comparison, approval thresholds, exception evidence, partial receipts, returns and a server-side three-way-match. Post journals only after approval.

## Phase 3 — general inventory

Introduce warehouses, categories, units, SKUs, lots/serials, immutable stock movements and average costing. Link approved receipts and student sales. Reject negative stock under row locks.

## Phase 4 — assets and cheques

Extend existing asset/cheque structures with lifecycle state machines, custody, maintenance, depreciation approval/posting, disposal/reversal and due-date controls.

## Phase 5 — transport

Extend existing transport structures with stops, capacity, trip attendance, temporary changes, maintenance, fuel and incidents. Provide provider-neutral GPS API contracts only; do not claim live GPS.

## Phase 6 — HR completion

Complete employee and biometric import with preview, mapping, deduplication and approval. Add approved attendance calculation feeding the next payroll period only.

## Phase 7 — tax integration readiness

Add organization/branch tax settings, code mapping, document queue, attempts and reconciliation. Deploy a JWT-protected Edge Function using server-side secrets and an explicitly labelled sandbox adapter until ETA credentials are supplied.

## Phase 8 — multi-school foundation

Add organization, school, branch, division, academic year and membership scope additively. Backfill current MCIS/IG into one verified organization without changing values. Activate tenant RLS only after coverage and cross-tenant denial tests pass.

## Phase 9 — reports and UX

Create a server-filtered report center, real pagination, Arabic/English message infrastructure, role dashboards, accessible modals/toasts and responsive A4 exports. Remove production `prompt()`/`alert()` usage.

## Phase 10 — security, UAT and release

Run the full role matrix, accounting invariants, duplicate/idempotency, stock, payroll, admissions, procurement, backup/restore, mobile and published smoke tests. Publish only when all gates pass and release notes, admin guide, role guides, ERD, data dictionary and UAT checklist are current.

