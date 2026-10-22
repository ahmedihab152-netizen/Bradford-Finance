import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const ui=readFileSync(new URL('../operational-ui.js',import.meta.url),'utf8');
const foundation=readFileSync(new URL('../supabase/migrations/20260916120000_operational_ui_foundation.sql',import.meta.url),'utf8');
const roles=readFileSync(new URL('../supabase/migrations/20260916122000_operational_role_policies.sql',import.meta.url),'utf8');
const attachmentScope=readFileSync(new URL('../supabase/migrations/20260916123000_scope_operation_attachments.sql',import.meta.url),'utf8');
const workflows=readFileSync(new URL('../supabase/migrations/20260916133000_complete_operational_server_workflows.sql',import.meta.url),'utf8');
const quoteApproval=readFileSync(new URL('../supabase/migrations/20260916134000_quote_decision_approval_state.sql',import.meta.url),'utf8');
const amanyUi=readFileSync(new URL('../amany-financial-approvals.js',import.meta.url),'utf8');
const amanyDashboard=readFileSync(new URL('../dr-amany-dashboard.js',import.meta.url),'utf8');
const amanyBatch=readFileSync(new URL('../supabase/migrations/20260920123000_amany_mobile_grouped_financial_approvals.sql',import.meta.url),'utf8');
const hrPhase6=readFileSync(new URL('../hr-phase6.js',import.meta.url),'utf8');
const hrOperations=readFileSync(new URL('../hr-operations.js',import.meta.url),'utf8');
const attendanceFile=readFileSync(new URL('../supabase/migrations/20261015090000_attendance_file_import_without_device.sql',import.meta.url),'utf8');
const attendancePolicy=readFileSync(new URL('../supabase/migrations/20261015100000_attendance_deduction_policy.sql',import.meta.url),'utf8');
const attendanceBasis=readFileSync(new URL('../supabase/migrations/20261015102000_attendance_gross_daily_basis.sql',import.meta.url),'utf8');
const payrollAdjustments=readFileSync(new URL('../supabase/migrations/20261021111312_add_payroll_manual_adjustments.sql',import.meta.url),'utf8');
const payrollReview=readFileSync(new URL('../supabase/migrations/20261022120000_complete_attendance_payroll_review.sql',import.meta.url),'utf8');
const bulkReview=readFileSync(new URL('../supabase/migrations/20261022133000_bulk_employee_attendance_review.sql',import.meta.url),'utf8');
const cashier=readFileSync(new URL('../cashier.js',import.meta.url),'utf8');
const sourceImports=readFileSync(new URL('../supabase/migrations/20261022173000_source_controlled_finance_imports.sql',import.meta.url),'utf8');

