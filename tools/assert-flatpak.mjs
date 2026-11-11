#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
//
// Assert that the installed Flatpak tree is the production build we intended.
// This runs inside the flatpak-builder sandbox after the app has been installed
// into /app, so failures stop the build before a bundle/repo is produced.
//
// Usage: node tools/assert-flatpak.mjs <app-root> <app-id> <version> <electron>

import {createRequire} from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const asar = require('@electron/asar');
const {FuseV1Options, getCurrentFuseWire} = require('@electron/fuses');

const FUSE_DISABLE = 48;
const FUSE_ENABLE = 49;

const [rootArg, appId, expectedVersion, expectedElectron] = process.argv.slice(2);
if (!rootArg || !appId || !expectedVersion || !expectedElectron) {
  console.error('usage: assert-flatpak.mjs <app-root> <app-id> <version> <electron>');
  process.exit(2);
}

const root = path.resolve(rootArg);
const appDir = path.join(root, 'wire-desktop');
const asarPath = path.join(appDir, 'resources', 'app.asar');
const executable = path.join(appDir, 'wire-desktop');
const failures = [];

const check = (condition, message) => {
  if (!condition) {
    failures.push(message);
  }
};

const readAsarJson = (name) => JSON.parse(asar.extractFile(asarPath, name).toString('utf8'));
const read = (file) => fs.readFileSync(file, 'utf8');
const exists = (file) => fs.existsSync(file);
const isExecutable = (file) => {
  try {
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
};
const directorySize = (dir) => {
  let total = 0;
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      total += directorySize(entryPath);
    } else if (entry.isFile()) {
      total += fs.statSync(entryPath).size;
    }
  }
  return total;
};

check(exists(asarPath), `missing ${asarPath}`);
if (exists(asarPath)) {
  const wireJson = readAsarJson('electron/wire.json');
  const packageJson = readAsarJson('package.json');
  check(wireJson.name === 'Wire', `wire.json name is ${wireJson.name}`);
  check(wireJson.environment === 'production', `wire.json environment is ${wireJson.environment}`);
  check(wireJson.version === expectedVersion, `wire.json version is ${wireJson.version}`);
  check(packageJson.productName === 'Wire', `productName is ${packageJson.productName}`);
  check(packageJson.version === expectedVersion, `package version is ${packageJson.version}`);
  check(packageJson.scripts === undefined, 'packaged package.json still contains scripts');

  const entries = asar.listPackage(asarPath);
  check(!entries.some((entry) => entry.endsWith('.map')), 'asar contains source maps');
  check(!entries.some((entry) => entry.endsWith('.d.ts')), 'asar contains TypeScript declarations');
  check(!entries.some((entry) => /^\/electron\/src\//.test(entry)), 'asar contains electron/src');
  check(
    !entries.some((entry) => /^\/(tools|patches|e2e-tests|flatpak)\//.test(entry)),
    'asar contains build tooling',
  );
  check(
    entries.includes('/node_modules/@wireapp/commons/lib/config/CommonConfig.js'),
    'asar is missing @wireapp/commons config',
  );
  check(
    !entries.some((entry) => /^\/node_modules\/(electron|@electron-internal)\//.test(entry)),
    'asar contains the dev-only electron package',
  );
  check(
    !entries.some((entry) =>
      /^\/node_modules\/(webpack|eslint|jest|mocha|prettier|electron-builder)\//.test(entry),
    ),
    'asar contains development tooling',
  );
  check(
    !exists(path.join(appDir, 'resources', 'app.asar.unpacked', 'node_modules', 'electron')),
    'app.asar.unpacked contains the dev electron package',
  );
}

check(isExecutable(executable), `missing executable ${executable}`);
if (exists(path.join(appDir, 'version'))) {
  const electronVersion = read(path.join(appDir, 'version')).trim();
  check(
    electronVersion === expectedElectron,
    `bundled Electron is ${electronVersion}, expected ${expectedElectron}`,
  );
}

if (exists(executable)) {
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
}

const desktopPath = path.join(root, 'share', 'applications', `${appId}.desktop`);
check(exists(desktopPath), `missing ${desktopPath}`);
if (exists(desktopPath)) {
  const desktop = read(desktopPath);
  check(desktop.includes('MimeType=x-scheme-handler/wire;'), 'desktop file has no wire:// handler');
  check(
    new RegExp(`^Exec=wire-desktop-flatpak(?: %U)?$`, 'm').test(desktop),
    'desktop Exec is not wire-desktop-flatpak',
  );
  check(desktop.includes(`Icon=${appId}`), 'desktop Icon does not use the app ID');
  check(desktop.includes('StartupWMClass=Wire'), 'desktop StartupWMClass is not Wire');
  check(!desktop.includes('--no-sandbox'), 'desktop file contains --no-sandbox');
}

const metainfoPath = path.join(root, 'share', 'metainfo', `${appId}.metainfo.xml`);
check(exists(metainfoPath), `missing ${metainfoPath}`);
if (exists(metainfoPath)) {
  const metainfo = read(metainfoPath);
  check(metainfo.includes(`<id>${appId}</id>`), 'metainfo ID does not match the app ID');
  check(
    metainfo.includes(`<launchable type="desktop-id">${appId}.desktop</launchable>`),
    'metainfo launchable does not match the desktop file',
  );
  check(
    metainfo.includes(`<release version="${expectedVersion}"`),
    'metainfo release version does not match',
  );
  check(metainfo.includes('<project_license>GPL-3.0-only</project_license>'), 'metainfo license is wrong');
  check(!metainfo.includes('%VERSION%') && !metainfo.includes('%DATE%'), 'metainfo placeholders remain');
}

const iconPath = path.join(root, 'share', 'icons', 'hicolor', '256x256', 'apps', `${appId}.png`);
check(exists(iconPath), `missing ${iconPath}`);
if (exists(iconPath)) {
  check(fs.statSync(iconPath).size > 1024, 'app icon is suspiciously small');
}

const wrapperPath = path.join(root, 'bin', 'wire-desktop-flatpak');
check(exists(wrapperPath), `missing ${wrapperPath}`);
check(isExecutable(wrapperPath), 'Flatpak wrapper is not executable');
if (exists(wrapperPath)) {
  const wrapper = read(wrapperPath);
  check(wrapper.includes('zypak-wrapper'), 'wrapper does not use zypak-wrapper');
  check(!wrapper.includes('--no-sandbox'), 'wrapper contains --no-sandbox');
}

const licensePath = path.join(root, 'share', 'licenses', appId, 'LICENSE');
check(exists(licensePath), `missing ${licensePath}`);

for (const forbidden of ['.upd_info', '.zsync', 'apparmor.profile']) {
  check(!exists(path.join(root, forbidden)), `Flatpak contains AppImage artifact ${forbidden}`);
}

const size = directorySize(appDir);
check(size > 40 * 1024 * 1024, `application is suspiciously small (${size} bytes)`);
check(size < 600 * 1024 * 1024, `application is suspiciously large (${size} bytes)`);

if (failures.length > 0) {
  console.error('Flatpak assertions failed:');
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log(
  `Flatpak OK: Wire ${expectedVersion}, Electron ${expectedElectron}, ${(size / 1024 / 1024).toFixed(1)} MiB`,
);
