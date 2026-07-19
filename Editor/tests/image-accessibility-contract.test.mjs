import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const images = fs.readFileSync(new URL('../src/images.ts', import.meta.url), 'utf8');
const sync = fs.readFileSync(new URL('../src/docSync.ts', import.meta.url), 'utf8');

test('images preserve explicit descriptions and decorative intent', () => {
  assert.match(images, /setSelectedImageAlt/);
  assert.match(images, /data-image-decorative/);
  assert.match(images, /Image without a description/);
  assert.match(sync, /imageDecorative: selectedImageAttrs\.decorative === true/);
});