test('approved finance workbooks are traceable and superseded student accounts stay hidden',()=>{
 assert.match(html,/const STUDENT_YEAR='2025-2026'/);
 assert.match(html,/cashier\.js\?v=20260914-3/);
 assert.match(html,/student_accounts\(source_meta,students/);
 assert.match(html,/source_meta\?\.superseded/);
 assert.match(cashier,/source_meta/);
 assert.match(cashier,/!a\.source_meta\?\.superseded/);
 for(const table of ['erp_source_files','erp_source_rows']) assert.match(sourceImports,new RegExp(`create table if not exists public\\.${table}`));
 assert.match(sourceImports,/enable row level security/);
 assert.match(sourceImports,/duplicate_of/);
});

test('operational shell is loaded and public sign-up is removed at runtime',()=>{
 assert.match(html,/operational-ui\.js\?v=20260916-1/);
 assert.match(html,/hr-phase6\.js\?v=20261022-2/);
 assert.match(ui,/signupTab\.remove\(\)/);
 assert.match(ui,/nav-group-title/);
 assert.match(ui,/screenSearch/);
 assert.match(ui,/breadcrumb/);
 assert.match(ui,/quickCreate/);
});

test('employee attendance review is inline and saved once as a bulk decision set',()=>{
 assert.match(hrPhase6,/data-inline-review-action="APPLY"/);
 assert.match(hrPhase6,/data-inline-review-action="CANCEL"/);
 assert.match(hrPhase6,/data-cancel-reason/);
 assert.match(hrPhase6,/إجمالي الخصومات المختارة/);
 assert.match(hrPhase6,/صافي المستحق/);
 assert.match(hrPhase6,/لم يُراجع/);
 assert.match(hrPhase6,/تم احتساب الخصم/);
 assert.match(hrPhase6,/أُلغي الخصم/);
 assert.match(hrPhase6,/hr_save_employee_attendance_review/);
});

test('bulk attendance review RPC validates every row and writes one audit event',()=>{
 assert.match(bulkReview,/Every attendance row must be reviewed exactly once/);
 assert.match(bulkReview,/Invalid decision or missing cancellation reason/);
 assert.match(bulkReview,/BULK_ATTENDANCE_REVIEW/);
 assert.match(bulkReview,/status='PENDING_HR'/);
 assert.match(bulkReview,/revoke all on function public\.hr_save_employee_attendance_review/);
});

test('payroll review supersedes the old gross preview with base net divided by 30',()=>{
 assert.match(attendanceBasis,/salary_basis='GROSS'/); // historical migration remains immutable
 assert.match(payrollReview,/daily_salary_piasters=round\(e\.net_salary_piasters\/30\.0\)/);
 assert.match(payrollReview,/Gross remains an independent source field/);
 assert.match(attendanceBasis,/'financial_effect',false/);
 assert.match(attendanceBasis,/'requires_hr_approval',true/);
 assert.doesNotMatch(attendanceBasis,/service_role/i);
});

test('school attendance policy and zero-punch holiday rule are server-side and financially inert',()=>{
 for(const rule of ['ABSENCE_INFORMED','ABSENCE_UNEXCUSED','LATE_EARLY_04_10','LATE_EARLY_GT150','PERMISSION_01_02','PERMISSION_05_PLUS','MISSING_PUNCH']) assert.match(attendancePolicy,new RegExp(rule));
 for(const pct of ['5','10','20','30','40','50']) assert.match(attendancePolicy,new RegExp(`,${pct},0`));
 assert.match(attendancePolicy,/not exists\(select 1 from public\.hr_attendance_file_punches/);
 assert.match(attendancePolicy,/NO_PUNCH_DAY/);
 assert.match(attendancePolicy,/hr_finalize_attendance_file/);
 assert.match(attendancePolicy,/'financial_effect',false/);
 assert.match(hrPhase6,/hr_finalize_attendance_file/);
 assert.doesNotMatch(attendancePolicy,/service_role/i);
});

test('core create actions persist through Supabase or guarded RPCs',()=>{
 for(const name of ['newPurchaseRequisition','newVendor','newQuotation','newInventoryItem','newInventoryMovement','newFixedAsset','newCheque','newBusEnrollment']) assert.match(ui,new RegExp(`window\\.${name}=`));
 for(const table of ['vendors','vendor_quotations','inventory_items','fixed_assets','cheques','transport_enrollments']) assert.match(ui,new RegExp(`from\\('${table}'\\)\\.insert`));
 assert.match(ui,/create_purchase_requisition_draft/);
 assert.match(ui,/create_inventory_movement_draft/);
 assert.match(ui,/b\.disabled=on/);
});

test('attachments are private, limited and protected by RLS',()=>{
 assert.match(foundation,/operation_attachments enable row level security/);
 assert.match(foundation,/erp-private-documents','erp-private-documents',false/);
 assert.match(foundation,/10485760/);
 assert.match(foundation,/application\/pdf/);
 assert.match(foundation,/image\/jpeg/);
 assert.match(foundation,/image\/png/);
 assert.match(foundation,/unique\(source_table,source_id,sha256\)/);
 assert.match(attachmentScope,/organization_id uuid/);
 assert.match(attachmentScope,/can_access_organization/);
 assert.match(attachmentScope,/can_read_operation_attachment/);
});

test('specialized roles are granted bounded table access',()=>{
 for(const role of ['CASHIER','TREASURY_MANAGER','STOREKEEPER','PROCUREMENT','APPROVER']) assert.match(roles,new RegExp(role));
 assert.doesNotMatch(roles,/service_role/);
});

test('remaining operational forms are connected to persisted records',()=>{
 for(const name of ['newRFQ','newQuoteComparison','newPurchaseOrder','newGoodsReceipt','newVendorBill','newPurchaseReturn','newInventoryCount','newTransportTrip','newTransportVehicle','newTransportStaff','newAssetMaintenance','newAssetTransfer','newAssetDisposal','newHREmployeeDocument','newHRAttendance','newHRLeave','newHRDeduction','newHRCover','newHRCompensation']) assert.match(ui,new RegExp(`window\\.${name}=`));
 for(const table of ['procurement_rfqs','procurement_quote_decisions','purchase_orders','goods_receipts','vendor_bills','purchase_returns','inventory_counts','transport_trips','transport_vehicles','transport_staff','asset_maintenance','asset_transfers','asset_disposals','hr_employee_documents','hr_attendance','hr_leave_requests','hr_compensation_items','hr_cover_assignments']) assert.match(ui,new RegExp(`(?:sourceTable=')?${table}`));
});

test('operational attachments use private storage, camera capture, preview, hash and signed URL',()=>{
 assert.match(ui,/capture="environment"/);
 assert.match(ui,/attachment-preview/);
 assert.match(ui,/erp-private-documents/);
 assert.match(ui,/fileHash\(file\)/);
 assert.match(ui,/createSignedUrl/);
 assert.match(ui,/uploaded_by:session\.user\.id/);
});

test('remaining operational state machines are server-side, role-checked and audited',()=>{
 for(const fn of ['procurement_rfq_action','goods_receipt_action','inventory_count_action','hr_operational_action','asset_maintenance_action','transport_trip_action']) assert.match(workflows,new RegExp(`function public\\.${fn}`));
 for(const role of ['PROCUREMENT','STOREKEEPER','APPROVER','HR_OFFICER','HR_MANAGER','ACCOUNTANT','OWNER','FINANCE_MANAGER']) assert.match(workflows,new RegExp(role));
 assert.match(workflows,/for update/);
 assert.match(workflows,/insert into public\.audit_events/);
 assert.match(workflows,/perform public\.post_inventory_movement/);
 assert.match(quoteApproval,/status in\('DRAFT','APPROVED','REJECTED'\)/);
 assert.match(quoteApproval,/approve_procurement_quote_decision/);
 assert.match(quoteApproval,/reject_procurement_quote_decision/);
});

test('Dr Amany mobile approvals are grouped, filtered and transactionally reviewed',()=>{
 for(const token of ['grade_program_config','afGrade','afProgram','afStatus','afType','afDate','Approve Selected','Reject Selected','amany-approval-card','@media(max-width:520px)']) assert.match(amanyUi,new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')));
 assert.match(amanyUi,/range\(0,4999\)/);
 assert.match(amanyUi,/review_financial_records_batch/);
 assert.match(amanyBatch,/for update/);
 assert.match(amanyBatch,/Duplicate records are not allowed/);
 assert.match(amanyBatch,/BATCH_'\|\|v_action/);
 assert.match(amanyBatch,/jsonb_array_length\(p_records\)>200/);
 assert.doesNotMatch(amanyUi,/service_role/i);
});

test('Dr Amany navigation exposes both dashboard and financial approvals',()=>{
  assert.match(amanyDashboard,/access\.DR_AMANY_APPROVER=.*'amany_dashboard','approvals'/);
});

test('attendance spreadsheet import works without a live biometric device and stays financially inert',()=>{
 assert.match(html,/hr-phase6\.js\?v=20261022-2/);
 for(const token of ['تم التعرف على الشيت تلقائيًا','hr_preview_attendance_file','hr_finalize_attendance_file','employee_code','punch_time']) assert.match(hrPhase6,new RegExp(token));
 assert.match(hrPhase6,/\.csv,\.xlsx,\.xls,\.pdf/);
 assert.match(hrPhase6,/PDF.*لا يصلح لحساب الحضور/);
 for(const table of ['hr_attendance_file_batches','hr_attendance_file_rows','hr_attendance_file_punches']) assert.match(attendanceFile,new RegExp(`create table if not exists public\\.${table}`));
 assert.match(attendanceFile,/File must contain between 1 and 20000 rows/);
 assert.match(attendanceFile,/unique \(employee_id, punch_time, punch_type\)/);
 assert.match(attendanceFile,/hr_daily_attendance/);
 assert.match(attendanceFile,/source_record_id,status,created_by,updated_by\)\s*\n\s*values\([\s\S]*?'DRAFT'/);
 assert.match(attendanceFile,/'financial_effect',false/);
 assert.match(attendanceFile,/HR biometric manager confirmation required/);
 assert.doesNotMatch(hrPhase6,/service_role/i);
});

test('biometric spreadsheets auto-detect ZKTeco event and daily report columns without manual mapping',()=>{
 for(const token of ['detectColumns','normalizedPunches','ac-no.','clock in','clock out','automatic:true']) assert.match(hrPhase6,new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'),'i'));
 assert.doesNotMatch(hrPhase6,/id="afEmployee"/);
 assert.doesNotMatch(hrPhase6,/اختر الأعمدة ثم اضغط/);
 assert.match(hrPhase6,/await window\.submitAttendanceFilePreview\(\)/);
 assert.match(hrPhase6,/punch_type:'IN'/);
 assert.match(hrPhase6,/punch_type:'OUT'/);
});

test('HR payroll review and approval actions stay visible on narrow screens',()=>{
 assert.match(hrPhase6,/const hrActions=canHr/);
 assert.match(hrPhase6,/إرسال الكشف لد\. أماني/);
 assert.match(hrPhase6,/صف واحد لكل موظف/);
 assert.match(hrPhase6,/data-payroll-employee/);
 assert.match(hrPhase6,/data-save-employee-review/);
 assert.match(hrPhase6,/حالات غير محسومة/);
});

test('payroll adjustment and biometric review buttons are directly wired and audited',()=>{
 for(const token of ['data-employee-adjust','data-detail-review','خصم / زيادة','تطبيق الخصم المقترح','إذن','hr_set_payroll_adjustment','manual_deduction_piasters']) assert.match(hrPhase6,new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')));
 assert.doesNotMatch(hrPhase6,/onclick="(?:editPayrollIncrease|reviewPayrollItem)/);
 assert.match(payrollAdjustments,/function public\.hr_set_payroll_adjustment/);
 assert.match(payrollAdjustments,/SET_MANUAL_ADJUSTMENT/);
 assert.match(payrollAdjustments,/role_name not in \('OWNER','CEO','HR_MANAGER'\)/);
 assert.match(payrollAdjustments,/revoke all on function public\.hr_set_payroll_adjustment.*public,anon/);
 assert.match(payrollAdjustments,/approved_deduction_piasters=x\.approved_total \+ e\.manual_deduction_piasters/);
 assert.doesNotMatch(payrollAdjustments,/service_role/i);
});

test('payroll review uses net over 30, exposes data issues, and blocks unresolved sending',()=>{
 assert.match(payrollReview,/daily_salary_piasters=round\(e\.net_salary_piasters\/30\.0\)/);
 assert.match(payrollReview,/EG001_NAME_CONFLICT_AMANY_UYAR/);
 assert.match(payrollReview,/MISSING_GROSS_SOURCE/);
 assert.match(payrollReview,/Cannot send: % unresolved cases/);
 assert.match(payrollReview,/delete from public\.hr_holidays where source_type='NO_PUNCH_DAY'/);
 assert.match(payrollReview,/loan_installment_piasters/);
});

test('HR navigation is shared, sticky, role-filtered and survives internal page changes',()=>{
 assert.match(html,/id="hrSharedNav"/);
 assert.match(html,/class="hr-nav-shell"/);
 assert.match(html,/\.hr-nav-shell\{position:sticky;top:68px/);
 assert.match(html,/overflow-x:auto/);
 assert.match(html,/direction:rtl/);
 assert.match(html,/sessionStorage\.setItem\('bradford_hr_module'/);
 assert.match(html,/sessionStorage\.getItem\('bradford_hr_module'/);
 assert.match(html,/ensureHRNavigation/);
 assert.match(hrOperations,/ensureHRNavigation/);
});

test('mobile HR and top action buttons remain visible without horizontal clipping',()=>{
  assert.match(html,/\.hr-tabs\{display:grid;grid-template-columns:repeat\(2,minmax\(0,1fr\)\);overflow:visible/);
  assert.match(html,/\.top \.actions \.btn\{display:inline-block!important;flex:1 1 auto\}/);
  assert.match(html,/@media\(max-width:900px\)\{\.shell\{grid-template-columns:1fr\}/);
  assert.match(html,/\.top\{position:static;height:auto;min-height:68px;[^}]*flex-wrap:wrap\}/);
});
