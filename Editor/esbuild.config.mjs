import esbuild from 'esbuild';
import { readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';

// Never let removed or renamed assets linger in a package.
await rm('dist', { recursive: true, force: true });

// Build JS bundle
const editorBuild = await esbuild.build({
  entryPoints: ['src/editor.ts'],
  bundle: true,
  metafile: true,
  format: 'iife',
  outfile: 'dist/editor.js',
  minify: true,
  target: ['safari17'],
  sourcemap: false,
  external: ['fs'],
  loader: { '.css': 'css' },
});

// Harper is deliberately kept out of the startup bundle. It is loaded only
// after the editor is ready and proofreading is enabled.
const harperBuild = await esbuild.build({
  entryPoints: ['src/harperRuntime.ts'],
  bundle: true,
  metafile: true,
  format: 'iife',
  outfile: 'dist/harper-runtime.js',
  minify: true,
  target: ['safari17'],
  sourcemap: false,
  external: ['fs'],
});

// Build CSS bundle separately
await esbuild.build({
  entryPoints: ['src/theme.css'],
  bundle: true,
  outfile: 'dist/editor.css',
  minify: true,
});

const harperWasm = await readFile(
  'node_modules/harper.js/dist/harper_wasm_slim_bg.wasm'
);
const compressedHarperWasm = gzipSync(harperWasm, { level: 9 }).toString('base64');
await writeFile(
  'dist/harper-wasm-data.js',
  `window.harperWasmGzipBase64=${JSON.stringify(compressedHarperWasm)};\n`
);

const bundledPackages = new Set();
for (const input of [
  ...Object.keys(editorBuild.metafile.inputs),
  ...Object.keys(harperBuild.metafile.inputs),
]) {
  const match = input.match(/node_modules\/(?:@[^/]+\/[^/]+|[^/]+)/);
  if (match) bundledPackages.add(match[0].slice('node_modules/'.length));
}

const licenseGroups = new Map();
for (const packageName of [...bundledPackages].sort()) {
  const packageRoot = `node_modules/${packageName}`;
  const packageJSON = JSON.parse(await readFile(`${packageRoot}/package.json`, 'utf8'));
  const filenames = await readdir(packageRoot);
  const licenseFilename = filenames.find((name) =>
    /^(licen[sc]e|copying)([-._].*)?$/i.test(name)
  );
  const fallbackLicense = packageName.startsWith('@tiptap/')
    ? '../Packaging/Licenses/Tiptap_LICENSE.md'
    : null;
  const licensePath = licenseFilename
    ? `${packageRoot}/${licenseFilename}`
    : fallbackLicense;
  if (!licensePath) {
    throw new Error(`Bundled package ${packageName} has no license text`);
  }

  const licenseText = (await readFile(licensePath, 'utf8')).trim();
  const label = `${packageJSON.name ?? packageName} ${packageJSON.version ?? 'unknown'}`;
  const existing = licenseGroups.get(licenseText) ?? [];
  existing.push(label);
  licenseGroups.set(licenseText, existing);
}

const notices = [
  'Shakespeare third-party notices',
  '',
  'This file is generated from the packages actually bundled into the editor.',
  ...[...licenseGroups.entries()].flatMap(([licenseText, packages]) => [
    '',
    '='.repeat(72),
    packages.sort().join('\n'),
    '='.repeat(72),
    licenseText,
  ]),
  '',
].join('\n');
await writeFile('dist/THIRD_PARTY_NOTICES.txt', notices);

console.log('Editor bundles built → editor.js + lazy Harper runtime/WASM data + editor.css + notices');
