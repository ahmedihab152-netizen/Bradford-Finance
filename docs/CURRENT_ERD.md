# Bradford School ERP — current baseline ERD

This is the Phase 0 domain map. It documents the current database; it does not imply that every workflow is complete.

```mermaid
erDiagram
  AUTH_USERS ||--|| USER_PROFILES : profile
  STUDENTS ||--o{ STUDENT_ACCOUNTS : academic_year
  STUDENT_ACCOUNTS ||--o{ STUDENT_PAYMENTS : receives
  STUDENT_ACCOUNTS ||--o{ STUDENT_CHARGES : charged
  STUDENT_ACCOUNTS ||--o{ STUDENT_PAYMENT_BATCHES : cashier
  STUDENT_PAYMENT_BATCHES ||--|{ STUDENT_PAYMENT_LINES : contains
  STUDENT_PAYMENT_BATCHES ||--|{ STUDENT_PAYMENT_TENDERS : paid_by
  STUDENTS ||--o{ TRANSPORT_ENROLLMENTS : subscribes
  TRANSPORT_ROUTES ||--o{ TRANSPORT_ENROLLMENTS : serves
  HR_EMPLOYEES ||--o{ PAYROLL_LINES : paid_on
  PAYROLL_RUNS ||--o{ PAYROLL_LINES : contains
  PAYROLL_RUNS ||--o| PAYROLL_PAYMENTS : settled_by
  VENDORS ||--o{ PURCHASE_ORDERS : supplies
  PURCHASE_ORDERS ||--o{ GOODS_RECEIPTS : received
  PURCHASE_ORDERS ||--o{ VENDOR_BILLS : invoiced
  JOURNAL_ENTRIES ||--|{ JOURNAL_LINES : balances
  FIXED_ASSETS ||--o{ ASSET_TRANSFERS : history
  FIXED_ASSETS ||--o{ DEPRECIATION_RUN_LINES : depreciated
  BACKUP_MANIFESTS ||--o{ RESTORE_TEST_RUNS : rehearsed
```

## Trust boundaries

1. GitHub Pages is an untrusted public client. It may hold a publishable Supabase key, never privileged credentials.
2. Supabase Auth establishes identity and MFA assurance.
3. RLS and guarded PostgreSQL RPCs enforce roles, row scope and workflow transitions.
4. Private Storage must enforce path ownership/role rules and issue short-lived signed URLs.
5. Future ETA, GPS, email and messaging providers must be called only from authenticated server-side adapters using managed secrets.
6. Backups leave Production only as encrypted artifacts with a SHA-256 manifest and are restored only into an isolated target.
