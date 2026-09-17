import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const frontend=['index.html','cashier.js','hr-operations.js','hr-phase6.js','ig-exams.js','admissions.js','procurement.js','inventory.js','assets-cheques.js','transport-operations.js','tax-integration.js','multi-school.js','report-center.js'].map(read).join('\n');
const migrations=fs.readdirSync(path.join(root,'supabase','migrations')).filter(x=>x.endsWith('.sql')).sort().map(x=>read(path.join('supabase','migrations',x))).join('\n').toLowerCase();

test('production frontend contains no native dialogs, privileged secret or localhost URL',()=>{
 assert.doesNotMatch(frontend,/\b(?:alert|prompt|confirm)\s*\(/);
 assert.doesNotMatch(frontend,/service[_-]?role|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|localhost|127\.0\.0\.1/i);
});

test('only the canonical production HTML entry point is shipped',()=>{
 const html=fs.readdirSync(root).filter(x=>x.endsWith('.html'));
 assert.deepEqual(html,['index.html']);
});

test('role and exclusive approval controls remain server-backed',()=>{
 for(const token of ['dr_amany_approver','hr_manager','hr_officer','payroll_cashier','approval_authorities','hr_approval_authorities'])assert.ok(migrations.includes(token),token);
 for(const token of ['READ_ONLY','AUDITOR'])assert.ok(frontend.includes(token),token);
 assert.match(migrations,/only designated payroll cashier can record payment/);
 assert.match(migrations,/only dr\. amany hussein can approve or reject/);
});

test('financial, stock and enrollment idempotency invariants are present',()=>{
 for(const token of ['idempotency_key','negative stock is forbidden','journal is not balanced','procurement_three_way_match',"if a.status='enrolled' then return a.enrolled_student_id"])assert.ok(migrations.includes(token),token);
});

test('tax adapter requires bearer identity and supports browser preflight',()=>{
 const edge=read('supabase/functions/tax-adapter/index.ts');
 assert.match(edge,/req\.method==="OPTIONS"/);
 assert.match(edge,/authorization/);
 assert.match(edge,/tax_process_sandbox/);
 assert.doesNotMatch(edge,/SERVICE_ROLE|service_role/);
});

test('authorization does not trust editable user metadata',()=>{
 assert.doesNotMatch(migrations,/raw_user_meta_data|user_metadata/);
});

test('final payroll separation of duties is enforced server-side',()=>{
 const sod=read('supabase/migrations/20260917121000_final_payroll_separation_of_duties.sql').toLowerCase();
 for(const token of ['biometric_manager','payroll_preparer','attendance_officer','dr_amany_approver','payroll_cashier'])assert.ok(sod.includes(token),token);
 assert.match(sod,/separation of duties violation/);
 assert.match(sod,/r\.status<>'approved'/);
 assert.match(sod,/payment method, reference and document are required/);
 assert.match(sod,/biometric_sync_enabled','false'/);
 const prepareAudit=read('supabase/migrations/20260917122000_audit_payroll_preparation.sql').toLowerCase();
 for(const token of ['prepare','prepared_by','prepared_at','supporting_document_url'])assert.ok(prepareAudit.includes(token),token);
});
