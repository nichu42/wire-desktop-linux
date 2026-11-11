// SPDX-License-Identifier: GPL-3.0-only
//
// electron-builder configuration for the Flatpak build. It reuses the AppImage
// config for asar, fuses and the production file excludes, but only produces an
// unpacked application directory. Flatpak packages that directory itself.

const path = require('path');

// The Flatpak build copies this file next to tools/electron-builder.config.cjs,
// so the relative require resolves to the AppImage base config.
const base = require('./electron-builder.config.cjs');

/** @type {import('electron-builder').Configuration} */
module.exports = {
  ...base,
  appId: 'io.github.nichu42.wire-desktop-linux',
  // The AppImage metainfo is installed by the AppImage packaging, not here.
  extraFiles: [],
  files: [
    ...base.files,
    // The Flatpak packaging files are copied into the upstream tree; never
    // pack them into app.asar.
    '!flatpak{,/**}',
  ],
  linux: {
    ...base.linux,
    target: ['dir'],
  },
  afterPack: path.join(__dirname, 'after-pack.cjs'),
};
