# Bradford Finance production-readiness UAT — 2026-09-14

Environment: `Bradford Finance Staging 2026-09-14` (`jmeyaazpuzhhvvmvjmbd`)

Restore source: Physical backup completed at `2026-09-14 05:20:32 UTC`.

## Restore verification

- Students: 509 — PASS
- Active students: 494 — PASS
- Student accounts: 509 — PASS
- Student payments: 909 — PASS
- Expenses: 1,642 — PASS
- Legacy applications: 619 — PASS
- Legacy treasury rows: 4,419 — PASS
- Fixed assets: 142 — PASS
- Transport routes/enrollments: 11/41 — PASS
- Unbalanced journal entries: 0 — PASS
- Storage objects at manifest time: 0 — PASS

The restored snapshot predates later HR imports and Auth-user additions. Their lower
counts in Staging are therefore expected and are not treated as restore corruption.

## Transactional UAT

All test records and temporary role changes ran inside PostgreSQL exception
subtransactions and were rolled back in full.

- Student receipt: DRAFT -> SUBMITTED -> POSTED — PASS
- DRAFT/SUBMITTED has no official financial effect — PASS
- Exclusive Dr. Amany approval; OWNER bypass rejected — PASS
- Expense: DRAFT -> SUBMITTED -> POSTED — PASS
- Required invoice and voucher enforcement — PASS
- IG levels OL, AS, A2 and Full A Level — PASS
- IG entry types First Entry, Retake, Remark and Late Entry — PASS
- IG partial, multi-subject receipt — PASS
- SUBMITTED IG receipt excluded from paid balance — PASS
- HR Officer -> HR Manager -> Dr. Amany -> disbursement — PASS
- Payroll net calculation and immutable disbursement amount — PASS
- Payroll and finance journals balanced — PASS
- Test cleanup — PASS (ROLLBACK)

## Production invariants after migrations

- Students: 509; active: 494
- Student accounts: 509; student payments: 909
- Expenses: 1,642
- HR employees: 134
- Fixed assets: 142
- Transport routes/enrollments: 11/41
- Unbalanced journal entries: 0
- IG exam entries/payment batches: 0 (no Production test data inserted)
- Storage objects: 0

No automatic changes were made to the 14-student reconciliation difference or the
1,188 expense-document review set.

## Remaining dashboard advisory

Supabase Auth leaked-password protection is disabled and should be enabled in the
dashboard. Public `SECURITY DEFINER` RPC warnings are expected for the controlled
workflow endpoints; each endpoint performs server-side identity/role/authority checks.
