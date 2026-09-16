# Bradford ERP operational UI audit — 2026-09-16

Target: `app.bradforderp.com` at commit `0fe6989`, compared with the operational-screen request.

## Confirmed gaps in the published baseline

- Navigation is a single flat list and has no screen search, breadcrumbs or user favourites.
- Public sign-up is visible despite the administrator-only account requirement.
- Procurement, inventory, assets, cheques and transport lists do not consistently expose contextual create actions.
- Several HR submodules remain list-only and do not yet have type-specific create/edit/review forms.
- There is no shared, private attachment component covering every requested record type.

## Implemented on `operational-ui-audit`

| Area | Create action | Persistence | Verification |
|---|---|---|---|
| Student | Existing `+ إضافة طالب جديد` | `create_student_with_account` RPC | Existing automated/static checks |
| Unified receipt | Existing cashier wizard | idempotent cashier RPC | Existing automated/static checks |
| Expense | Existing `+ مصروف جديد` | `expenses` DRAFT + private invoice upload | Existing automated/static checks |
| Employee | Existing `+ موظف جديد` | `hr_employees` | Existing automated/static checks |
| Purchase request | Added `+ طلب شراء` | idempotent DRAFT RPC | Staging transaction PASS |
| Vendor | Added `+ مورد` | `vendors` | Source/static PASS; authenticated UI UAT pending |
| Vendor quotation | Added `+ عرض سعر` | `vendor_quotations` DRAFT | Source/static PASS; authenticated UI UAT pending |
| Inventory item | Added `+ صنف` | `inventory_items` | Source/static PASS; authenticated UI UAT pending |
| Inventory movement | Added `+ حركة مخزن` | atomic idempotent DRAFT RPC | Staging transaction PASS; no stock effect PASS |
| Fixed asset | Added `+ أصل ثابت` | `fixed_assets` | Source/static PASS; authenticated UI UAT pending |
| Cheque | Added `+ شيك` | `cheques` DRAFT | Source/static PASS; authenticated UI UAT pending |
| Bus enrollment | Added `+ اشتراك باص` | `transport_enrollments` | Source/static PASS; authenticated UI UAT pending |

## Staging evidence

- Applied migrations: `operational_ui_foundation`, `add_operational_roles`, `operational_role_policies`, `scope_operation_attachments`, `fix_attachment_policy_execution`.
- Transaction/rollback UAT: purchase idempotency PASS; inventory idempotency PASS; DRAFT stock effect PASS; READ_ONLY denial PASS.
- Attachment isolation UAT: HR_MANAGER sees HR documents only PASS; STOREKEEPER sees inventory documents only PASS; READ_ONLY sees none PASS.
- Cleanup check: zero UAT users, purchase requests and inventory movements remained.
- Browser: public sign-up removed; desktop console had no errors; 390×844 login viewport rendered without horizontal overflow.

## Remaining before Production/main

- Authenticated browser UAT for each real role is required; no passwords were available and no Production test accounts were created.
- Complete type-specific forms are still required for RFQ, purchase order, receiving, vendor bill/payment/return, inventory count, transport routes/vehicles/staff/trips, all HR generic modules, asset maintenance/transfer/disposal, and approval-policy administration.
- The shared attachment database/storage foundation exists on Staging, but the reusable upload/preview/camera/signed-download UI is not yet wired across all forms.
- Supabase security advisor still reports existing project warnings, including leaked-password protection disabled and multiple exposed SECURITY DEFINER RPCs. The new two draft RPCs are role-guarded and were denial-tested, but the full historical RPC set remains a release-review item.

Verdict: **NOT READY**. Do not merge to `main` or apply these migrations to Production until the remaining authenticated UAT and type-specific workflows are complete.
