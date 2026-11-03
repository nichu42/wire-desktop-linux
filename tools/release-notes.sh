#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Generate GitHub release notes from build-info.json and the upstream
# changelog captured by the build job.
#
# Environment:
#   BUILD_INFO      path to build-info.json (default: artifacts/build-info.json)
#   CHANGELOG_FILE  path to changelog.txt    (default: artifacts/changelog.txt)
#   REPO            owner/repo               (default: nichu42/wire-desktop-linux)

set -euo pipefail

BUILD_INFO="${BUILD_INFO:-artifacts/build-info.json}"
CHANGELOG_FILE="${CHANGELOG_FILE:-artifacts/changelog.txt}"
REPO="${REPO:-nichu42/wire-desktop-linux}"

if [ ! -f "$BUILD_INFO" ]; then
  echo "release-notes: missing $BUILD_INFO" >&2
  exit 1
fi

info() {
  jq -r --arg key "$1" '.[$key] // empty' "$BUILD_INFO"
}

TAG="$(info upstream_tag)"
COMMIT="$(info upstream_commit)"
ELECTRON="$(info electron)"
UPSTREAM_ELECTRON="$(info upstream_electron)"
BUILDER="$(info electron_builder)"
RUNTIME_PATCH="$(info runtime_patch)"
REVISION="$(info revision)"
EOL_ESCAPE="$(info eol_escape)"

cat <<EOF
Unofficial Linux AppImage build of Wire Desktop.

- Upstream: [\`${TAG}\`](https://github.com/wireapp/wire-desktop/tree/${TAG}) (commit \`${COMMIT}\`)
- Electron: **${ELECTRON}** (upstream pin: ${UPSTREAM_ELECTRON})
- electron-builder: ${BUILDER}
- Linux runtime patch: ${RUNTIME_PATCH}
- Revision: ${REVISION}
EOF

if [ "$EOL_ESCAPE" = "true" ]; then
  cat <<EOF
- **Note:** upstream's Electron major is no longer supported; this build uses
  the oldest still-supported major instead.
EOF
fi

cat <<EOF

## Upstream changes since the previous release

EOF

if [ -s "$CHANGELOG_FILE" ]; then
  echo '```'
  head -100 "$CHANGELOG_FILE"
  echo '```'
else
  echo "_No changelog available._"
fi

cat <<EOF

## Install with Gear Lever (recommended)

1. Download \`Wire-*.AppImage\` below.
2. Open Gear Lever and add the AppImage (or drag and drop it).
3. Gear Lever reads the embedded update source and offers future releases as
   updates.

## Verify

\`\`\`bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo ${REPO}
\`\`\`

The \`.zsync\` file is consumed by Gear Lever/AppImageUpdate; it is not needed
for manual installs.

## Known issues

- This is an unofficial build with no QA from Wire. Calls and screen sharing
  may have distribution/session-specific problems (the reason Wire gave for
  dropping Linux builds).
- On Ubuntu 24.04+, Chromium's sandbox needs an AppArmor profile because
  unprivileged user namespaces are restricted. See the repository README;
  \`--no-sandbox\` is not recommended.
- Native Wayland is Electron's default. Use \`--ozone-platform=x11\` if you hit
  compositor-specific issues.

## Source and license

GPL-3.0. Source: upstream tag above plus the patches and tooling in
[\`${REPO}\`](https://github.com/${REPO}).

This build is not affiliated with or endorsed by Wire Swiss GmbH. "Wire" is a
trademark of Wire Swiss GmbH.
EOF
