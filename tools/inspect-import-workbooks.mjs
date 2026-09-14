import {FileBlob,SpreadsheetFile} from 'file:///C:/Users/mostafa/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';
const root='C:/Users/mostafa/Downloads/';
const defaults=['عدد الطلبة حتي 5-9-2026.xlsx','الخزينه.xlsx','تحليل سداد مصروفات الطلبة 2027-2026.xlsx','خزينه د-اماني 2026-2027.xlsx','طلبة عام 25-26.xlsx','طلبة عام 26-27.xlsx','MCIS_Application_Data_Master.xlsx','Mid Cairo Data base 2026-2027(1) M.xlsx'];
const files=process.argv.slice(2).length?process.argv.slice(2):defaults;
for(const file of files){
 const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(root+file));
 const sheets=JSON.parse('['+(await wb.inspect({kind:'sheet',include:'id,name',maxChars:20000})).ndjson.trim().split('\n').join(',')+']');
 console.log('\nFILE',file);
 for(const meta of sheets){
  const ws=wb.resolve(meta.id),used=ws.getUsedRange(true),v=used?.values||[];
  console.log(JSON.stringify({sheet:meta.name,range:meta.range,rows:v.length,cols:v.reduce((m,r)=>Math.max(m,r.length),0),sample:v.slice(0,8).map(r=>r.slice(0,18))}));
 }
}
