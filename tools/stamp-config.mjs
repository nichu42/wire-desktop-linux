#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
//
// Stamp the production runtime configuration into an upstream wire-desktop
// checkout. Mirrors upstream's bin/build-tools/lib/commonConfig.ts so the
// packaged app reports itself as "Wire" / "production" with the right
// version, instead of the repository's internal development defaults.
//
// Usage: BUILD_NUMBER=5382 node tools/stamp-config.mjs (from the repo root)

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const wireJsonPath = path.join(root, 'electron', 'wire.json');
const packageJsonPath = path.join(root, 'package.json');
const envPath = path.join(root, '.env.defaults');

function fail(message) {
  console.error(`stamp-config: ${message}`);
  process.exit(1);
}

function parseEnvFile(text) {
  const parsed = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    const match = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) {
      continue;
    }
    let value = match[2];
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    parsed[match[1]] = value;
  }
  return parsed;
}

if (!fs.existsSync(wireJsonPath)) {
  fail(`missing ${wireJsonPath}`);
}
if (!fs.existsSync(envPath)) {
  fail(`missing ${envPath}; did "yarn configure" run?`);
}

const defaults = JSON.parse(fs.readFileSync(wireJsonPath, 'utf8'));
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
const env = parseEnvFile(fs.readFileSync(envPath, 'utf8'));

const read = (name, fallback) => process.env[name] || env[name] || fallback;
const buildNumber = process.env.BUILD_NUMBER;
if (!buildNumber) {
  fail('BUILD_NUMBER is not set');
}

const baseVersion = String(defaults.version || packageJson.version || '0').replace(/\.0$/, '');
const version = `${baseVersion}.${buildNumber}`;
const name = read('APP_NAME', defaults.name);
const maximumAccounts = String(read('APP_MAXIMUM_ACCOUNTS', defaults.maximumAccounts));

const config = {
  ...defaults,
  aboutReleasesUrl: read('URL_ABOUT_RELEASES', defaults.aboutReleasesUrl),
  aboutUpdatesUrl: read('URL_ABOUT_UPDATES', defaults.aboutUpdatesUrl),
  adminUrl: read('URL_ADMIN', defaults.adminUrl),
  appBase: read('APP_BASE', defaults.appBase),
  buildDir: defaults.buildDir || 'wrap/build',
  buildNumber: String(buildNumber),
  copyright: read('APP_COPYRIGHT', defaults.copyright),
  customProtocolName: read('APP_CUSTOM_PROTOCOL_NAME', defaults.customProtocolName),
  description: read('APP_DESCRIPTION', defaults.description),
  distDir: defaults.distDir || 'wrap/dist',
  electronDirectory: defaults.electronDirectory || 'electron',
  enableAsar: process.env.ENABLE_ASAR === 'false' ? false : defaults.enableAsar,
  environment: 'production',
  legalUrl: read('URL_LEGAL', defaults.legalUrl),
  licensesUrl: read('URL_LICENSES', defaults.licensesUrl),
  maximumAccounts,
  name,
  nameShort: read('APP_NAME_SHORT', defaults.nameShort),
  privacyUrl: read('URL_PRIVACY', defaults.privacyUrl),
  raygunApiKey: read('RAYGUN_API_KEY', defaults.raygunApiKey),
  supportUrl: read('URL_SUPPORT', defaults.supportUrl),
  updateUrl: read('WIN_URL_UPDATE', defaults.updateUrl),
  version,
  websiteUrl: read('URL_WEBSITE', defaults.websiteUrl),
};

fs.writeFileSync(wireJsonPath, `${JSON.stringify(config, null, 2)}\n`);
fs.writeFileSync(
  packageJsonPath,
  `${JSON.stringify({...packageJson, productName: name, version}, null, 2)}\n`,
);

console.log(
  `stamp-config: ${name} ${version} (${config.environment}) from ${path.basename(envPath)}`,
);
