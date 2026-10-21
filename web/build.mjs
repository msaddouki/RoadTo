// Builds the site into dist/: pages, RoadTo's map style (from the
// pipeline), the app's font, the bundled scripts and the legal pages (from
// docs/beta). Everything is served from the site itself; only the map tiles
// come from OpenFreeMap.
//   npm run build            (needs Python 3 for the style)
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import * as esbuild from 'esbuild';
import { marked } from 'marked';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const dist = join(here, 'dist');

rmSync(dist, { recursive: true, force: true });
cpSync(join(here, 'public'), dist, { recursive: true });

// Map style, day and night, and its sprite: the same as the app's.
const styles = join(dist, 'styles');
execFileSync('python3', ['-m', 'roadto_pipeline.web_style', '--out', styles], {
  env: { ...process.env, PYTHONPATH: join(root, 'pipeline') },
  stdio: 'inherit',
});
for (const f of readdirSync(styles).filter((f) => f.endsWith('.json'))) {
  const path = join(styles, f);
  // Relative to the pages, which all sit at the site's root.
  writeFileSync(path, readFileSync(path, 'utf8').replaceAll('@ROADTO_SPRITE@', 'styles/sprites/roadto'));
}

// The app's own face (SIL OFL 1.1).
const fonts = join(dist, 'fonts');
mkdirSync(fonts, { recursive: true });
for (const f of ['AtkinsonHyperlegibleNext-Regular.ttf', 'AtkinsonHyperlegibleNext-Bold.ttf', 'AtkinsonHyperlegibleNext-ExtraBold.ttf', 'OFL.txt']) {
  cpSync(join(root, 'app/assets/fonts', f), join(fonts, f));
}

await esbuild.build({
  entryPoints: {
    index: join(here, 'src/pages/index.js'),
    carte: join(here, 'src/pages/carte.js'),
    lieu: join(here, 'src/pages/lieu.js'),
  },
  bundle: true,
  minify: true,
  format: 'esm',
  splitting: true,
  target: ['es2022'],
  outdir: join(dist, 'assets'),
  legalComments: 'linked',
});
// MapLibre 6 starts its worker from ./maplibre-gl-worker.mjs next to the
// script that loads it (import.meta.url), and the worker imports the shared code.
for (const f of ['maplibre-gl.css', 'maplibre-gl-worker.mjs', 'maplibre-gl-shared.mjs']) {
  cpSync(join(here, 'node_modules/maplibre-gl/dist', f), join(dist, 'assets', f));
}

// Legal pages, from the drafts in docs/beta.
const template = readFileSync(join(here, 'src/legal.html'), 'utf8');
for (const [md, out] of [
  ['politique-de-confidentialite.md', 'confidentialite.html'],
  ['conditions-d-utilisation.md', 'cgu.html'],
]) {
  const source = join(root, 'docs/beta', md);
  if (!existsSync(source)) {
    console.warn(`missing ${source}: ${out} not built`);
    continue;
  }
  const text = readFileSync(source, 'utf8');
  const html = marked.parse(text).replaceAll('href="politique-de-confidentialite.md"', 'href="confidentialite.html"');
  const title = /^# (.+)$/m.exec(text)?.[1] ?? 'RoadTo';
  writeFileSync(join(dist, out), template.replace('{{title}}', title).replace('{{body}}', html));
}
console.log(`site -> ${dist}`);
