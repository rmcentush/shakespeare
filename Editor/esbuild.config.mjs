import esbuild from 'esbuild';

// Build JS bundle
await esbuild.build({
  entryPoints: ['src/editor.ts'],
  bundle: true,
  format: 'iife',
  outfile: 'dist/editor.js',
  minify: true,
  target: ['safari17'],
  sourcemap: false,
  loader: { '.css': 'css' },
});

// Build CSS bundle separately
await esbuild.build({
  entryPoints: ['src/theme.css'],
  bundle: true,
  outfile: 'dist/editor.css',
  minify: true,
});

console.log('Editor bundle built → dist/editor.js + dist/editor.css');
