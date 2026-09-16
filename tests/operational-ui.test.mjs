import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const ui=readFileSync(new URL('../operational-ui.js',import.meta.url),'utf8');
const foundation=readFileSync(new URL('../supabase/migrations/20260916120000_operational_ui_foundation.sql',import.meta.url),'utf8');
const roles=readFileSync(new URL('../supabase/migrations/20260916122000_operational_role_policies.sql',import.meta.url),'utf8');
const attachmentScope=readFileSync(new URL('../supabase/migrations/20260916123000_scope_operation_attachments.sql',import.meta.url),'utf8');

test('operational shell is loaded and public sign-up is removed at runtime',()=>{
 assert.match(html,/operational-ui\.js\?v=20260916-1/);
 assert.match(ui,/signupTab\.remove\(\)/);
 assert.match(ui,/nav-group-title/);
 assert.match(ui,/screenSearch/);
 assert.match(ui,/breadcrumb/);
 assert.match(ui,/quickCreate/);
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
