import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { verifyBackupPackage } from '../tools/verify-backup.mjs';

function packageFor(payload) {
  const serialized = JSON.stringify(payload);
  return {
    manifest: {
      algorithm: 'SHA-256',
      sha256: createHash('sha256').update(serialized, 'utf8').digest('hex'),
      byte_size: Buffer.byteLength(serialized, 'utf8'),
      table_count: Object.keys(payload.tables).length,
      row_count: Object.values(payload.tables).reduce((sum, rows) => sum + rows.length, 0)
    },
    payload
  };
}

test('accepts a package whose manifest matches its production payload', () => {
  const result = verifyBackupPackage(packageFor({ environment: 'PRODUCTION', tables: { students: [{ id: '1' }], expenses: [] } }));
  assert.equal(result.ok, true);
  assert.equal(result.computed.table_count, 2);
  assert.equal(result.computed.row_count, 1);
});

test('rejects payload tampering after the manifest was created', () => {
  const pack = packageFor({ environment: 'PRODUCTION', tables: { students: [{ id: '1' }] } });
  pack.payload.tables.students[0].id = 'changed';
  const result = verifyBackupPackage(pack);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /digest does not match/);
});

test('rejects incorrect counts and byte size even with a matching digest', () => {
  const pack = packageFor({ environment: 'PRODUCTION', tables: { students: [], expenses: [] } });
  pack.manifest.byte_size += 1;
  pack.manifest.table_count = 9;
  pack.manifest.row_count = 4;
  const result = verifyBackupPackage(pack);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /byte_size/);
  assert.match(result.errors.join('\n'), /table_count/);
  assert.match(result.errors.join('\n'), /row_count/);
});

test('rejects malformed table values and non-production labels', () => {
  const payload = { environment: 'STAGING', tables: { students: { id: 'not-an-array' } } };
  const serialized = JSON.stringify(payload);
  const result = verifyBackupPackage({
    manifest: {
      algorithm: 'SHA-256',
      sha256: createHash('sha256').update(serialized, 'utf8').digest('hex'),
      byte_size: Buffer.byteLength(serialized, 'utf8'),
      table_count: 1,
      row_count: 0
    },
    payload
  });
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /Tables must contain arrays/);
  assert.match(result.errors.join('\n'), /not labelled PRODUCTION/);
});
