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
    // The Flatpak sources live at the build root, not in the upstream tree;
    // keep the exclude so a future in-tree copy can never reach app.asar.
    '!flatpak{,/**}',
  ],
  linux: {
    ...base.linux,
    target: ['dir'],
  },
  afterPack: path.join(__dirname, 'after-pack.cjs'),
};
