(()=>{
 const digest=async f=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))].map(x=>x.toString(16).padStart(2,'0')).join('');
 const readSheet=async f=>{if(f.name.toLowerCase().endsWith('.csv')){const ls=(await f.text()).split(/\r?\n/).filter(Boolean),h=(ls.shift()||'').split(',').map(x=>x.trim());return ls.map(z=>Object.fromEntries(z.split(',').map((v,j)=>[h[j],v.trim()])))}const X=await import('https://cdn.jsdelivr.net/npm/xlsx@0.18.5/+esm'),w=X.read(await f.arrayBuffer());return X.utils.sheet_to_json(w.Sheets[w.SheetNames[0]],{defval:''})};
 const get=(r,...ks)=>{for(const k of ks){const hit=Object.keys(r).find(x=>x.trim().toLowerCase()===k.toLowerCase());if(hit&&r[hit]!==''&&r[hit]!=null)return r[hit]}return null};
 window.previewEmployeeImport=()=>{const i=document.querySelector('#hrImportFile');i.accept='.csv,.xlsx,.xls';i.onchange=async()=>{const f=i.files?.[0];if(!f)return;try{uiToast('جاري التحقق Server-side…','info');const raw=await readSheet(f),rows=raw.map(r=>({employee_code:String(get(r,'Employee Code','employee_code','Code')||'').trim(),full_name:String(get(r,'Full Name','Name','full_name')||'').trim(),department:get(r,'Department'),job_title:get(r,'Position','Job Title','job_title'),hire_date:get(r,'Appointment Date','Hire Date','hire_date')||null,national_id:get(r,'National ID','national_id')||null,phone:get(r,'Phone','phone')||null,contract_type:get(r,'Employment Type','contract_type')||null,social_insurance_number:get(r,'Insurance Number','social_insurance_number')||null,experience_years:String(get(r,'Years of Experience','experience_years')||''),school_division:get(r,'Division','school_division')||null})),hash=await digest(f),p=await supabase.rpc('hr_preview_employee_import',{p_file_name:f.name,p_sha256:hash,p_rows:rows});if(p.error)throw p.error;const [b,details]=await Promise.all([supabase.from('hr_import_batches').select('*').eq('id',p.data).single(),supabase.from('hr_import_rows').select('row_number,employee_code,validation_status,validation_errors').eq('batch_id',p.data).neq('validation_status','VALID').limit(100)]);if(b.error)throw b.error;window.hrImportBatch=p.data;const x=b.data,invalid=Number(x.validation_result?.invalid_rows||0);openM('Preview استيراد الموظفين — تحقق الخادم','<div class="grid cards">'+metric('إجمالي الصفوف',n(x.preview_rows),'SHA-256 محفوظ')+metric('صالح',n(x.valid_rows),'لم يُستورد بعد','green')+metric('مكرر',n(x.duplicate_rows),'employee_code','red')+metric('غير صالح',n(invalid),'لن يُستورد','red')+'</div><div class="tablewrap"><table class="tbl"><thead><tr><th>الصف</th><th>الكود</th><th>الحالة</th><th>الأخطاء</th></tr></thead><tbody>'+((details.data||[]).map(z=>'<tr><td>'+n(z.row_number)+'</td><td>'+esc(z.employee_code||'—')+'</td><td>'+esc(z.validation_status)+'</td><td>'+esc((z.validation_errors||[]).join('، '))+'</td></tr>').join('')||'<tr><td colspan="4">لا توجد أخطاء.</td></tr>')+'</tbody></table></div>'+(profile.role==='HR_MANAGER'&&x.valid_rows?'<button class="btn primary w" onclick="confirmEmployeeImport()">اعتماد ريهام واستيراد السجلات الصالحة</button>':'<div class="note orange">تم حفظ Preview فقط؛ الاعتماد النهائي للاستيراد متاح لريهام.</div>')+'<div class="note">لا يتضمن الاستيراد رواتب أو بدلات أو خصومات.</div>')}catch(e){uiToast(e.message||e,'error',9000)}};i.value='';i.click()};
 window.confirmEmployeeImport=async()=>{if(!window.hrImportBatch)return uiToast('لا توجد دفعة Preview.','warning');const r=await supabase.rpc('hr_confirm_employee_import',{p_batch:window.hrImportBatch});if(r.error)return uiToast(r.error.message,'error',9000);window.hrImportBatch=null;closeM();uiToast('اعتمدت ريهام استيراد '+r.data+' موظفًا.','success',7000);await openHRModule('employees')};
 window.previewBioImport=()=>{if(!(window.bioDeviceRows||[]).length)return uiToast('سجّل جهاز بصمة حقيقيًا أولًا.','warning');const i=document.createElement('input');i.type='file';i.accept='.csv,.xlsx,.xls';i.onchange=async()=>{const f=i.files?.[0];if(!f)return;try{const raw=await readSheet(f),rows=raw.map(r=>({device_user_id:String(get(r,'User ID','device_user_id','Employee ID')||'').trim(),punch_time:String(get(r,'Punch Time','punch_time','Date Time')||'').trim(),punch_type:String(get(r,'Punch Type','punch_type')||'').trim()||null})),hash=await digest(f),device=window.bioDeviceRows[0],p=await supabase.rpc('hr_preview_biometric_import',{p_device:device.id,p_file_name:f.name,p_sha256:hash,p_rows:rows});if(p.error)throw p.error;const b=await supabase.from('biometric_import_batches').select('*').eq('id',p.data).single();if(b.error)throw b.error;window.bioImportBatch=p.data;const x=b.data;openM('Preview البصمة — تحقق الخادم','<div class="grid cards">'+metric('صالح',n(x.accepted_count),'لم يُعتمد','green')+metric('مكرر',n(x.duplicate_count),'لن يتكرر','amber')+metric('مرفوض/غير مرتبط',n(x.rejected_count),'يحتاج ربط','red')+'</div>'+(profile.role==='HR_MANAGER'&&x.accepted_count?'<button class="btn primary w" onclick="confirmBioImport()">اعتماد ريهام لسجلات البصمة</button>':'<div class="note orange">Preview فقط؛ ريهام وحدها تؤكد الاستيراد.</div>')+'<div class="note">السجلات الخام لا تدخل المرتب. يجب حساب الحضور ومراجعة واعتماد الحركة أولًا.</div>')}catch(e){uiToast(e.message||e,'error',9000)}};i.click()};
 window.confirmBioImport=async()=>{if(!window.bioImportBatch)return uiToast('لا توجد دفعة Preview.','warning');const r=await supabase.rpc('hr_confirm_biometric_import',{p_batch:window.bioImportBatch});if(r.error)return uiToast(r.error.message,'error',9000);window.bioImportBatch=null;closeM();uiToast('تم اعتماد '+r.data+' سجل بصمة خام دون تأثير على المرتب.','success',7000);await openHRModule('biometric')};
})();

