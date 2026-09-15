import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

const read = file => readFile(new URL(`../${file}`, import.meta.url), 'utf8');

test('mobile configuration has the final identity and local web bundle', async () => {
  const config = JSON.parse(await read('capacitor.config.json'));
  assert.equal(config.appId, 'com.bradforderp.app');
  assert.equal(config.appName, 'Bradford ERP');
  assert.equal(config.webDir, 'www');
  assert.equal(config.server, undefined, 'production must not load a remote server URL');
});

test('mobile bundle is self-contained and exposes required support links', async () => {
  const html = await read('www/index.html');
  assert.match(html, /\.\/supabase-client\.js/);
  assert.doesNotMatch(html, /https:\/\/esm\.sh/);
  assert.match(html, /mobile-bridge\.js/);
  assert.match(html, /Bradford ERP/);
  assert.match(html, /app\.bradforderp\.com/);
  await Promise.all([
    'www/privacy.html',
    'www/support.html',
    'www/account-deletion.html',
    'android/app/src/main/AndroidManifest.xml',
    'ios/App/App/Info.plist'
  ].map(file => access(new URL(`../${file}`, import.meta.url))));
});

test('no privileged backend secret is shipped in mobile output', async () => {
  const files = ['www/index.html', 'www/mobile-bridge.js', 'www/supabase-client.js'];
  for (const file of files) {
    const contents = await read(file);
    assert.doesNotMatch(contents, /service_role|SUPABASE_SERVICE_ROLE_KEY/i, file);
  }
});
