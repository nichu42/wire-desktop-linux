// SPDX-License-Identifier: GPL-3.0-only
//
// electron-builder configuration for the unofficial Linux AppImage.
// Version-aware for electron-builder 25 (flat desktop entry) and 26+
// (desktop entry under `entry`).

const fs = require('fs');
const path = require('path');

const packageJsonPath = path.join(__dirname, '..', 'package.json');
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
const builderVersion = require('electron-builder/package.json').version;
const builderMajor = Number.parseInt(builderVersion.split('.')[0], 10);

const revision = process.env.RELEASE_REVISION ? `-r${process.env.RELEASE_REVISION}` : '';
const artifactName = `Wire-\${version}${revision}_\${arch}.\${ext}`;

const desktopEntry = {
  Name: 'Wire',
  GenericName: 'Secure messenger',
  Comment: packageJson.description || 'The most secure collaboration platform.',
  Categories: 'Network;InstantMessaging;Chat;VideoConference;',
  Keywords: 'chat;encrypt;e2e;messenger;videocall;',
  MimeType: 'x-scheme-handler/wire;',
  StartupWMClass: 'Wire',
  Version: '1.1',
};
const desktop = builderMajor >= 26 ? {entry: desktopEntry} : desktopEntry;

/** @type {import('electron-builder').Configuration} */
module.exports = {
  appId: 'io.github.nichu42.WireDesktop',
  productName: packageJson.productName || 'Wire',
  // Keep X-AppImage-Version equal to the app version; otherwise electron-builder
  // appends the BUILD_NUMBER env var (3.46.5382.5382).
  buildVersion: packageJson.version,
  artifactName,
  asar: true,
  npmRebuild: false,
  removePackageScripts: true,
  publish: null,
  directories: {
    buildResources: 'resources',
    output: 'wrap/dist',
  },
  files: [
    // Do not add a positive '**/*' pattern here: it pulls in the dev electron
    // package (an entire second Electron distribution) plus its download
    // helpers. The default patterns already limit node_modules to production
    // dependencies.
    // Root-relative excludes only: never strip matching directories from
    // node_modules (e.g. @wireapp/commons/lib/config).
    '!.yarn{,/**}',
    '!electron/src{,/**}',
    '!electron/renderer/src{,/**}',
    '!bin{,/**}',
    '!jenkins{,/**}',
    '!tools{,/**}',
    '!e2e-tests{,/**}',
    '!.github{,/**}',
    '!docs{,/**}',
    '!patches{,/**}',
    '!app-config{,/**}',
    '!resources{,/**}',
    '!config{,/**}',
    '!.env*',
    '!.upstream-commit',
    '!node_modules/electron{,/**}',
    '!node_modules/@electron-internal{,/**}',
    '!node_modules/registry-js{,/**}',
    '!node_modules/objc-js{,/**}',
    '!**/*.map',
    '!**/*.d.ts',
    '!**/*.test*',
  ],
  extraFiles: [
    {
      from: 'resources/io.github.nichu42.WireDesktop.metainfo.xml',
      to: 'usr/share/metainfo/io.github.nichu42.WireDesktop.metainfo.xml',
    },
  ],
  linux: {
    target: ['AppImage'],
    executableName: 'wire-desktop',
    category: 'Network;InstantMessaging;Chat;VideoConference',
    icon: 'resources/icons',
    desktop,
  },
  appImage: {
    artifactName,
    desktop,
    // electron-builder 26.18 defaults to --no-sandbox when toolsets.appimage
    // is unset; never hardcode that in the desktop entry.
    executableArgs: [],
  },
  afterPack: 'tools/after-pack.cjs',
};
