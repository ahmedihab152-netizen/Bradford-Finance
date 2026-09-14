import fs from 'node:fs/promises';
import {FileBlob,SpreadsheetFile,Workbook} from 'file:///C:/Users/mostafa/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
const source='C:/Users/mostafa/Downloads/MCIS_Application_Data_Master.xlsx';
const out='outputs/final_readiness_20260914';
const src=await SpreadsheetFile.importXlsx(await FileBlob.load(source));
console.log('SOURCE_IMPORTED');
const values=name=>src.worksheets.getItem(name).getUsedRange(true).values;
const records=name=>{const v=values(name),h=v[0].map(String);return v.slice(1).filter(r=>r.some(x=>x!==null&&x!=='')).map(r=>Object.fromEntries(h.map((x,i)=>[x,r[i]])))};
const students=records('Students'),payments=records('Student_Payments'),apps=records('Application_Fees'),treasury=records('Treasury'),expenses=records('Expenses'),ig=records('IG_Revenue'),advances=records('Advances'),audit=records('Audit');
const sum=(a,k)=>a.reduce((s,x)=>s+(Number(x[k])||0),0);
const distinct=(a,k)=>new Set(a.map(x=>String(x[k]??'').trim()).filter(Boolean)).size;
const duplicateCount=(a,k)=>a.length-distinct(a,k);
const missingExpenseDocs=expenses.filter(x=>!x.invoice_no||/بدون|لا يوجد|no invoice/i.test(String(x.invoice_no))).length;
const current=students.filter(x=>x.academic_year==='2026-2027'),prior=students.filter(x=>x.academic_year==='2025-2026');
const metrics=[
 ['طلاب المصدر — كل السنوات',students.length,'سجل سنة/طالب؛ لا يُجمع كعدد طلاب حالي'],
 ['طلاب 2026-2027 في المصدر',current.length,'يتطلب فصل المنسحب/طلب التقديم فقط قبل المقارنة'],
 ['طلاب 2025-2026 في المصدر',prior.length,'تاريخ سابق، ليس إضافة تلقائية للعام الحالي'],
 ['أكواد طلاب مميزة عبر الملف',distinct(students,'student_code'),'المقارنة مع Production غير منفذة لغياب جلسة Admin'],
 ['حركات تحصيل طلاب',payments.length,'المصدر الموحد'],
 ['صافي تحصيل الطلاب EGP',sum(payments,'amount'),'يشمل الإشارات السالبة كما وردت'],
 ['رسوم تقديم — سجلات',apps.length,'قد تشمل من لم يستكمل الالتحاق'],
 ['رسوم تقديم محصلة EGP',sum(apps,'payment_amount'),'مصدر فقط'],
 ['حركات خزنة',treasury.length,'بما فيها الرصيد الافتتاحي'],
 ['مدين خزنة EGP',sum(treasury,'debit_in'),'مصدر فقط'],
 ['دائن خزنة EGP',sum(treasury,'credit_out'),'مصدر فقط'],
 ['حركات بنك داخل كشف الخزنة EGP',sum(treasury,'bank_amount'),'مصدر فقط'],
 ['مصروفات',expenses.length,'مصدر فقط'],
 ['صافي المصروفات EGP',sum(expenses,'net_amount'),'السلف المخصصة للخصم من الراتب مفصولة أدناه'],
 ['مصروفات بمستند ناقص/غير واضح',missingExpenseDocs,'فحص نصي يحتاج مراجعة المستند الأصلي'],
 ['سلف موظفين EGP',sum(advances,'amount'),'لا تُكرر كمصروف إذا كانت تُخصم من الرواتب'],
 ['إيراد IG — سجلات المصدر',ig.length,'يشمل صفوفًا تحتاج تنظيف رأس الجدول'],
 ['IG تعليم EGP',sum(ig,'tuition'),'منفصل عن رسوم التسجيل/المواد'],
 ['IG كتب EGP',sum(ig,'books'),'مصدر فقط'],
 ['IG تسجيل EGP',sum(ig,'registration'),'ليس تفصيل مواد OL/AS/A2'],
 ['تكرار record_id للطلاب',duplicateCount(students,'record_id'),'يجب أن يكون صفرًا'],
 ['ملاحظات Audit في ملف المصدر',audit.length,'من صفحة Audit']
];
const wb=Workbook.create(),s=wb.worksheets.add('ملخص المطابقة'),i=wb.worksheets.add('بنود المراجعة');
console.log('REPORT_CREATED');
s.showGridLines=false;i.showGridLines=false;
s.getRange('A1:C1').values=[['Final Production Readiness — Bradford Finance',null,null]];
s.getRange('A2:C2').values=[['تقرير مصدر Read-only — لم تُعدّل بيانات Production',null,null]];
s.getRange('A4:C4').values=[['البند','القيمة','ملاحظة/نطاق']];
s.getRange('A5').write(metrics);
const end=4+metrics.length;s.getRange(`A${end+2}:C${end+2}`).values=[['حالة مقارنة Production','NOT VERIFIED','لا توجد جلسة Supabase Admin/CLI ولا Staging مثبتة؛ ممنوع افتراض التطابق']];
s.getRange(`A${end+3}:C${end+3}`).values=[['مصدر التقرير','MCIS_Application_Data_Master.xlsx','Last modified 2026-09-09؛ يجب مقارنته بلقطة Production مؤرخة']];
i.getRange('A1:D1').values=[['بنود المراجعة',null,null,null]];i.getRange('A3:D3').values=[['الشدة','الجدول/الوحدة','المفتاح','الملاحظة']];
const issues=[...audit.map(x=>[x.severity||'Error',x.table||'—',x.record_key||'—',x.issue||'—']),
 ['FAIL','Production','Supabase access','تعذر استخراج لقطة Production موثقة؛ لا يمكن حساب فروق فعلية.'],
 ['FAIL','Backup/Restore','Staging','لا يوجد إثبات Backup manifest أو Restore Test على Staging.'],
 ['WARNING','Students','2026-2027','المصدر يحتوي 508 سجل سنة/طالب بينما العدد التشغيلي المذكور سابقًا 494؛ يلزم تحديد 14 حالة (منسحب/تقديم فقط/غير نشط).'],
 ['WARNING','Students','cross-year','725 هو مجموع 217 + 508 لسجلين دراسيين، وليس عدد الطلاب الحالي.'],
 ['WARNING','IG','subject detail','ملف المصدر يلخص registration فقط ولا يحتوي تفصيل الجهة/المادة/Session/Entry Type.'],
 ['WARNING','Expenses','documents',`${missingExpenseDocs} بندًا بمستند ناقص/غير واضح حسب النص.`],
 ['INFO','Advances','salary deduction',`${sum(advances,'amount')} EGP سلف مفصولة ويجب منع تكرارها كمصروف عند خصم الرواتب.`]
];i.getRange('A4').write(issues);
console.log('VALUES_WRITTEN');
for(const sh of[s,i]){const u=sh.getUsedRange();u.format.font={name:'Arial',size:10,color:'#172536'};u.format.wrapText=true;u.format.verticalAlignment='center';sh.getRange('A1:D1').format.font={name:'Arial',size:15,bold:true,color:'#0B1F38'};sh.freezePanes.freezeRows(sh===s?4:3)}
console.log('BASE_FORMATTED');
s.getRange('A4:C4').format={fill:'#0B1F38',font:{name:'Arial',bold:true,color:'#FFFFFF'},borders:{preset:'inside',style:'thin',color:'#FFFFFF'}};
i.getRange('A3:D3').format={fill:'#0B1F38',font:{name:'Arial',bold:true,color:'#FFFFFF'},borders:{preset:'inside',style:'thin',color:'#FFFFFF'}};
s.getRange(`B5:B${end}`).format.numberFormat='#,##0.00;[Red](#,##0.00);-';
s.getRange(`A1:A${end+3}`).format.columnWidth=34;s.getRange(`B1:B${end+3}`).format.columnWidth=18;s.getRange(`C1:C${end+3}`).format.columnWidth=58;
i.getRange(`A1:A${3+issues.length}`).format.columnWidth=14;i.getRange(`B1:B${3+issues.length}`).format.columnWidth=20;i.getRange(`C1:C${3+issues.length}`).format.columnWidth=24;i.getRange(`D1:D${3+issues.length}`).format.columnWidth=70;
issues.forEach((x,n)=>{const c=i.getRange(`A${n+4}`);if(x[0]==='FAIL')c.format={fill:'#FEE4E2',font:{name:'Arial',color:'#B42318',bold:true}};else if(x[0]==='WARNING')c.format={fill:'#FFF4D8',font:{name:'Arial',color:'#855D00',bold:true}}});
console.log('FORMATTED');
await fs.mkdir(out,{recursive:true});
const xlsx=await SpreadsheetFile.exportXlsx(wb);await xlsx.save(`${out}/Bradford_Final_Readiness_Reconciliation_2026-09-14.xlsx`);
console.log((await wb.inspect({kind:'region',sheetId:'ملخص المطابقة',range:`A1:C${end+3}`,maxChars:10000})).ndjson);
console.log('EXPORTED');
const preview=await wb.render({sheetName:'ملخص المطابقة',range:`A1:C${end+3}`,scale:.7,format:'png'});await fs.writeFile(`${out}/reconciliation-preview.png`,new Uint8Array(await preview.arrayBuffer()));
console.log('RENDERED');
