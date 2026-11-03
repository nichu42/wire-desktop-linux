#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
//
// electron-builder does not write AppImage update information, but its static
// runtime has a 1024-byte .upd_info section. Write the Gear Lever/AppImageUpdate
// string in place without changing the file length, so the squashfs offset and
// appended blockmap remain valid.
//
// Usage: node tools/embed-updateinfo.mjs <AppImage> <update-info>

import {execFileSync} from 'node:child_process';
import fs from 'node:fs';

const [appimageArg, updateInfo] = process.argv.slice(2);
if (!appimageArg || !updateInfo) {
  console.error('usage: embed-updateinfo.mjs <AppImage> <update-info>');
  process.exit(2);
}

const appimage = appimageArg;
const readelf = execFileSync('readelf', ['-S', '--wide', appimage], {
  encoding: 'utf8',
  env: {...process.env, LC_ALL: 'C'},
});
const line = readelf
  .split('\n')
  .find((entry) => /\]\s+\.upd_info\s+/.test(entry));
if (!line) {
  console.error('embed-updateinfo: .upd_info section not found in the runtime');
  process.exit(1);
}

const parts = line.trim().split(/\s+/);
// [Nr] Name Type Address Off Size ES Flg Lk Inf Al
const offset = Number.parseInt(parts[4], 16);
const size = Number.parseInt(parts[5], 16);
const payload = Buffer.from(`${updateInfo}\0`, 'utf8');

if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(size) || size < payload.length) {
  console.error(
    `embed-updateinfo: bad section (offset=${parts[4]}, size=${parts[5]}, payload=${payload.length})`,
  );
  process.exit(1);
}

const fd = fs.openSync(appimage, 'r+');
try {
  fs.writeSync(fd, Buffer.alloc(size), 0, size, offset);
  fs.writeSync(fd, payload, 0, payload.length, offset);
} finally {
  fs.closeSync(fd);
}

let embedded = '';
try {
  embedded = execFileSync(appimage, ['--appimage-updateinfo'], {encoding: 'utf8'}).trim();
} catch {
  const dump = execFileSync('readelf', ['--string-dump=.upd_info', '--wide', appimage], {
    encoding: 'utf8',
    env: {...process.env, LC_ALL: 'C'},
  });
  embedded = dump;
}
if (!embedded.includes(updateInfo)) {
  console.error(`embed-updateinfo: verification failed, got ${JSON.stringify(embedded)}`);
  process.exit(1);
}

console.log(`embed-updateinfo: ${updateInfo}`);
