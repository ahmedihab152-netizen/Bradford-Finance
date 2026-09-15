# Bradford School ERP — Phase 0 data dictionary

This catalog groups the current production tables. Column-level definitions will be regenerated from the verified post-backup schema before Phase 1.

| Domain | Current principal tables | Status |
|---|---|---|
| Identity and access | `user_profiles`, approval authority tables | Active; role/RLS baseline requires full matrix test |
| Students and billing | `students`, `student_accounts`, `student_charges`, `student_payments`, allocations, discounts, refunds, write-offs | Active finance baseline |
| Unified cashier | `student_payment_batches`, `student_payment_lines`, `student_payment_tenders`, `student_stock_reservations` | Active; no Production batches at Phase 0 snapshot |
| Admissions source | `legacy_applications` | Historical/import source, not a complete Admissions workflow |
| Finance | `expenses`, treasury/bank tables, `chart_of_accounts`, journal tables, periods, snapshots | Active baseline |
| IG | departments, cost centers and dimension allocation/override tables | Active overlays |
| Vendors/procurement | `vendors`, requisitions, quotations, purchase orders, goods receipts, vendor bills/payments | Schema present; operational completeness pending |
| Uniform/books | uniform item/purchase/sale tables, `book_items`, packages | Uniform active; books catalog empty |
| Assets | `fixed_assets`, depreciation, transfers, counts, disposals | Partial lifecycle |
| Transport | routes, stops, vehicles, staff, enrollments, trips, attendance, temporary changes, documents, maintenance, fuel, incidents | Operations active; GPS remains a disabled provider-neutral contract until a provider is configured |
| HR/payroll | employees, documents, attendance, movements, biometric tables, secure import batches/rows, payroll runs/lines/payments | Operational HR active with server-validated imports and controlled payroll approvals |
| Tax readiness | organizations, code mappings, documents, submission attempts, reconciliations | Sandbox adapter active; Production ETA submission disabled until server-side credentials and certification are supplied |
| Tax and cheques | VAT, withholding, tax returns, `cheques` | Readiness structures; integrations/workflows pending |
| Audit and recovery | `audit_events`, findings, alerts, import batches, backup manifests, restore tests, UAT tables | Audit active; verified backup/restore absent |

Monetary values use integer piasters unless a legacy snapshot explicitly documents another representation. Official totals must consume only posted/approved states and reversal signs.
