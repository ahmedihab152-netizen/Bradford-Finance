# Phase 1 design — Admissions and Student Administration

This is an implementation contract, not an applied migration and not a claim that Admissions is live. It is deliberately held behind the production backup/restore gate.

## Additive data model

Proposed new tables use UUID primary keys, `created_at`, `created_by`, `updated_at`, optimistic versioning where edited, organization/school/branch scope, RLS, and audit triggers.

- `admission_applications`: immutable application number, academic year, requested grade/division, applicant identity fields, status and status reason.
- `admission_guardians`: father/mother/guardian contacts, relationship and authorized-contact flags; sensitive values are column-restricted.
- `admission_documents`: private Storage object path, document kind, review status, checksum and reviewer metadata. No public bucket URLs.
- `admission_appointments`: assessment/interview type, capacity-aware slot, state and attendance.
- `admission_assessments`: academic, behavioral and interview results with confidential-note access separated from general review.
- `admission_reviews`: append-only decision trail for document review, waitlist, acceptance and rejection.
- `admission_duplicate_candidates`: deterministic and probable-match evidence, resolution and resolver.
- `student_families` and `student_family_members`: family account and sibling relationships without merging student identities.
- `student_contacts`: versioned parent/guardian contact records.
- `student_enrollments`: academic-year/grade/class/division history with one active enrollment per student/year and no deletion of prior years.
- `academic_classes`: scoped class and capacity.
- `student_services`: dated education/books/uniform/transport/activity enrollment linked to approved charges where applicable.
- `student_status_history`: append-only active/withdrawn/suspended/graduated transitions.

Existing `students` and `student_accounts` remain authoritative and are extended only through nullable foreign keys or compatibility views after a verified backfill. No existing identifier or balance is rewritten.

## Server-side interfaces

- Public submission uses a rate-limited Edge Function with schema validation, bot protection, idempotency key and a narrowly scoped server secret. The browser never receives privileged credentials.
- Private uploads use authenticated, short-lived signed upload URLs and server-generated object paths. File type, size and checksum are validated before review.
- Workflow transitions use security-invoker RPCs that lock the application row, validate the current state/role/scope/reason, append audit evidence and return the new state.
- `enroll_admission_application(application_id, idempotency_key)` is a single transaction. It locks the accepted application, rechecks duplicates and class capacity, creates/reuses exactly one student and family relationship, creates one account, creates approved charge/service rows, inserts enrollment/history, and marks ENROLLED. Any failure rolls back the entire transaction.
- Application numbers come from a database sequence/prefix rule, not client-side counting. Idempotency is protected by unique constraints.

## Workflow

Allowed forward states are `DRAFT → SUBMITTED → DOCUMENTS_REVIEW → ASSESSMENT_SCHEDULED → ASSESSED`, followed by `WAITING_LIST`, `ACCEPTED` or `REJECTED`; an accepted application may become `ENROLLED`, and eligible states may become `WITHDRAWN`. Server functions define the exact transition graph. Rejection/waitlist/withdrawal require a reason. Enrollment is irreversible by deletion; correction uses an audited administrative action.

## Duplicate controls

Hard duplicate keys use normalized national ID/passport when supplied. Probable duplicates compare normalized student name plus birth date and contact phone. Probable matches block automatic enrollment and require authorized resolution. A unique constraint on source application and idempotency key prevents repeated enrollment on retries.

## RLS and role matrix

- Anonymous callers cannot select tables; they can invoke only the constrained public submission interface.
- ADMISSIONS_ENTRY reads/writes assigned-scope DRAFT/application contact data but cannot decide or enroll.
- ADMISSIONS_REVIEWER reviews documents/assessments and cannot final-accept/enroll.
- ADMISSIONS_APPROVER decides and invokes enrollment within assigned scope.
- Finance roles see only the resulting permitted student/account/charge rows, not confidential assessment notes.
- OWNER oversight is scoped and audited; it does not override a designated exclusive approval.
- Storage policies bind object paths to application scope and authorized reviewer claims. Signed URLs expire quickly.

Every public table has RLS enabled and no broad `authenticated using (true)` policy. RPC authorization derives `auth.uid()` server-side and never trusts role, school or creator identifiers supplied by the browser.

## Migration and rollback strategy

Create one forward-only migration for enums/tables/constraints/indexes, one for RLS/grants/helpers, and one for workflow/enrollment functions and compatibility views. Apply to Staging, run rollback-transaction tests and the Admissions section of `docs/UAT_CHECKLIST.md`, then rehearse restore. Rollback before Production is drop-new-objects in reverse dependency order; after Production release, preserve submitted data and disable entry points rather than dropping records.

## Required business inputs before activation

- Academic-year and grade catalog, class capacities, application-number prefix policy.
- Required-document matrix by division/grade/nationality.
- Assessment scoring and acceptance authority/threshold policy.
- Approved fee/discount plans used by enrollment; no amounts may be invented.
- Retention/privacy periods and consent text for applicant/student documents.
- Notification provider and approved Arabic/English message templates, if notifications are enabled.
