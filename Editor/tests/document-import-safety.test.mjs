import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sanitizer = readFileSync(resolve(editorRoot, 'src/sanitize.ts'), 'utf8');

test('document imports cannot activate remote or embedded web content', () => {
  assert.match(
    sanitizer,
    /script, style, noscript, iframe, object, embed, link, meta, base/,
    'active and externally loaded document elements must be removed'
  );
  assert.ok(
    sanitizer.includes("(name === 'style' && /url\\s*\\(/i.test(attribute.value))"),
    'inline CSS URLs must be removed before imported content enters the editor'
  );
  assert.match(
    sanitizer,
    /name === 'srcdoc'/,
    'embedded HTML attributes must be removed'
  );
  assert.ok(
    sanitizer.includes('stripUnsafeURLs(parsed.body)'),
    'document image and link URLs must pass the shared local-only policy'
  );
});
