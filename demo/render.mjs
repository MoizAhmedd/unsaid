// Renders scene.html to PNG frames by calling its render(t) for each frame, then encodes them.
//   node render.mjs [out.mp4] [fps]
// Needs Google Chrome and `npm i playwright-core` (in this folder).
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(process.argv[2] || join(here, 'demo.mp4'));
const fps = Number(process.argv[3] || 30);
const frames = join(here, 'frames');
rmSync(frames, { recursive: true, force: true });
mkdirSync(frames, { recursive: true });

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(join(here, 'scene.html')).href + '?capture');
await page.evaluate(() => document.fonts.ready);
const duration = await page.evaluate(() => window.DURATION);
const n = Math.round(duration * fps);
for (let i = 0; i < n; i++) {
  await page.evaluate((t) => window.render(t), i / fps);
  await page.screenshot({ path: join(frames, String(i).padStart(5, '0') + '.png') });
  if (i % 60 === 0) process.stdout.write(`frame ${i}/${n}\r`);
}
await browser.close();
console.log(`\n${n} frames → ${out}`);
execFileSync('swift', [join(here, 'encode.swift'), frames, String(fps), out], { stdio: 'inherit' });
rmSync(frames, { recursive: true, force: true });
