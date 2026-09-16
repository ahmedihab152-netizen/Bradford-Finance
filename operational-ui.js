(()=>{
 Object.assign(access,{
  CASHIER:['dashboard','students','cashier','security','support'],
  TREASURY_MANAGER:['dashboard','approvals','treasury','cheques','banks','reports','security','support'],
  STOREKEEPER:['dashboard','inventory','reports','security','support'],
  PROCUREMENT:['dashboard','procurement','inventory','reports','security','support'],
  APPROVER:['dashboard','approvals','reports','security','support']
 });
 const GROUPS=[
  ['الرئيسية',[['dashboard','Dashboard'],['approvals','الموافقات المعلقة'],['system_check','فحص النظام']]],
  ['الطلاب والتحصيل',[['students','الطلاب وملفاتهم'],['cashier','التحصيل الموحد والإيصالات'],['buses','الباص والنقل'],['uniform','الكتب والزي المدرسي'],['ig','رسوم IG والمواد'],['admissions','التقديم والقبول']]],
  ['المالية والخزنة',[['treasury','الخزنة اليومية والمقبوضات'],['expenses','المصروفات'],['cheques','الشيكات الواردة والصادرة'],['banks','البنوك والمطابقة'],['ledger','القيود والتسويات'],['periods','الفترات والإغلاق']]],
  ['الموارد البشرية',[['hr','الموظفون وعمليات HR']]],
  ['المشتريات والمخازن',[['procurement','المشتريات والموردون'],['inventory','الأصناف والمخازن والجرد']]],
  ['الأصول الثابتة',[['assets','سجل الأصول ودورة الحياة']]],
  ['التقارير',[['reports','مركز التقارير'],['audit','Audit Trail']]],
  ['الإعدادات والإدارة',[['users','المستخدمون والصلاحيات'],['organization','المدارس والفروع'],['security','الأمان وMFA'],['backup','النسخ الاحتياطي'],['support','الدعم والقانونية']]]
 ];
 const allowed=key=>(access[profile?.role]||[]).includes(key);
 const favKey=()=>`bf-favorites:${session?.user?.id||'anon'}`;
 const favorites=()=>{try{return JSON.parse(localStorage.getItem(favKey())||'[]')}catch{return []}};
 const saveFavorites=x=>localStorage.setItem(favKey(),JSON.stringify(x));
 const oldBuildNav=buildNav;
 buildNav=function(){
  if(!profile)return oldBuildNav();
  const fav=favorites(),groups=GROUPS.map(([name,items])=>[name,items.filter(x=>allowed(x[0]))]).filter(x=>x[1].length);
  $('#nav').innerHTML='<div class="nav-search"><input id="screenSearch" aria-label="بحث عن شاشة" placeholder="بحث عن شاشة…"></div>'+groups.map(([name,items],i)=>'<section class="nav-group"><button class="nav-group-title" type="button" aria-expanded="'+(i<2?'true':'false')+'"><span>'+esc(name)+'</span><b>⌄</b></button><div class="nav-group-items '+(i<2?'':'hidden')+'">'+items.map(([k,label])=>'<div class="nav-entry"><button data-p="'+k+'" class="'+(k===page?'on':'')+'">'+esc(label)+'</button><button class="nav-fav" data-fav="'+k+'" title="مفضلة" aria-label="إضافة للمفضلة">'+(fav.includes(k)?'★':'☆')+'</button></div>').join('')+'</div></section>').join('');
  $('#nav').onclick=async e=>{const group=e.target.closest('.nav-group-title');if(group){const box=group.nextElementSibling,open=box.classList.toggle('hidden');group.setAttribute('aria-expanded',String(!open));return}const star=e.target.closest('[data-fav]');if(star){const k=star.dataset.fav,a=favorites(),i=a.indexOf(k);i<0?a.push(k):a.splice(i,1);saveFavorites(a);star.textContent=i<0?'★':'☆';return}const b=e.target.closest('button[data-p]');if(!b)return;page=b.dataset.p;buildNav();await render()};
  $('#screenSearch').oninput=e=>{const q=e.target.value.trim().toLocaleLowerCase('ar');$$('.nav-entry').forEach(x=>x.classList.toggle('hidden',q&&!x.textContent.toLocaleLowerCase('ar').includes(q)));$$('.nav-group-items').forEach(x=>{if(q)x.classList.remove('hidden')})};
 };

 const canWrite=()=>!['READ_ONLY','AUDITOR','DR_AMANY_APPROVER'].includes(profile?.role);
 const addTopChrome=()=>{
  const title=pages[page]||'Bradford ERP',crumb=$('#breadcrumb');if(crumb)crumb.textContent='Bradford ERP / '+title;
  const quick=$('#quickCreate');if(quick){quick.classList.toggle('hidden',!canWrite());quick.onclick=()=>quickCreate()}
 };
 const oldRender=render;
 render=async function(){const out=await oldRender();addTopChrome();installPageActions();return out};

 const topTools=()=>$('#content .sec .tools')||$('#content .sec')||$('#content');
 function addAction(id,label,fn){if(!canWrite()||$('#'+id))return;const b=document.createElement('button');b.id=id;b.className='btn primary';b.textContent='+ '+label;b.onclick=fn;topTools()?.prepend(b)}
 function installPageActions(){
  if(page==='procurement'){const t=window._procTab||'requisitions';if(t==='requisitions')addAction('addPR','طلب شراء',newPurchaseRequisition);if(t==='vendors')addAction('addVendor','مورد',newVendor);if(t==='rfqs')addAction('addQuote','عرض سعر',newQuotation)}
  if(page==='inventory'){const t=window._inventoryTab||'balances';if(t==='items')addAction('addItem','صنف',newInventoryItem);if(t==='movements')addAction('addMovement','حركة مخزن',newInventoryMovement)}
  if(page==='assets')addAction('addAsset','أصل ثابت',newFixedAsset);
  if(page==='cheques')addAction('addCheque','شيك',newCheque);
  if(page==='buses'&&(window._transportOpsTab||'enrollments')==='enrollments')addAction('addBusEnrollment','اشتراك باص',newBusEnrollment);
 }
 const oldShowProcurement=window.showProcurement;window.showProcurement=t=>{oldShowProcurement(t);setTimeout(installPageActions,0)};
 const oldShowInventory=window.showInventory;window.showInventory=t=>{oldShowInventory(t);setTimeout(installPageActions,0)};
 const oldShowTransportOps=window.showTransportOps;window.showTransportOps=t=>{oldShowTransportOps(t);setTimeout(installPageActions,0)};

 function busy(form,on=true){const b=form.querySelector('[type=submit]');if(b){b.disabled=on;b.dataset.label||=b.textContent;b.textContent=on?'جاري الحفظ…':b.dataset.label}}
 async function finish(r,form,message,refresh=true){busy(form,false);if(r.error)return uiToast(r.error.message,'error',8000);closeM();uiToast(message,'success');if(refresh)await render()}
 const form=(id,body,label='حفظ كمسودة')=>'<form id="'+id+'">'+body+'<button class="btn primary w" type="submit">'+label+'</button></form>';
 const f=(id,label,type='text',extra='')=>'<div class="f"><label for="'+id+'">'+label+'</label><input id="'+id+'" type="'+type+'" '+extra+'></div>';
 const select=(id,label,opts)=>'<div class="f"><label for="'+id+'">'+label+'</label><select id="'+id+'">'+opts+'</select></div>';

 window.quickCreate=()=>{const actions=[['طالب','newStudent'],['إيصال موحد','cashierOpenWizard'],['مصروف','newExpense'],['موظف','newHREmployee'],['طلب شراء','newPurchaseRequisition'],['صنف','newInventoryItem'],['حركة مخزن','newInventoryMovement'],['شيك','newCheque'],['أصل ثابت','newFixedAsset']].filter(x=>typeof window[x[1]]==='function');openM('إجراء سريع جديد','<div class="quick-create-grid">'+actions.map(x=>'<button class="card btn ghost" onclick="closeM();'+x[1]+'()">+ '+esc(x[0])+'</button>').join('')+'</div>')};

 window.newPurchaseRequisition=()=>openM('إضافة طلب شراء',form('prCreate','<div class="split">'+f('prDepartment','القسم')+f('prEstimate','القيمة التقديرية EGP','number','min="0" step="0.01" required')+'</div><div class="f"><label>الغرض والمواصفات *</label><textarea id="prPurpose" minlength="3" required></textarea></div><div class="note">يبدأ DRAFT ولا ينشئ قيدًا أو حركة مخزون.</div>'));
 window.newVendor=()=>openM('إضافة مورد',form('vendorCreate','<div class="split">'+f('vendorCode','كود المورد *','text','required maxlength="40"')+f('vendorName','الاسم القانوني *','text','required maxlength="180"')+'</div><div class="split">'+f('vendorTax','الرقم الضريبي')+f('vendorCR','السجل التجاري')+'</div><div class="split">'+f('vendorPhone','الهاتف','tel')+f('vendorEmail','البريد','email')+'</div>'+f('vendorAddress','العنوان')));
 window.newQuotation=()=>{const vendors=window._proc?.vendors||[],prs=window._proc?.requisitions||[];openM('إضافة عرض سعر',form('quoteCreate',select('quoteVendor','المورد *',vendors.map(x=>'<option value="'+x.id+'">'+esc(x.name)+'</option>').join(''))+select('quotePR','طلب الشراء','<option value="">—</option>'+prs.map(x=>'<option value="'+x.id+'">'+esc(x.pr_number)+'</option>').join(''))+'<div class="split">'+f('quoteNo','رقم العرض')+f('quoteDate','تاريخ العرض','date','required')+'</div><div class="split">'+f('quoteAmount','الإجمالي EGP','number','min="0.01" step="0.01" required')+f('quoteValid','صالح حتى','date')+'</div>'+f('quoteDelivery','مدة التوريد بالأيام','number','min="0"')))};
 window.newInventoryItem=()=>{const cats=window._inventory?.items?.map(x=>x.inventory_categories).filter(Boolean)||[];openM('إضافة صنف',form('itemCreate','<div class="split">'+f('itemSku','SKU *','text','required maxlength="80"')+f('itemBarcode','Barcode / QR')+'</div>'+f('itemName','اسم الصنف *','text','required maxlength="180"')+'<div class="split">'+f('itemUnit','الوحدة *','text','required value="EA"')+f('itemSize','المقاس')+'</div><div class="split">'+f('itemMin','الحد الأدنى','number','min="0" step="0.01" value="0"')+f('itemReorder','كمية إعادة الطلب','number','min="0" step="0.01" value="0"')+'</div>'))};
 window.newInventoryMovement=()=>{const d=window._inventory||{},ware=d.warehouses||[],items=d.items||[],wo='<option value="">—</option>'+ware.map(x=>'<option value="'+x.id+'">'+esc(x.warehouse_code+' — '+x.warehouse_name)+'</option>').join('');openM('إضافة حركة مخزن',form('movementCreate',select('moveType','نوع الحركة','<option>RECEIPT</option><option>ISSUE</option><option>RETURN_IN</option><option>RETURN_OUT</option><option>TRANSFER</option><option>ADJUSTMENT_IN</option><option>ADJUSTMENT_OUT</option><option>DAMAGE</option><option>WASTE</option><option>COUNT</option>')+'<div class="split">'+select('moveFrom','المخزن المصدر',wo)+select('moveTo','المخزن الوجهة',wo)+'</div>'+select('moveItem','الصنف *',items.map(x=>'<option value="'+x.id+'">'+esc(x.sku+' — '+x.item_name)+'</option>').join(''))+'<div class="split">'+f('moveQty','الكمية *','number','min="0.001" step="0.001" required')+f('moveCost','سعر الوحدة EGP','number','min="0" step="0.01" value="0"')+'</div>'+f('moveReason','السبب / المرجع')))};
 window.newFixedAsset=()=>openM('إضافة أصل ثابت',form('assetCreate','<div class="split">'+f('assetCode','كود الأصل *','text','required')+f('assetName','اسم الأصل *','text','required')+'</div><div class="split">'+f('assetCategory','التصنيف')+f('assetSerial','الرقم التسلسلي')+'</div><div class="split">'+f('assetDate','تاريخ الشراء','date','required')+f('assetCost','قيمة الشراء EGP','number','min="0.01" step="0.01" required')+'</div><div class="split">'+f('assetLife','العمر الإنتاجي بالأشهر','number','min="1" required')+f('assetRate','الإهلاك السنوي %','number','min="0" max="100" step="0.01" value="20" required')+'</div><div class="split">'+f('assetLocation','الموقع')+f('assetCustodian','المسؤول')+'</div>'));
 window.newCheque=async()=>{const r=await supabase.from('bank_accounts').select('id,bank_name,account_label').order('bank_name');if(r.error)return uiToast(r.error.message,'error');openM('إضافة شيك',form('chequeCreate','<div class="split">'+select('chequeDirection','النوع','<option value="RECEIVABLE">وارد</option><option value="PAYABLE">صادر</option>')+f('chequeNumber','رقم الشيك *','text','required')+'</div>'+select('chequeBank','الحساب البنكي *',(r.data||[]).map(x=>'<option value="'+x.id+'">'+esc(x.bank_name+' — '+x.account_label)+'</option>').join(''))+'<div class="split">'+f('chequeParty','صاحب الشيك / المستفيد *','text','required')+f('chequeAmount','المبلغ EGP *','number','min="0.01" step="0.01" required')+'</div><div class="split">'+f('chequeIssue','تاريخ الإصدار','date','required')+f('chequeDue','تاريخ الاستحقاق','date','required')+'</div>'+f('chequeNotes','ملاحظات')))};
 window.newBusEnrollment=async()=>{const [s,r,v]=await Promise.all([supabase.from('students').select('id,student_code,student_name,grade').eq('status','ACTIVE').order('student_name'),supabase.from('transport_routes').select('id,route_code,route_name,annual_fee_piasters').eq('status','ACTIVE').order('route_name'),supabase.from('transport_vehicles').select('id,vehicle_code,capacity').eq('status','ACTIVE').order('vehicle_code')]);if(s.error||r.error||v.error)return uiToast((s.error||r.error||v.error).message,'error');openM('إضافة اشتراك باص',form('busEnrollmentCreate',select('busStudent','الطالب *',(s.data||[]).map(x=>'<option value="'+x.id+'">'+esc(x.student_code+' — '+x.student_name+' — '+(x.grade||''))+'</option>').join(''))+'<div class="split">'+select('busRoute','المسار *',(r.data||[]).map(x=>'<option value="'+x.id+'" data-fee="'+x.annual_fee_piasters+'">'+esc(x.route_code+' — '+x.route_name)+'</option>').join(''))+select('busVehicle','المركبة','<option value="">—</option>'+(v.data||[]).map(x=>'<option value="'+x.id+'">'+esc(x.vehicle_code+' — '+x.capacity+' مقعد')+'</option>').join(''))+'</div><div class="split">'+f('busPickup','نقطة الركوب *','text','required')+f('busGuardian','هاتف ولي الأمر','tel')+'</div><div class="split">'+f('busYear','السنة الدراسية *','text','required value="2026-2027"')+f('busFee','الرسوم EGP *','number','min="0" step="0.01" required')+'</div>'))};

 document.addEventListener('submit',async e=>{
  const x=e.target;if(!['prCreate','vendorCreate','quoteCreate','itemCreate','movementCreate','assetCreate','chequeCreate','busEnrollmentCreate'].includes(x.id))return;e.preventDefault();busy(x,true);let r;
  if(x.id==='prCreate')r=await supabase.rpc('create_purchase_requisition_draft',{p_department:$('#prDepartment').value,p_purpose:$('#prPurpose').value,p_estimated_total_piasters:Math.round(Number($('#prEstimate').value)*100),p_idempotency_key:crypto.randomUUID()});
  if(x.id==='vendorCreate')r=await supabase.from('vendors').insert({vendor_code:$('#vendorCode').value.trim(),name:$('#vendorName').value.trim(),legal_name:$('#vendorName').value.trim(),tax_id:$('#vendorTax').value.trim()||null,commercial_register:$('#vendorCR').value.trim()||null,phone:$('#vendorPhone').value.trim()||null,email:$('#vendorEmail').value.trim()||null,address:$('#vendorAddress').value.trim()||null,created_by:session.user.id});
  if(x.id==='quoteCreate')r=await supabase.from('vendor_quotations').insert({vendor_id:$('#quoteVendor').value,requisition_id:$('#quotePR').value||null,quotation_number:$('#quoteNo').value.trim()||null,quotation_date:$('#quoteDate').value,amount_piasters:Math.round(Number($('#quoteAmount').value)*100),valid_until:$('#quoteValid').value||null,delivery_days:Number($('#quoteDelivery').value)||null,status:'DRAFT',created_by:session.user.id});
  if(x.id==='itemCreate')r=await supabase.from('inventory_items').insert({sku:$('#itemSku').value.trim(),barcode:$('#itemBarcode').value.trim()||null,item_name:$('#itemName').value.trim(),unit:$('#itemUnit').value.trim(),size:$('#itemSize').value.trim()||null,minimum_quantity:Number($('#itemMin').value)||0,reorder_quantity:Number($('#itemReorder').value)||0,created_by:session.user.id,updated_by:session.user.id});
  if(x.id==='movementCreate')r=await supabase.rpc('create_inventory_movement_draft',{p_movement_type:$('#moveType').value,p_from_warehouse:$('#moveFrom').value||null,p_to_warehouse:$('#moveTo').value||null,p_item:$('#moveItem').value,p_quantity:Number($('#moveQty').value),p_unit_cost_piasters:Math.round(Number($('#moveCost').value||0)*100),p_reason:$('#moveReason').value,p_idempotency_key:crypto.randomUUID()});
  if(x.id==='assetCreate')r=await supabase.from('fixed_assets').insert({asset_code:$('#assetCode').value.trim(),asset_name:$('#assetName').value.trim(),category:$('#assetCategory').value.trim()||null,asset_tag:$('#assetSerial').value.trim()||null,purchase_date:$('#assetDate').value,acquisition_cost_piasters:Math.round(Number($('#assetCost').value)*100),useful_life_months:Number($('#assetLife').value),depreciation_rate:Number($('#assetRate').value)/100,location:$('#assetLocation').value.trim()||null,responsibility:'NEEDS_REVIEW',notes:$('#assetCustodian').value.trim()||null,created_by:session.user.id,updated_by:session.user.id});
  if(x.id==='chequeCreate')r=await supabase.from('cheques').insert({cheque_number:$('#chequeNumber').value.trim(),bank_account_id:$('#chequeBank').value,direction:$('#chequeDirection').value==='RECEIVABLE'?'RECEIVED':'ISSUED',beneficiary:$('#chequeParty').value.trim(),amount_piasters:Math.round(Number($('#chequeAmount').value)*100),issue_date:$('#chequeIssue').value,due_date:$('#chequeDue').value,status:'DRAFT',notes:$('#chequeNotes').value.trim()||null,created_by:session.user.id,updated_by:session.user.id});
  if(x.id==='busEnrollmentCreate')r=await supabase.from('transport_enrollments').insert({student_id:$('#busStudent').value,route_id:$('#busRoute').value,vehicle_id:$('#busVehicle').value||null,pickup_point:$('#busPickup').value.trim(),guardian_phone:$('#busGuardian').value.trim()||null,academic_year:$('#busYear').value.trim(),fee_piasters:Math.round(Number($('#busFee').value)*100),status:'ACTIVE',created_by:session.user.id,updated_by:session.user.id});
  await finish(r,x,'تم الحفظ بنجاح وظهر السجل في القائمة.');
 });

 // Administrator-only account policy: the public sign-up form is not a production entry point.
 const signupTab=$('#st');if(signupTab)signupTab.remove();const signupForm=$('#sf');if(signupForm)signupForm.remove();
 addTopChrome();
})();
