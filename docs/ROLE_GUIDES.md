# Bradford School ERP — Role guides

Permissions are enforced by Supabase RLS and server-side workflow functions. Hidden buttons are only a usability aid and never an authorization boundary. A user should stop and report a permission error rather than request broader access as a workaround.

## OWNER

May view organization-wide dashboards, system checks, audit evidence and approved reports within assigned scopes. OWNER can manage authorized profiles and initiate a backup export/isolated restore test when MFA and policy allow. OWNER cannot replace Dr Amany's exclusive financial approval or the HR manager's stage approval merely because the role is OWNER.

## ACCOUNTANT / CASHIER

May search permitted students, prepare DRAFT collections/expenses, attach evidence, and submit them. DRAFT and SUBMITTED records remain provisional, red, and excluded from official balances. The cashier prints a provisional receipt until the authorized approval changes the transaction to POSTED. No approved transaction may be deleted or edited.

## FINANCE_MANAGER

May review and submit permitted financial work, reconcile supporting documents, and run scoped reports. This role does not bypass the configured exclusive final approver. Corrections after posting require an auditable reversal with the correct sign and period controls.

## IG ACCOUNTANT

May work only with IG-scoped records and the IG cost center. The role must not see or write American/Administration records unless a separate explicit scope grants it. Exports and prints inherit the same scope.

## DR AMANY APPROVER

The Auth identity linked to the configured approval authority is the exclusive final approver for designated student collections and expenses. She may approve or reject submitted items; rejection requires a reason. Approval creates the server-side posted effect and changes the visible state to green. Credentials and MFA must never be shared.

## HR_OFFICER

May create and edit employee/payroll inputs only while DRAFT, import through preview/validation, and submit to the HR manager. Cannot approve HR, approve final payroll, post accounting, or mark payroll paid. Bank and salary data must not be exported outside the permitted HR scope.

## HR_MANAGER

The linked HR manager reviews submitted payroll, approves the HR stage, or returns it with a mandatory correction reason. HR approval forwards the immutable calculation to Dr Amany; it is not final financial approval.

## Payroll payer

Mahmoud's linked identity may see only payroll that completed Dr Amany's approval and is ready for payment. He records payment date, method, reference and document. He cannot change earnings, deductions or net pay.

## AUDITOR / READ_ONLY

May view only assigned reports and audit evidence. These roles must have no insert, update, delete, submit, approve, reverse, restore, or payment capability. Printed and exported data is limited to rows and sensitive columns already permitted by RLS and the reporting function.

## Admissions roles (planned, not yet released)

ADMISSIONS_ENTRY prepares applications; ADMISSIONS_REVIEWER verifies documents and assessments; ADMISSIONS_APPROVER accepts/rejects and authorizes enrollment. Public applicants can access only their own short-lived submission flow. These roles become operational only after the Phase 1 migration and RLS test suite pass.
