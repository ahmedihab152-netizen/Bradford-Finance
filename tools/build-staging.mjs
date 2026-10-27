import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'staging-dist');
const stagingUrl = process.env.BF_STAGING_SUPABASE_URL;
const stagingKey = process.env.BF_STAGING_SUPABASE_KEY;
if (!stagingUrl || !stagingKey) throw new Error('Missing staging Supabase configuration');

await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
const assets = [
  'index.html', 'admissions.js', 'amany-financial-approvals.js', 'assets-cheques.js',
  'cashier.js', 'dr-amany-dashboard.js', 'hr-operations.js', 'hr-phase6.js',
  'ig-exams.js', 'inventory.js', 'multi-school.js', 'operational-ui.js',
  'procurement.js', 'report-center.js', 'tax-integration.js', 'transport-operations.js'
];
for (const asset of assets) await cp(join(root, asset), join(out, asset));

const productionRef = 'yrdypwatutpceiligfzl';
let html = await readFile(join(out, 'index.html'), 'utf8');
html = html
  .replaceAll(`https://${productionRef}.supabase.co`, stagingUrl)
  .replace(/sb_publishable_[A-Za-z0-9_-]+/, stagingKey)
  .replaceAll(`project_ref:'${productionRef}'`, "project_ref:'jmeyaazpuzhhvvmvjmbd'")
  .replace('<title>Bradford Finance ERP</title>', '<title>Bradford Finance ERP — STAGING</title>')
  .replace('Production Finance Control Center', 'بيئة اختبار خاصة — STAGING')
  .replace('<button id="st" onclick="authTab(\'signup\')">إنشاء حساب</button>', '<button id="st" class="hidden" type="button">إنشاء حساب</button>')
  .replace("let p=await supabase.from('user_profiles')", "let gate=await supabase.from('staging_test_access').select('user_id').eq('user_id',session.user.id).maybeSingle();if(gate.error||!gate.data){await supabase.auth.signOut();msg('هذا الحساب غير مصرح له بدخول بيئة الاختبار.');$('#auth').classList.remove('hidden');$('#app').classList.add('hidden');return}let p=await supabase.from('user_profiles')");
html = html.replace('</head>', `<style>
body::before{content:'STAGING • بيانات اختبار فقط';position:fixed;z-index:99999;top:0;left:0;right:0;background:#9a3412;color:#fff;text-align:center;font-weight:900;padding:6px;letter-spacing:.5px}
body{padding-top:30px}#st,#sf{display:none!important}
</style></head>`);

if (html.includes(productionRef)) throw new Error('Production project reference leaked into staging build');
if (!html.includes('jmeyaazpuzhhvvmvjmbd')) throw new Error('Staging project reference is missing');
await writeFile(join(out, 'index.html'), html, 'utf8');
console.log(`Staging build ready: ${out}`);
