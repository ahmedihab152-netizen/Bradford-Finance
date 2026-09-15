import { build } from 'esbuild';
import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(root, 'www');

if (output !== resolve(root, 'www')) throw new Error('Unexpected mobile output directory.');

await rm(output, { recursive: true, force: true });
await mkdir(resolve(output, 'assets'), { recursive: true });

const appScripts = [
  'admissions.js',
  'assets-cheques.js',
  'cashier.js',
  'hr-operations.js',
  'hr-phase6.js',
  'ig-exams.js',
  'inventory.js',
  'multi-school.js',
  'procurement.js',
  'report-center.js',
  'tax-integration.js',
  'transport-operations.js'
];

let html = await readFile(resolve(root, 'index.html'), 'utf8');
const remoteSupabaseImport = "import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';";
if (!html.includes(remoteSupabaseImport)) {
  throw new Error('Expected Supabase bootstrap was not found; refusing to create a partial mobile bundle.');
}

html = html
  .replace(remoteSupabaseImport, "import {createClient} from './supabase-client.js';")
  .replace('<title>Bradford Finance ERP</title>', '<title>Bradford ERP</title>')
  .replace('resetPasswordForEmail(email,{redirectTo:location.href})', "resetPasswordForEmail(email,{redirectTo:location.protocol==='capacitor:'?'https://app.bradforderp.com/':location.href})")
  .replace('BRADFORD <span>FINANCE ERP</span>', 'BRADFORD <span>ERP</span>')
  .replace('Finance, Audit & Control', 'HR, Finance, Audit & Control')
  .replace('<h2 style="margin:0">Bradford Finance</h2>', '<h2 style="margin:0">Bradford ERP</h2>')
  .replace('Production Finance Control Center', 'HR & Finance Control Center')
  .replace('<div class="brand">BRADFORD <span>FINANCE</span>', '<div class="brand">BRADFORD <span>ERP</span>')
  .replace('</head>', '<meta name="theme-color" content="#0b1f38"><meta name="mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="black-translucent"><link rel="manifest" href="manifest.webmanifest"><link rel="apple-touch-icon" href="assets/icon-192.png"><link rel="stylesheet" href="mobile.css"></head>')
  .replace('</body>', '<script type="module" src="mobile-bridge.js"></script></body>');

await writeFile(resolve(output, 'index.html'), html);
await Promise.all(appScripts.map(file => cp(resolve(root, file), resolve(output, file))));
await Promise.all(['privacy.html', 'support.html', 'account-deletion.html', 'manifest.webmanifest', 'mobile.css'].map(file => cp(resolve(root, 'mobile', file), resolve(output, file))));
await Promise.all(['icon.svg', 'icon-192.png', 'icon-512.png'].map(file => cp(resolve(root, 'mobile/assets', file), resolve(output, 'assets', file))));

await build({
  entryPoints: [resolve(root, 'mobile/supabase-entry.js')],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  minify: true,
  outfile: resolve(output, 'supabase-client.js')
});

await build({
  entryPoints: [resolve(root, 'mobile/mobile-bridge.js')],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  minify: true,
  outfile: resolve(output, 'mobile-bridge.js')
});

console.log('Mobile web bundle created in www/.');
