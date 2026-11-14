#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
//
// Render the Flatpak manifest template with the current upstream release,
// Electron and production-config values. The rendered file is a build input,
// not something that should be committed.
//
// Usage:
//   node tools/flatpak-render-manifest.mjs \
//     --tag windows/3.46.5382 --commit <sha> --version 3.46.5382 --build 5382 \
//     --electron 43.1.1 --yarn 3.3.1 --config-url <url> --config-sha256 <sha> \
//     [--runtime 26.08] [--base 26.08] [--node 22] [--date YYYY-MM-DD] \
//     [--output flatpak/io.github.nichu42.wire-desktop-linux.yml]

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const appId = 'io.github.nichu42.wire-desktop-linux';
const templatePath = path.join(root, 'flatpak', `${appId}.yml.in`);

const args = process.argv.slice(2);
const options = {};
for (let index = 0; index < args.length; index += 1) {
  const key = args[index];
  if (!key.startsWith('--')) {
    throw new Error(`Unexpected argument: ${key}`);
  }
  const value = args[index + 1];
  if (value === undefined || value.startsWith('--')) {
    throw new Error(`Missing value for ${key}`);
  }
  options[key.slice(2)] = value;
  index += 1;
}

const required = ['tag', 'commit', 'version', 'build', 'electron', 'yarn', 'config-url', 'config-sha256'];
for (const key of required) {
  if (!options[key]) {
    throw new Error(`Missing required option --${key}`);
  }
}

const values = {
  RUNTIME_VERSION: options.runtime || '26.08',
  BASE_VERSION: options.base || '26.08',
  NODE_VERSION: options.node || '22',
  UPSTREAM_TAG: options.tag,
  UPSTREAM_COMMIT: options.commit,
  APP_VERSION: options.version,
  BUILD_NUMBER: options.build,
  BUILD_DATE: options.date || new Date().toISOString().slice(0, 10),
  ELECTRON_VERSION: options.electron,
  YARN_VERSION: options.yarn,
  CONFIG_URL: options['config-url'],
  CONFIG_SHA256: options['config-sha256'],
};

let manifest = fs.readFileSync(templatePath, 'utf8');
for (const [key, value] of Object.entries(values)) {
  manifest = manifest.replaceAll(`@${key}@`, value);
}

const unresolved = manifest.match(/@[A-Z0-9_]+@/g);
if (unresolved) {
  throw new Error(`Unresolved manifest placeholders: ${unresolved.join(', ')}`);
}

const outputPath = path.resolve(
  root,
  options.output || path.join('flatpak', `${appId}.yml`),
);
fs.writeFileSync(outputPath, manifest);
console.log(`flatpak-render-manifest: wrote ${path.relative(root, outputPath)}`);
