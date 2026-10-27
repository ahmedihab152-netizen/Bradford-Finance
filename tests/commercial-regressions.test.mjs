import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
function totals(){
 const source=html.match(/window\.accountOfficialTotals=function\(account,payments\)\{[^\n]+/);
 assert.ok(source,'one shared official-balance calculation must exist');
 const context={window:{}};vm.runInNewContext(source[0],context);return context.window.accountOfficialTotals;
}
test('official remaining agrees with the profile for all three observed discrepancies',()=>{
 const calculate=totals();
 for(const [due,paid,legacy,expected] of [[10000000,7294000,4706000,2706000],[11100000,7100000,6000000,4000000],[11100000,5000000,8100000,6100000]]){
  const actual=calculate({id:'a',total_due_piasters:due,legacy_paid_piasters:paid,legacy_remaining_piasters:legacy},[]);
  assert.equal(actual.remaining,expected);
 }
});
test('the actual student table renders the calculated balance rather than the imported remainder',()=>{
 const helper=html.match(/window\.accountOfficialTotals=function\(account,payments\)\{[^\n]+/)[0];
 const renderer=html.match(/  studentRows=function\(a\)\{[^\n]+/)[0];
 const context={esc:String,egp:String,discountText:()=>'',window:{_accountPostedPayments:[]}};
 vm.runInNewContext(helper+'\n'+renderer,context);
 const row=context.studentRows([{id:'a',total_due_piasters:10000000,legacy_paid_piasters:7294000,legacy_remaining_piasters:4706000,students:{student_code:'audit',student_name:'Test'}}]);
 assert.ok(row.includes('<td>2706000</td>'));assert.ok(!row.includes('<td>4706000</td>'));
});
test('only posted payments affect official balance, reversals reduce paid and overpayments remain visible',()=>{
 const calculate=totals(),a={id:'a',total_due_piasters:10000,legacy_paid_piasters:1000};
 const p=[{account_id:'a',status:'POSTED',amount_piasters:3000,effect_sign:1},{account_id:'a',status:'POSTED',amount_piasters:500,effect_sign:-1},{account_id:'a',status:'DRAFT',amount_piasters:9000},{account_id:'a',status:'SUBMITTED',amount_piasters:8000},{account_id:'other',status:'POSTED',amount_piasters:50000}];
 assert.equal(calculate(a,p).paid,3500);assert.equal(calculate(a,p).remaining,6500);
 assert.equal(calculate({...a,legacy_paid_piasters:11000},[]).remaining,-1000);
});
test('CSV text cannot initiate a spreadsheet formula; ordinary negative numbers retain numeric meaning',()=>{
 const source=html.match(/function csvSafeCell\(value\)\{[^\n]+/);assert.ok(source);
 const context={};vm.runInNewContext(source[0],context);
 for(const value of ['=1+1','+SUM(A1:A2)','@SUM(1,1)','-cmd','  =1+1','\t=1+1'])assert.ok(context.csvSafeCell(value).startsWith("'"),value);
 assert.equal(context.csvSafeCell('-12.50'),'-12.50');assert.equal(context.csvSafeCell('normal'),'normal');
});

function cashierHarness(rpc,storage=new Map()){
 const source=readFileSync(new URL('../cashier.js',import.meta.url),'utf8');
 const code=source.slice(source.indexOf(' let cashierSaving=false;'),source.indexOf(' function batchQueueMarkup'));
 const context={crypto:webcrypto,TextEncoder,Uint8Array,session:{user:{id:'test-user'}},state:{selected:{id:'test-account'},tenders:[{method:'CASH',amount:12345}]},payloadLines:()=>[{category:'TUITION',paid_now_piasters:12345}],sum:xs=>xs.reduce((a,b)=>a+b,0),document:{querySelectorAll:()=>[]},$:()=>({value:''}),supabase:{rpc},sessionStorage:{getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},uiToast:()=>{},renderCashier:async()=>{},cashierOpenBatch:async()=>{}};
 context.window=context;vm.runInNewContext(code,context);return context;
}
test('cashier blocks a second save while the first RPC is in flight',async()=>{
 let calls=0,release,started;const ready=new Promise(r=>started=r);
 const h=cashierHarness(async()=>{calls++;started();return new Promise(r=>release=r)});
 const first=h.cashierSave(false);await ready;await h.cashierSave(false);assert.equal(calls,1);
 release({data:'batch'});await first;
});
test('unknown save outcome reuses the same key even after a page reload',async()=>{
 const keys=[],storage=new Map();
 const failed=cashierHarness(async(_name,p)=>{keys.push(p.p_idempotency_key);return {error:{message:'connection lost'}}},storage);
 await failed.cashierSave(false);assert.equal(storage.size,1);
 const reloaded=cashierHarness(async(_name,p)=>{keys.push(p.p_idempotency_key);return {data:'same-batch'}},storage);
 await reloaded.cashierSave(false);assert.equal(keys.length,2);assert.equal(keys[0],keys[1]);assert.equal(storage.size,0);
});
test('submission retry never creates a second saved draft',async()=>{
 const calls=[],storage=new Map();let submissions=0;
 const h=cashierHarness(async(name)=>{calls.push(name);if(name==='create_student_payment_batch')return {data:'saved-batch'};return ++submissions===1?{error:{message:'connection lost'}}:{data:null}},storage);
 await h.cashierSave(true);await h.cashierSave(true);
 assert.deepEqual(calls,['create_student_payment_batch','submit_student_payment_batch','submit_student_payment_batch']);
});

function journalHarness(rpc){
 const code=html.slice(html.indexOf('async function saveJournal(e)'),html.indexOf('\n',html.indexOf('async function saveJournal(e)')));
 const button={disabled:false},form={dataset:{},querySelector:()=>button};
 const values={'#jdr':'1100','#jcr':'1300','#jd':'2026-10-26','#jdesc':'Test journal','#ja':'123.45'};
 const context={crypto:webcrypto,supabase:{rpc},$:id=>({value:values[id]}),uiToast:()=>{},closeM:()=>{},ledger:async()=>{}};
 vm.runInNewContext(code,context);return {save:()=>context.saveJournal({preventDefault(){},target:form}),form,button,values};
}
test('manual journal blocks double save and sends one atomic balanced-journal request',async()=>{
 let calls=0,release,started;const ready=new Promise(r=>started=r);
 const h=journalHarness(async(name,p)=>{calls++;assert.equal(name,'create_manual_journal_draft');assert.equal(p.p_amount,12345);started();return new Promise(r=>release=r)});
 const first=h.save();await ready;await h.save();assert.equal(calls,1);assert.equal(h.button.disabled,true);release({data:'id'});await first;assert.equal(h.button.disabled,false);
});
test('manual journal retries an unknown outcome using the original request id',async()=>{
 const ids=[];let attempt=0;const h=journalHarness(async(_name,p)=>{ids.push(p.p_id);if(!attempt++)throw Error('lost response');return {data:p.p_id}});
 await h.save();await h.save();assert.equal(ids.length,2);assert.equal(ids[0],ids[1]);assert.equal(h.form.dataset.saving,'0');
});
test('manual journal refuses the same debit and credit account before sending',async()=>{
 let calls=0;const h=journalHarness(async()=>{calls++;return {data:'id'}});h.values['#jcr']='1100';await h.save();assert.equal(calls,0);
});
test('a live collection is counted once even after the database refreshes legacy totals',()=>{
 const calculate=totals();const a={id:'a',total_due_piasters:50000,opening_paid_piasters:10000,legacy_paid_piasters:22345};
 const p=[{account_id:'a',status:'POSTED',amount_piasters:12345,effect_sign:1}];
 assert.equal(calculate(a,p).paid,22345);assert.equal(calculate(a,p).remaining,27655);
});
test('reversed originals and signed reversals cancel without losing the opening balance',()=>{
 const calculate=totals();const a={id:'a',total_due_piasters:50000,opening_paid_piasters:10000,legacy_paid_piasters:10000};
 const p=[{account_id:'a',status:'REVERSED',amount_piasters:12345,effect_sign:1},{account_id:'a',status:'POSTED',amount_piasters:12345,effect_sign:-1}];
 assert.equal(calculate(a,p).paid,10000);assert.equal(calculate(a,p).remaining,40000);
});
function correctionHarness(rpc){
 const source=readFileSync(new URL('../cashier.js',import.meta.url),'utf8');
 const code=source.slice(source.indexOf(' let correctionSaving=false;'),source.indexOf(' window.cashierPrintReceipt='));
 const values={'#cashierCorrectionReason':{value:'Synthetic reversal'},'#cashierRefundConfirmed':{checked:true},'#cashierCorrectionDate':{value:'2026-10-26'},'#cashierReturnedGoods':{checked:true}};
 const c={document:{querySelectorAll:()=>[]},$:id=>values[id],supabase:{rpc},uiToast:()=>{},closeM:()=>{},renderCashier:async()=>{},cashierOpenBatch:async()=>{}};c.window=c;vm.runInNewContext(code,c);return {c,values};
}
test('receipt correction blocks concurrent clicks and requires refund confirmation',async()=>{
 let calls=0,release,started;const ready=new Promise(r=>started=r);
 const {c,values}=correctionHarness(async()=>{calls++;started();return new Promise(r=>release=r)});
 values['#cashierRefundConfirmed'].checked=false;await c.cashierCorrectBatch('batch','REVERSE');assert.equal(calls,0);
 values['#cashierRefundConfirmed'].checked=true;const first=c.cashierCorrectBatch('batch','REVERSE');await ready;await c.cashierCorrectBatch('batch','REVERSE');assert.equal(calls,1);release({data:'journal'});await first;
});
test('correction buttons respect maker and finance-admin roles',()=>{
 const src=readFileSync(new URL('../cashier.js',import.meta.url),'utf8');const code=src.slice(src.indexOf(' const correctionAdmins='),src.indexOf(' window.cashierRequestCorrection='));
 const c={profile:{role:'ACCOUNTANT'},session:{user:{id:'maker'}}};vm.runInNewContext(code,c);
 assert.ok(c.batchCorrectionActions({id:'b',status:'DRAFT',created_by:'maker'}).includes('إلغاء المسودة'));
 assert.equal(c.batchCorrectionActions({id:'b',status:'DRAFT',created_by:'other'}),'');
 assert.equal(c.batchCorrectionActions({id:'b',status:'POSTED'}),'');c.profile.role='FINANCE_MANAGER';assert.ok(c.batchCorrectionActions({id:'b',status:'POSTED'}).includes('استرداد'));
});
test('failed attachment metadata save attempts to remove the newly uploaded orphan',async()=>{
 const source=readFileSync(new URL('../operational-ui.js',import.meta.url),'utf8');
 const start=source.indexOf(' async function saveAttachments('),end=source.indexOf(' window.openOperationAttachment=',start);assert.ok(start>=0&&end>start);
 const removed=[];const ctx={session:{user:{id:'actor'}},crypto:webcrypto,fileHash:async()=> 'a'.repeat(64),supabase:{storage:{from:()=>({upload:async()=>({error:null}),remove:async paths=>{removed.push(...paths);return {error:null}}})},from:()=>({insert:async()=>({error:{message:'metadata denied'}})})}};
 vm.runInNewContext(source.slice(start,end),ctx);
 await assert.rejects(ctx.saveAttachments({files:[{name:'test.pdf',size:42,type:'application/pdf'}]},'transport_vehicles','test-id'),e=>e.message==='metadata denied');
 assert.equal(removed.length,1);assert.ok(removed[0].startsWith('actor/transport_vehicles/test-id/'));
});
function igReceiptHarness(rpc,storage=new Map()){
 const source=readFileSync(new URL('../ig-exams.js',import.meta.url),'utf8');const code=source.slice(source.indexOf(' let igSaving=false;'),source.indexOf(' const previous=igFinance;'));
 const fields={'#igPayAccount':{value:'account'},'#igPayMethod':{value:'CASH'},'#igPayBank':{value:''},'#igPayDate':{value:'2026-10-27'},'#igPayReference':{value:''}};let submit;
 const context={rows:[{id:'subject1',subject_code:'MATH',subject_name:'Maths',session_code:'2026'}],document:{addEventListener:(type,fn)=>{if(type==='submit')submit=fn},querySelectorAll:()=>[{value:'subject1'}],querySelector:()=>({value:'60'})},$:id=>fields[id],session:{user:{id:'actor'}},crypto:webcrypto,TextEncoder,Uint8Array,Array,JSON,sessionStorage:{getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},supabase:{rpc},uiToast:()=>{},closeM:()=>{},igFinance:async()=>{}};
 vm.runInNewContext(code,context);return {fields,submit:()=>submit({target:{id:'igExamPayForm',querySelector:()=>({disabled:false})},preventDefault(){}})};
}
test('IG receipt retry after a lost response reuses the same request key after reload',async()=>{
 const keys=[],storage=new Map();const first=igReceiptHarness(async(_name,p)=>{keys.push(p.p_idempotency_key);throw Error('lost response')},storage);await first.submit();
 const second=igReceiptHarness(async(_name,p)=>{keys.push(p.p_idempotency_key);return {data:'batch'}},storage);await second.submit();assert.equal(keys.length,2);assert.equal(keys[0],keys[1]);assert.equal(storage.size,0);
});
test('IG receipt prevents double save and demands a bank account for noncash',async()=>{
 let calls=0,release,started;const ready=new Promise(r=>started=r);const h=igReceiptHarness(async(_name,p)=>{calls++;assert.equal(p.p_tenders[0].bank_account_id,'bank1');started();return new Promise(r=>release=r)});
 h.fields['#igPayMethod'].value='QNB';await h.submit();assert.equal(calls,0);h.fields['#igPayBank'].value='bank1';const first=h.submit();await ready;await h.submit();assert.equal(calls,1);release({data:'batch'});await first;
});
