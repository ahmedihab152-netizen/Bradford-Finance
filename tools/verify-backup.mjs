import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const sha256 = value => createHash('sha256').update(value, 'utf8').digest('hex');

export function verifyBackupPackage(pack) {
  const errors = [];
  if (!pack || typeof pack !== 'object' || Array.isArray(pack)) return { ok: false, errors: ['Backup package must be a JSON object.'] };
  const { manifest, payload } = pack;
  if (!manifest || typeof manifest !== 'object') return { ok: false, errors: ['Backup manifest is missing.'] };
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return { ok: false, errors: ['Backup payload is missing.'] };
  if (manifest.algorithm !== 'SHA-256') errors.push('Manifest algorithm must be SHA-256.');
  if (!payload.tables || typeof payload.tables !== 'object' || Array.isArray(payload.tables)) errors.push('Payload tables object is missing.');

  const serialized = JSON.stringify(payload);
  const digest = sha256(serialized);
  const byteSize = Buffer.byteLength(serialized, 'utf8');
  const tables = payload.tables && typeof payload.tables === 'object' && !Array.isArray(payload.tables) ? payload.tables : {};
  const tableNames = Object.keys(tables);
  const invalidTables = tableNames.filter(name => !Array.isArray(tables[name]));
  if (invalidTables.length) errors.push(`Tables must contain arrays: ${invalidTables.join(', ')}.`);
  const rowCount = tableNames.reduce((total, name) => total + (Array.isArray(tables[name]) ? tables[name].length : 0), 0);

  if (String(manifest.sha256 || '').toLowerCase() !== digest) errors.push('SHA-256 digest does not match the payload.');
  if (Number(manifest.byte_size) !== byteSize) errors.push('Manifest byte_size does not match the UTF-8 payload size.');
  if (Number(manifest.table_count) !== tableNames.length) errors.push('Manifest table_count does not match the payload.');
  if (Number(manifest.row_count) !== rowCount) errors.push('Manifest row_count does not match the payload.');
  if (payload.environment && payload.environment !== 'PRODUCTION') errors.push('Backup payload is not labelled PRODUCTION.');

  return {
    ok: errors.length === 0,
    errors,
    computed: { sha256: digest, byte_size: byteSize, table_count: tableNames.length, row_count: rowCount }
  };
}

export async function verifyBackupFile(file) {
  let pack;
  try {
    pack = JSON.parse(await readFile(file, 'utf8'));
  } catch (error) {
    return { ok: false, errors: [`Cannot read valid JSON: ${error.message}`] };
  }
  return verifyBackupPackage(pack);
}

async function main() {
  const file = process.argv[2];
  if (!file) {
    console.error('Usage: node tools/verify-backup.mjs <backup.json>');
    process.exitCode = 2;
    return;
  }
  const result = await verifyBackupFile(file);
  if (!result.ok) {
    console.error('BACKUP VERIFICATION FAILED');
    result.errors.forEach(error => console.error(`- ${error}`));
    process.exitCode = 1;
    return;
  }
  console.log('BACKUP VERIFICATION PASSED');
  console.log(JSON.stringify(result.computed, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
