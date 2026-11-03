// SPDX-License-Identifier: GPL-3.0-only
//
// Flip the same Electron fuses upstream Wire uses for its production builds.
// `EnableEmbeddedAsarIntegrityValidation` is deliberately left disabled: it is
// a macOS/Windows feature with no effect on Linux.

const path = require('path');
const {flipFuses, FuseVersion, FuseV1Options} = require('@electron/fuses');

module.exports = async function afterPack(context) {
  const executableName =
    context.packager.platformSpecificBuildOptions.executableName || 'wire-desktop';
  const executablePath = path.join(context.appOutDir, executableName);

  await flipFuses(executablePath, {
    version: FuseVersion.V1,
    [FuseV1Options.RunAsNode]: false,
    [FuseV1Options.EnableCookieEncryption]: true,
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
    [FuseV1Options.EnableNodeCliInspectArguments]: false,
    [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: false,
    [FuseV1Options.OnlyLoadAppFromAsar]: true,
  });

  console.log(`after-pack: flipped Electron fuses in ${executablePath}`);
};
