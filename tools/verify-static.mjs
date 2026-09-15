import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = path.resolve(import.meta.dirname, '..');
const failures = [];
const pass = message => console.log(`PASS ${message}`);
const fail = message => failures.push(message);
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

for (const file of ['cashier.js', 'hr-operations.js', 'ig-exams.js', 'admissions.js']) {
  try {
    new vm.Script(read(file), { filename: file });
    pass(`${file} parses as JavaScript`);
  } catch (error) {
    fail(`${file}: ${error.message}`);
  }
}

const html = read('index.html');
const inlineScripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/gi)]
  .filter(match => !/\bsrc\s*=/.test(match[1]) && !/\btype\s*=\s*["']module/.test(match[1]) && match[2].trim());
inlineScripts.forEach((match, index) => {
  try {
    new vm.Script(match[2], { filename: `index-inline-${index + 1}.js` });
  } catch (error) {
    fail(`index inline script ${index + 1}: ${error.message}`);
  }
});
if (!failures.some(item => item.startsWith('index inline'))) pass(`${inlineScripts.length} classic index.html scripts parse`);

const sourceFiles = ['index.html', 'cashier.js', 'hr-operations.js', 'ig-exams.js', 'admissions.js'];
const combinedSource = sourceFiles.map(file => `${file}\n${read(file)}`).join('\n');
const forbidden = [
  [/service[_-]?role/i, 'service-role reference in frontend'],
  [/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/, 'private key in frontend'],
  [/postgres(?:ql)?:\/\/[^\s'"<>]+:[^\s'"<>]+@/i, 'database credential URL in frontend'],
  [/(?:localhost|127\.0\.0\.1)/i, 'localhost reference in production frontend']
];
for (const [pattern, label] of forbidden) pattern.test(combinedSource) ? fail(label) : pass(`no ${label}`);

const indexVariants = fs.readdirSync(root).filter(name => /^index(?:\s|\(|-).*\.html$/i.test(name));
indexVariants.length ? fail(`extra index variants: ${indexVariants.join(', ')}`) : pass('one canonical index.html entry point');

const migrationDir = path.join(root, 'supabase', 'migrations');
const migrations = fs.readdirSync(migrationDir).filter(name => name.endsWith('.sql')).sort();
const timestamps = migrations.map(name => name.slice(0, 14));
if (new Set(timestamps).size !== timestamps.length) fail('duplicate migration timestamps');
else pass(`${migrations.length} unique additive migration files`);

const migrationSql = migrations.map(name => read(path.join('supabase', 'migrations', name))).join('\n').toLowerCase();
const createdPublicTables = [...migrationSql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z0-9_]+)/g)].map(match => match[1]);
const dynamicallyProtected = new Set();
for (const block of migrationSql.matchAll(/do\s+\$\$([\s\S]*?)\$\$/g)) {
  if (!block[1].includes("alter table public.%i enable row level security")) continue;
  for (const list of block[1].matchAll(/array\s*\[([^\]]+)\]/g)) {
    for (const item of list[1].matchAll(/'([a-z0-9_]+)'/g)) dynamicallyProtected.add(item[1]);
  }
}
const missingRls = [...new Set(createdPublicTables)].filter(table =>
  !migrationSql.includes(`alter table public.${table} enable row level security`) && !dynamicallyProtected.has(table));
missingRls.length ? fail(`created public tables without an RLS enable statement: ${missingRls.join(', ')}`) : pass('all locally created public tables have an RLS enable statement');

for (const bundle of ['cashier.js', 'hr-operations.js', 'ig-exams.js', 'admissions.js']) {
  const escaped = bundle.replace('.', '\\.');
  const reference = new RegExp(`${escaped}\\?v=[^"']+`);
  reference.test(html) ? pass(`${bundle} is cache-versioned`) : fail(`${bundle} is not cache-versioned`);
}

const cashierSource = read('cashier.js');
if (/\b(?:alert|prompt|confirm)\s*\(/.test(cashierSource)) fail('cashier uses a native browser dialog');
else pass('cashier uses application dialogs and toasts');

const hrSource = read('hr-operations.js');
if (/\b(?:alert|prompt|confirm)\s*\(/.test(hrSource)) fail('HR operations use a native browser dialog');
else pass('HR operations use application dialogs and toasts');

const igSource = read('ig-exams.js');
if (/\b(?:alert|prompt|confirm)\s*\(/.test(igSource)) fail('IG exams use a native browser dialog');
else pass('IG exams use application dialogs and toasts');
for (const token of ['OL','AS','A2','FULL_A_LEVEL','FIRST_ENTRY','RETAKE','REMARK','LATE_ENTRY','create_ig_exam_payment_batch']) {
  if (!igSource.includes(token) && !migrationSql.includes(token.toLowerCase())) fail(`IG exams missing ${token}`);
}
if (!failures.some(item => item.startsWith('IG exams missing'))) pass('IG exam levels, entry types and unified receipt RPC are present');

const admissionsSource = read('admissions.js');
if (/\b(?:alert|prompt|confirm)\s*\(/.test(admissionsSource)) fail('Admissions uses a native browser dialog');
else pass('Admissions uses application dialogs and toasts');
for (const token of ['admission_applications','transition_admission','enroll_admission_application','ADMISSIONS_REVIEWER','ADMISSIONS_APPROVER']) {
  if (!admissionsSource.includes(token) && !migrationSql.includes(token.toLowerCase())) fail(`Admissions missing ${token}`);
}
if (!failures.some(item => item.startsWith('Admissions missing'))) pass('Admissions workflow and enrollment seams are present');

if (!html.includes('window.forgot=()=>openM(') || /window\.forgot=async\(\)=>\{let e=prompt/.test(html)) fail('password recovery does not use the application dialog');
else pass('password recovery uses the application dialog');
if (!/id="modal"[^>]*role="dialog"[^>]*aria-modal="true"/.test(html)) fail('application modal lacks dialog accessibility attributes');
else pass('application modal exposes dialog accessibility attributes');
if (!html.includes('autocomplete="one-time-code"')) fail('MFA challenge lacks one-time-code autocomplete');
else pass('MFA challenge supports one-time-code entry');
if (/async function finAction\([^\n]*\b(?:alert|prompt|confirm)\s*\(/.test(html)) fail('financial approval workflow uses a native browser dialog');
else pass('financial approval workflow uses application dialogs and toasts');

const requiredReleaseDocs = [
  'docs/ADMIN_GUIDE.md',
  'docs/ROLE_GUIDES.md',
  'docs/UAT_CHECKLIST.md',
  'docs/RELEASE_NOTES.md',
  'docs/CURRENT_ERD.md',
  'docs/DATA_DICTIONARY.md',
  'docs/BACKUP_RESTORE.md'
];
const missingReleaseDocs = requiredReleaseDocs.filter(file => !fs.existsSync(path.join(root, file)));
missingReleaseDocs.length ? fail(`missing release documents: ${missingReleaseDocs.join(', ')}`) : pass('required release documents are present');

const workflowFile = path.join(root, '.github', 'workflows', 'verify.yml');
if (!fs.existsSync(workflowFile)) {
  fail('static verification workflow is missing');
} else {
  const workflow = fs.readFileSync(workflowFile, 'utf8');
  if (!/permissions:\s*\n\s*contents:\s*read/.test(workflow)) fail('verification workflow does not declare read-only contents permission');
  else pass('verification workflow uses read-only repository permission');
  if (!/run:\s*npm test/.test(workflow)) fail('verification workflow does not run the repository test command');
  else pass('verification workflow runs npm test');
}

if (failures.length) {
  console.error('\nSTATIC VERIFICATION FAILED');
  failures.forEach(item => console.error(`- ${item}`));
  process.exit(1);
}
console.log('\nSTATIC VERIFICATION PASSED');
