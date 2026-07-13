import esbuild from 'esbuild';
import { copyFile } from 'node:fs/promises';

// Build JS bundle
await esbuild.build({
  entryPoints: ['src/editor.ts'],
  bundle: true,
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
await esbuild.build({
  entryPoints: ['src/harperRuntime.ts'],
  bundle: true,
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

await copyFile('node_modules/harper.js/LICENSE', 'dist/Harper_LICENSE.txt');
await copyFile(
  'node_modules/harper.js/dist/harper_wasm_slim_bg.wasm',
  'dist/harper_wasm_slim_bg.wasm'
);

console.log('Editor bundles built → editor.js + lazy Harper runtime/WASM + editor.css');
