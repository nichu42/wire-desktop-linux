#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
//
// Assert that the extracted AppImage is the production build we intended.
// Usage: node tools/assert-artifact.mjs <squashfs-root> <version> <electron> <appimage>

import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
const asar = require('@electron/asar');
const {FuseV1Options, getCurrentFuseWire} = require('@electron/fuses');
// Values from @electron/fuses' FuseState enum; 1.8.x does not re-export it.
const FUSE_DISABLE = 48;
const FUSE_ENABLE = 49;

const [dirArg, expectedVersion, expectedElectron, appimageArg] = process.argv.slice(2);
if (!dirArg || !expectedVersion || !expectedElectron || !appimageArg) {
  console.error('usage: assert-artifact.mjs <squashfs-root> <version> <electron> <appimage>');
  process.exit(2);
}

const root = path.resolve(dirArg);
const appimage = path.resolve(appimageArg);
const asarPath = path.join(root, 'resources', 'app.asar');
const executable = path.join(root, 'wire-desktop');

const failures = [];
const check = (condition, message) => {
  if (!condition) {
    failures.push(message);
  }
};
const readAsarJson = (name) => JSON.parse(asar.extractFile(asarPath, name).toString('utf8'));

const wireJson = readAsarJson('electron/wire.json');
const packageJson = readAsarJson('package.json');
check(wireJson.name === 'Wire', `wire.json name is ${wireJson.name}`);
check(
  wireJson.environment === 'production',
  `wire.json environment is ${wireJson.environment}`,
);
check(wireJson.version === expectedVersion, `wire.json version is ${wireJson.version}`);
check(packageJson.productName === 'Wire', `productName is ${packageJson.productName}`);
check(packageJson.version === expectedVersion, `package version is ${packageJson.version}`);
check(packageJson.scripts === undefined, 'packaged package.json still contains scripts');

const entries = asar.listPackage(asarPath);
check(!entries.some((entry) => entry.endsWith('.map')), 'asar contains source maps');
check(!entries.some((entry) => entry.endsWith('.d.ts')), 'asar contains TypeScript declarations');
check(
  !entries.some((entry) => /^\/electron\/src\//.test(entry)),
  'asar contains electron/src',
);
check(!entries.some((entry) => /^\/(tools|patches|e2e-tests)\//.test(entry)), 'asar contains build tooling');
check(
  entries.includes('/node_modules/@wireapp/commons/lib/config/CommonConfig.js'),
  'asar is missing @wireapp/commons config (over-broad files exclusion)',
);
check(
  !entries.some((entry) => /^\/node_modules\/(electron|@electron-internal)\//.test(entry)),
  'asar contains the dev-only electron package',
);
// `typescript` is a production dependency of @wireapp/protocol-messaging, so it
// also ships in upstream's own builds; flag only real build tooling.
check(
  !entries.some((entry) =>
    /^\/node_modules\/(webpack|eslint|jest|mocha|prettier|electron-builder)\//.test(entry),
  ),
  'asar contains development tooling',
);
check(
  !fs.existsSync(path.join(root, 'resources', 'app.asar.unpacked', 'node_modules', 'electron')),
  'app.asar.unpacked contains the dev electron package',
);

const desktopFile = fs
  .readdirSync(root)
  .find((entry) => entry.endsWith('.desktop') && fs.statSync(path.join(root, entry)).isFile());
check(Boolean(desktopFile), 'no desktop file in AppImage');
if (desktopFile) {
  const desktop = fs.readFileSync(path.join(root, desktopFile), 'utf8');
  check(desktop.includes('MimeType=x-scheme-handler/wire;'), 'desktop file has no wire:// handler');
  // electron-builder's AppImage entrypoint is AppRun; other Linux targets use the
  // executable name. Accept both so the assertion survives packaging changes.
  check(/^Exec=(AppRun|.*wire-desktop)(\s|$)/m.test(desktop), 'desktop Exec is not AppRun/wire-desktop');
  check(desktop.includes('StartupWMClass=Wire'), 'desktop StartupWMClass is not Wire');
}

check(
  fs.existsSync(path.join(root, '.DirIcon')) || fs.existsSync(path.join(root, 'wire-desktop.png')),
  'no icon in AppImage',
);

const electronVersionFile = path.join(root, 'version');
if (fs.existsSync(electronVersionFile)) {
  const electronVersion = fs.readFileSync(electronVersionFile, 'utf8').trim();
  check(
    electronVersion === expectedElectron,
    `bundled Electron is ${electronVersion}, expected ${expectedElectron}`,
  );
}

const fuses = await getCurrentFuseWire(executable);
const expectedFuses = {
  [FuseV1Options.RunAsNode]: FUSE_DISABLE,
  [FuseV1Options.EnableCookieEncryption]: FUSE_ENABLE,
  [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: FUSE_DISABLE,
  [FuseV1Options.EnableNodeCliInspectArguments]: FUSE_DISABLE,
  [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: FUSE_DISABLE,
  [FuseV1Options.OnlyLoadAppFromAsar]: FUSE_ENABLE,
};
for (const [option, expected] of Object.entries(expectedFuses)) {
  check(fuses[option] === expected, `fuse ${option} is ${fuses[option]}, expected ${expected}`);
}

const expectedUpdateInfo =
  'gh-releases-zsync|nichu42|wire-desktop-linux|latest|Wire-*x86_64.AppImage.zsync';
let updateInfo = '';
try {
  updateInfo = execFileSync(appimage, ['--appimage-updateinfo'], {encoding: 'utf8'}).trim();
} catch {
  const readelf = execFileSync('readelf', ['--string-dump=.upd_info', '--wide', appimage], {
    encoding: 'utf8',
    env: {...process.env, LC_ALL: 'C'},
  });
  updateInfo = readelf;
}
check(updateInfo.includes(expectedUpdateInfo), `update info is ${JSON.stringify(updateInfo)}`);

const zsyncPath = `${appimage}.zsync`;
if (fs.existsSync(zsyncPath)) {
  const header = fs.readFileSync(zsyncPath, 'utf8').slice(0, 4096);
  const match = header.match(/SHA-1:\s*([0-9a-f]{40})/);
  const actual = crypto.createHash('sha1').update(fs.readFileSync(appimage)).digest('hex');
  check(Boolean(match), '.zsync has no SHA-1 header');
  if (match) {
    check(match[1] === actual, '.zsync SHA-1 does not match the AppImage');
  }
} else {
  failures.push(`missing ${zsyncPath}`);
}

const size = fs.statSync(appimage).size;
check(size > 40 * 1024 * 1024, `AppImage is suspiciously small (${size} bytes)`);
check(size < 200 * 1024 * 1024, `AppImage is suspiciously large (${size} bytes)`);

if (failures.length > 0) {
  console.error('Artifact assertions failed:');
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log(
  `Artifact OK: Wire ${expectedVersion}, Electron ${expectedElectron}, ${(size / 1024 / 1024).toFixed(1)} MiB`,
);