// Device-independent attendance spreadsheet import. The browser only parses the
// selected file; validation, deduplication, confirmation and calculation remain
// server-side and never post financial entries.
(()=>{
 const fileDigest=async f=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))].map(x=>x.toString(16).padStart(2,'0')).join('');
 const normHeader=value=>String(value??'').trim().toLowerCase().replace(/[._\-\/\\]+/g,' ').replace(/\s+/g,' ');
 const key=(headers,names)=>headers.find(h=>names.map(normHeader).includes(normHeader(h)))||'';
 const excelLocalISO=(value,X)=>{
  if(value instanceof Date&&!Number.isNaN(value.valueOf()))return value.toISOString();
  if(typeof value==='number'){
   const d=X.SSF.parse_date_code(value);if(!d)return '';
   return new Date(d.y,d.m-1,d.d,d.H||0,d.M||0,Math.floor(d.S||0)).toISOString();
  }
  const text=String(value??'').trim();if(!text)return '';
  const m=text.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
  if(m){const y=Number(m[3])<100?2000+Number(m[3]):Number(m[3]);return new Date(y,Number(m[2])-1,Number(m[1]),Number(m[4]||0),Number(m[5]||0),Number(m[6]||0)).toISOString()}
  const d=new Date(text);return Number.isNaN(d.valueOf())?'':d.toISOString();
 };
 const combineDateTime=(dateValue,timeValue,X)=>{
  if(timeValue==null||String(timeValue).trim()==='')return excelLocalISO(dateValue,X);
  let d;
  if(typeof dateValue==='number'){const p=X.SSF.parse_date_code(dateValue);if(p)d=new Date(p.y,p.m-1,p.d)}
  if(!d){const iso=excelLocalISO(dateValue,X);if(iso)d=new Date(iso)}
  if(!d||Number.isNaN(d.valueOf()))return '';
  if(timeValue instanceof Date&&!Number.isNaN(timeValue.valueOf()))d.setHours(timeValue.getHours(),timeValue.getMinutes(),timeValue.getSeconds(),0);
  else if(typeof timeValue==='number'){const p=X.SSF.parse_date_code(timeValue);if(p)d.setHours(p.H||0,p.M||0,Math.floor(p.S||0),0)}
  else {const m=String(timeValue).trim().match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?/);if(!m)return '';d.setHours(Number(m[1]),Number(m[2]),Number(m[3]||0),0)}
  return d.toISOString();
 };
 const punchType=v=>{const x=String(v??'').trim().toLowerCase();if(['in','check in','check-in','دخول','0'].includes(x))return'IN';if(['out','check out','check-out','خروج','1'].includes(x))return'OUT';return'AUTO'};
 const parseSheet=async file=>{
  const X=await import('https://cdn.jsdelivr.net/npm/xlsx@0.18.5/+esm');
  const wb=X.read(await file.arrayBuffer(),{cellDates:true});
  const sheet=wb.Sheets[wb.SheetNames[0]],rows=X.utils.sheet_to_json(sheet,{defval:'',raw:true});
  return {X,rows,headers:Object.keys(rows[0]||{})};
 };
 const detectColumns=headers=>({
  employee:key(headers,['employee code','employee_code','code','user id','userid','employee id','enroll number','ac-no.','ac no','acno','no.','person id','رقم الموظف','كود الموظف']),
  datetime:key(headers,['punch time','punch_time','date time','datetime','timestamp','التاريخ والوقت','وقت البصمة']),
  date:key(headers,['date','attendance date','work date','punch date','التاريخ']),
  time:key(headers,['clock','punch','attendance time','punch time only','وقت','الوقت']),
  type:key(headers,['punch type','punch_type','state','direction','check type','نوع البصمة','الحالة']),
  clockIn:key(headers,['clock in','check in','check-in','time in','actual in','in time','sign in','دخول','وقت الدخول']),
  clockOut:key(headers,['clock out','check out','check-out','time out','actual out','out time','sign out','خروج','وقت الخروج'])
 });
 const normalizedPunches=p=>{
  const c=p.columns,out=[];
  for(const r of p.rows){const employee_code=String(r[c.employee]??'').trim();
   if(c.date&&(c.clockIn||c.clockOut)){
    if(c.clockIn&&String(r[c.clockIn]??'').trim()!=='')out.push({employee_code,punch_time:combineDateTime(r[c.date],r[c.clockIn],p.X),punch_type:'IN'});
    if(c.clockOut&&String(r[c.clockOut]??'').trim()!=='')out.push({employee_code,punch_time:combineDateTime(r[c.date],r[c.clockOut],p.X),punch_type:'OUT'});
   }else out.push({employee_code,punch_time:c.datetime?excelLocalISO(r[c.datetime],p.X):combineDateTime(r[c.date],r[c.time],p.X),punch_type:c.type?punchType(r[c.type]):'AUTO'});
  }
  return out.filter(r=>r.employee_code||r.punch_time);
 };
 window.previewBioImport=()=>{
  const input=document.createElement('input');input.type='file';input.accept='.csv,.xlsx,.xls,.pdf';
  input.onchange=async()=>{const file=input.files?.[0];if(!file)return;
   if(file.name.toLowerCase().endsWith('.pdf'))return openM('ملف البصمة','<div class="note orange">يمكن الاحتفاظ بملف PDF كمستند، لكنه لا يصلح لحساب الحضور والمرتبات بصورة آمنة. صدّر نفس التقرير من برنامج البصمة بصيغة Excel أو CSV ثم اختره هنا.</div>');
   try{
    uiToast('جاري قراءة الشيت محليًا…','info');const parsed=await parseSheet(file);
    if(!parsed.rows.length)throw new Error('الشيت لا يحتوي على سجلات.');
    const columns=detectColumns(parsed.headers),hasEvent=columns.employee&&(columns.datetime||(columns.date&&columns.time)),hasDaily=columns.employee&&columns.date&&(columns.clockIn||columns.clockOut);
    if(!hasEvent&&!hasDaily)throw new Error('تعذر التعرف تلقائيًا على أعمدة الشيت. الأعمدة الموجودة: '+parsed.headers.join('، '));
    window.pendingAttendanceFile={file,...parsed,columns,sha256:await fileDigest(file)};
    uiToast('تم التعرف على الشيت تلقائيًا؛ جاري فحص '+n(parsed.rows.length)+' صف…','info',6000);
    await window.submitAttendanceFilePreview();
   }catch(e){uiToast(e.message||e,'error',9000)}
  };input.click();
 };
 window.submitAttendanceFilePreview=async()=>{const p=window.pendingAttendanceFile;if(!p)return uiToast('اختر شيت البصمة أولًا.','warning');
  const rows=normalizedPunches(p),format=p.file.name.split('.').pop().toUpperCase(),mapping={automatic:true,...p.columns};
  if(!rows.length)return uiToast('لم يعثر النظام على أي بصمات قابلة للقراءة داخل الشيت.','error',9000);
  try{uiToast('جاري التحقق Server-side…','info');const call=await supabase.rpc('hr_preview_attendance_file',{p_file_name:p.file.name,p_sha256:p.sha256,p_source_format:format,p_column_mapping:mapping,p_rows:rows});if(call.error)throw call.error;
   const [batch,issues]=await Promise.all([supabase.from('hr_attendance_file_batches').select('*').eq('id',call.data).single(),supabase.from('hr_attendance_file_rows').select('row_number,employee_code,punch_time,validation_status,validation_errors').eq('batch_id',call.data).neq('validation_status','VALID').order('row_number').limit(200)]);if(batch.error)throw batch.error;if(issues.error)throw issues.error;
   window.attendanceFileBatch=call.data;const b=batch.data;
   openM('نتيجة معاينة شيت البصمة','<div class="grid cards">'+metric('إجمالي',n(b.total_rows),'')+metric('صالح',n(b.valid_rows),'لم يُعتمد بعد','green')+metric('مكرر',n(b.duplicate_rows),'لن يتكرر','amber')+metric('غير مرتبط',n(b.unlinked_rows),'راجع كود الموظف','red')+metric('غير صالح',n(b.invalid_rows),'راجع التاريخ والكود','red')+'</div><div class="tablewrap"><table class="tbl"><thead><tr><th>صف</th><th>الكود</th><th>وقت البصمة</th><th>الحالة</th><th>السبب</th></tr></thead><tbody>'+((issues.data||[]).map(x=>'<tr><td>'+n(x.row_number)+'</td><td>'+esc(x.employee_code||'—')+'</td><td>'+esc(x.punch_time||'—')+'</td><td>'+esc(x.validation_status)+'</td><td>'+esc((x.validation_errors||[]).join('، ')||'—')+'</td></tr>').join('')||'<tr><td colspan="5">كل الصفوف صالحة.</td></tr>')+'</tbody></table></div>'+(profile.role==='HR_MANAGER'&&b.valid_rows?'<button class="btn primary w" onclick="confirmAttendanceFileImport()">تأكيد وحساب الحضور</button>':'<div class="note orange">المعاينة فقط؛ التأكيد متاح لمديرة HR صاحبة BIOMETRIC_MANAGER.</div>')+'<div class="note">التأكيد يحسب الدقائق وينشئ مسودات فقط. لا يعتمد مرتبًا ولا ينشئ قيدًا ماليًا.</div>');
  }catch(e){uiToast(e.message||e,'error',9000)}
 };
 window.confirmAttendanceFileImport=async()=>{if(!window.attendanceFileBatch)return uiToast('لا توجد معاينة جاهزة.','warning');
  try{const r=await supabase.rpc('hr_finalize_attendance_file',{p_batch:window.attendanceFileBatch});if(r.error)throw r.error;const x=r.data||{},p=x.policy||{};window.attendanceFileBatch=null;window.pendingAttendanceFile=null;closeM();uiToast('تم استيراد '+n(x.imported_punches)+' بصمة وحساب '+n(x.attendance_days)+' يوم، وتسجيل '+n(p.auto_holidays||0)+' يوم بلا بصمات كإجازة. كل الخصومات مسودات للمراجعة.','success',10000);await openHRModule('biometric')}catch(e){uiToast(e.message||e,'error',9000)}
 };
})();
