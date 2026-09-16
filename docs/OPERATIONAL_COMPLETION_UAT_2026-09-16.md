# Operational completion UAT — 2026-09-16

Environment: Supabase Staging `jmeyaazpuzhhvvmvjmbd` only. Production and `main` were not changed.

## Implemented forms

| Module | Create / edit entry point | Persistence target | Result |
|---|---|---|---|
| Procurement | Purchase requisition | guarded RPC | PASS (rollback) |
| Procurement | RFQ | `procurement_rfqs` | PASS (rollback) |
| Procurement | Vendor quotation | `vendor_quotations` | STATIC PASS; end-to-end blocked by empty Staging vendors |
| Procurement | Quote comparison | `procurement_quote_decisions` | STATIC PASS; end-to-end blocked by empty Staging quotations |
| Procurement | Purchase order and line | `purchase_orders`, `purchase_order_lines` | STATIC PASS; end-to-end blocked by empty Staging vendors |
| Procurement | Goods receipt and line | `goods_receipts`, `goods_receipt_lines` | STATIC PASS; end-to-end blocked by empty Staging purchase orders |
| Procurement | Vendor bill | `vendor_bills` | STATIC PASS; end-to-end blocked by empty Staging PO/GRN |
| Procurement | Purchase return and line | `purchase_returns`, `purchase_return_lines` | STATIC PASS; end-to-end blocked by empty Staging GRN |
| Vendors | Add and edit | `vendors` | STATIC PASS |
| HR | Employee | `hr_employees` | Existing implementation retained |
| HR | Employee document | `hr_employee_documents` + private attachment | POLICY PASS |
| HR | Attendance / absence / late | `hr_attendance` | PASS (rollback) |
| HR | Leave / permission | `hr_leave_requests` | POLICY PASS |
| HR | Deduction / penalty / adjustment | `hr_compensation_items` | POLICY PASS |
| HR | Cover / overtime | `hr_cover_assignments` | POLICY PASS |
| HR | Payroll | existing payroll workflow | Existing implementation retained |
| Inventory | Movement | guarded RPC | PASS (rollback, prior UAT) |
| Inventory | Stock count and line | `inventory_counts`, `inventory_count_lines` | PASS (rollback) |
| Transport | Trip | `transport_trips` | STATIC/POLICY PASS |
| Transport | Vehicle | `transport_vehicles` | STATIC/POLICY PASS |
| Transport | Driver / supervisor | `transport_staff` | STATIC/POLICY PASS |
| Assets | Maintenance | `asset_maintenance` | PASS (rollback) |
| Assets | Transfer | `asset_transfers` | STATIC/POLICY PASS |
| Assets | Disposal / sale | `asset_disposals` | STATIC/POLICY PASS |

All forms accept PDF/JPG/PNG up to 10MB, calculate SHA-256, upload to the private `erp-private-documents` bucket, record uploader/time metadata, and provide a 120-second signed URL. Image inputs support `capture="environment"` and show a pre-save file preview.

## Role checks

RLS was exercised with `SET LOCAL ROLE authenticated`, a real Staging user UUID, and a temporary role change inside a transaction that was rolled back.

| Role | Check | Result |
|---|---|---|
| CASHIER | student scope read | PASS |
| ACCOUNTANT | vendor-bill read and asset-maintenance draft | PASS |
| TREASURY_MANAGER | cheque scope read | PASS |
| HR_OFFICER | HR read and attendance create | PASS |
| HR_MANAGER | payroll scope read | PASS |
| STOREKEEPER | inventory count header/line create | PASS |
| PROCUREMENT | RFQ draft create | PASS |
| APPROVER | quote-decision read | PASS |
| AUDITOR | audit event read | PASS |
| OWNER | user profile read | PASS |

Post-UAT residue query returned zero for purchase requisitions, inventory counts/items, HR employees, and asset maintenance rows tagged `UAT rollback`.

## Migrations applied to Staging

1. `20260916120000_operational_ui_foundation.sql`
2. `20260916121000_add_operational_roles.sql`
3. `20260916122000_operational_role_policies.sql`
4. `20260916123000_scope_operation_attachments.sql`
5. `20260916124000_fix_attachment_policy_execution.sql`
6. `20260916130000_complete_operational_role_policies.sql`
7. `20260916131000_operational_document_number_defaults.sql`
8. `20260916132000_fix_storekeeper_count_line_policy.sql`

## Release blockers

- Staging contains OWNER accounts only. There are no actual sign-in accounts for the other nine requested roles, so browser UAT "with a real account for every role" cannot be honestly marked complete.
- Leaked Password Protection remains disabled in Staging. The available database API reports the warning but cannot change Auth settings; desktop automation policy also forbids changing in-app security/privacy settings.
- Full browser workflows through REVIEW/APPROVE/POSTED are not available for every newly exposed operational record type. Existing posting RPCs cover purchase requisitions/orders/vendor bills, inventory movements, payroll and asset disposal, but not every RFQ, GRN, stock count, maintenance, transfer, trip, attendance and leave record as a uniform financial workflow.
- Because of these blockers, no Production migration, merge to `main`, deployment, or published/mobile screenshot claim was made.

## Completion run — authenticated UAT

Ten temporary Auth accounts were created in Staging, one for each requested role. Password authentication and profile loading succeeded for all ten accounts. Their JWTs were then used against the real REST/RPC boundary for the following state machines:

| Workflow | Roles used | Final state | Result |
|---|---|---|---|
| RFQ | PROCUREMENT → APPROVER | CLOSED | PASS |
| Quote decision | APPROVER | APPROVED | PASS |
| Goods receipt | STOREKEEPER → APPROVER → OWNER | POSTED | PASS |
| Inventory receipt/stock card | OWNER posting | quantity `1` | PASS |
| Inventory count | STOREKEEPER → APPROVER → OWNER | POSTED | PASS |
| Leave | HR_OFFICER → HR_MANAGER | APPROVED | PASS |
| Cover | HR_OFFICER → HR_MANAGER | APPROVED | PASS |
| Compensation | HR_OFFICER → HR_MANAGER | APPROVED | PASS |
| Asset maintenance | ACCOUNTANT → OWNER | COMPLETED | PASS |
| Transport trip | ACCOUNTANT | COMPLETED | PASS |

The run produced 19 audit events. All UAT records, inventory effects and temporary Auth accounts were then removed. The final residue check returned zero for users, requisitions, vendors, inventory items, employees, maintenance records and trips.

Additional Staging migrations:

9. `20260916133000_complete_operational_server_workflows.sql`
10. `20260916134000_quote_decision_approval_state.sql`
11. `20260916135000_quote_decision_nullable_approval.sql`

Repository verification after integration: 17/17 Node tests passed, all JavaScript parsed, static verification passed, and 51 additive migrations were unique.

## Remaining release gate

The Staging Security Advisor still reports `auth_leaked_password_protection` disabled even though the user confirmed it is enabled in Supabase. This likely means the setting was enabled on Production but not on the Staging project. The advisor also reports the intentionally exposed, role-guarded SECURITY DEFINER workflow RPCs; authenticated UAT demonstrated their role checks, but they remain visible as advisory warnings by design.

No merge or push to `main` has been performed. Production has not received these migrations.

Decision: **STAGING FUNCTIONAL PASS / PRODUCTION RELEASE HELD** pending reconciliation of the Staging password-protection advisor and the user's review of this report.
