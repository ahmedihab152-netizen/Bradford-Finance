# Bradford School ERP — UAT checklist

Record date/time, environment, application commit, migration versions, tester Auth UUID/role, test record identifiers, expected result, actual result, PASS/FAIL, and evidence link for every executed item. Use isolated Staging data. Never mark an unexecuted row PASS.

## Release gates

- [ ] Fresh encrypted backup outside Production has a verified SHA-256 manifest.
- [ ] Restore completed in a separate environment; counts, relationships, RLS and storage inventory passed.
- [ ] `npm test` passes from the release commit.
- [ ] All new migrations applied to Staging in filename order and recorded.
- [ ] No critical browser-console errors at desktop and 360px mobile width.
- [ ] No `service_role`, private key, password, localhost URL or production test fixture exists in the frontend/repository.
- [ ] Published GitHub Pages content contains the release commit's cache-versioned assets.

## Identity and authorization

- [ ] Inactive/new user cannot access operational data.
- [ ] READ_ONLY and AUDITOR cannot write through UI, REST, RPC or direct crafted requests.
- [ ] Each role sees only assigned organization/school/branch/division/cost center.
- [ ] IDOR attempt using an out-of-scope UUID is denied without revealing row existence.
- [ ] Exclusive approver operations reject OWNER and FINANCE_MANAGER identities.
- [ ] Sensitive action without required MFA is denied and audited.
- [ ] Rejected authorization attempt appears in immutable audit evidence without sensitive payloads.

## Finance and cashier

- [ ] Student search works by name, code and grade with real pagination.
- [ ] Student details show education, bus, uniform and other permitted charges/payments without double counting.
- [ ] DRAFT and SUBMITTED collection/expense stay red and do not change official totals.
- [ ] Dr Amany alone can approve designated submitted collection and expense.
- [ ] POSTED state is green and creates balanced accounting effect once only.
- [ ] Duplicate/idempotency retry creates no second payment or journal.
- [ ] Provisional and approved receipt wording is correct; A4/mobile print renders RTL.
- [ ] Posted transaction cannot be edited/deleted; reversal is linked, signed correctly and audited.
- [ ] Period lock blocks backdated posting and routes a later adjustment correctly.

## HR and payroll

- [ ] HR_OFFICER can edit DRAFT only and cannot approve/pay.
- [ ] HR_MANAGER alone approves the HR stage or returns with mandatory reason.
- [ ] Dr Amany alone performs final payroll approval.
- [ ] Mahmoud sees only ready-for-payment payroll and cannot alter net pay.
- [ ] PAID records record date, method, reference and document; later correction is reversal/next-period adjustment.
- [ ] IG payroll uses the IG cost center.
- [ ] Employee/biometric import preview maps columns, rejects duplicate employee codes/punches and lists unmatched staff.
- [ ] Unapproved attendance never affects payroll.

## Admissions and enrollment (Phase 1 gate)

- [ ] Public form works on mobile without exposing private storage or other applications.
- [ ] Application number is unique under concurrent submission and retry.
- [ ] Duplicate national ID/passport and probable name/date/phone matches enter review rather than creating a student.
- [ ] Document completeness, assessment/interview and state transitions enforce role and reason requirements.
- [ ] ACCEPTED does not create finance records before enrollment approval.
- [ ] ENROLLED atomically creates one student, one account and the approved charge plan; failed step rolls back all.
- [ ] Enrollment retry is idempotent and audit-complete.

## Procurement and inventory (future phase gates)

- [ ] Approval thresholds and three-quotes/exception rules are server-enforced.
- [ ] Partial receipts cannot exceed approved PO quantities.
- [ ] Vendor payment requires a passing PO/receipt/invoice match and rejects duplicates.
- [ ] Approved receipt posts inventory/accounting once; return reverses the correct quantities/values.
- [ ] Concurrent issue/transfer cannot create negative stock.
- [ ] Stock card, average cost, lot/serial and warehouse scope reconcile to the ledger.

## Responsive, printing and accessibility

- [ ] Keyboard navigation reaches menu, filters, rows, modals and primary actions with visible focus.
- [ ] Arabic RTL and long tables work at 360px, tablet and desktop widths without inaccessible controls.
- [ ] Loading, empty, validation, unauthorized, error and success states are clear in Arabic.
- [ ] Print/PDF/CSV contains title, Bradford Finance, section, timestamp, user, filters, record count and permitted totals.
- [ ] UI controls/sidebar are hidden on A4 print and sensitive columns remain excluded.

## Final decision

READY requires every applicable release gate and module gate to pass with evidence. Any failed/unexecuted mandatory item, missing backup/restore test, unapplied migration, or unresolved high-severity security finding means NOT READY and must name the exact blocker.
