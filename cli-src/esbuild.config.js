import { build } from 'esbuild';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

await build({
  entryPoints: ['src/index.ts'],
  bundle: true,
  platform: 'node',
  target: 'node20',
  format: 'cjs',
  outfile: resolve(__dirname, '..', 'bin', 'cw'),
  banner: {
    js: '#!/usr/bin/env node',
  },
  external: [],
  minify: false,
  sourcemap: true,
});

console.log('Built → bin/cw');
