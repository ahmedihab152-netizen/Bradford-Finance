# HR & Payroll rollback

The HR module is additive and does not alter student or existing finance rows. Before production use, take an OWNER backup. Rollback is allowed only while all payroll tables are empty: revoke the HR RPCs, drop HR triggers/functions, drop HR tables in reverse foreign-key order, then remove the three enum values only by rebuilding the enum in a maintenance window. PostgreSQL enum values are intentionally not removed automatically. Never roll back after a payroll run is approved; use a documented payroll reversal migration instead.

Required Auth accounts before live workflow: Rehab (HR_MANAGER), Mariana (HR_OFFICER), Dr Amany (final approver), Mahmoud (PAYROLL_CASHIER). The migration never creates Auth accounts.
