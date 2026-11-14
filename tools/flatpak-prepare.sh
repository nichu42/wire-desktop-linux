#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Prepare a reproducible Flatpak source build:
#   - resolve the upstream tag, commit and Electron pin
#   - download the production config archive and pin its checksum
#   - generate the offline Yarn/Electron sources
#   - render flatpak/<app-id>.yml from the template
#
# Usage: tools/flatpak-prepare.sh [tag]
# Environment:
#   RUNTIME_VERSION   Freedesktop runtime/BaseApp branch (default: 26.08)
#   BASE_VERSION      Electron2 BaseApp branch (default: RUNTIME_VERSION)
#   NODE_VERSION      Node SDK extension major (default: 22)
#   OUTPUT            Rendered manifest path

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TAG="${1:-${TAG:-}}"
if [ -z "$TAG" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "flatpak-prepare: pass a tag or install gh to resolve the latest windows/* tag" >&2
    exit 1
  fi
  TAG="$(gh api "repos/wireapp/wire-desktop/releases?per_page=50" \
    --jq '[.[] | select(.tag_name | startswith("windows/"))][0].tag_name')"
fi

if ! [[ "$TAG" =~ ^windows/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "flatpak-prepare: invalid upstream tag: $TAG" >&2
  exit 1
fi
VERSION="${BASH_REMATCH[1]}"
BUILD="${VERSION##*.}"

for cmd in curl git jq sha256sum flatpak-node-generator; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "flatpak-prepare: missing required command: $cmd" >&2
    exit 1
  fi
done

RUNTIME_VERSION="${RUNTIME_VERSION:-26.08}"
BASE_VERSION="${BASE_VERSION:-$RUNTIME_VERSION}"
NODE_VERSION="${NODE_VERSION:-22}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

commit="$(git ls-remote https://github.com/wireapp/wire-desktop.git "refs/tags/$TAG^{}" | cut -f1)"
if [ -z "$commit" ]; then
  commit="$(git ls-remote https://github.com/wireapp/wire-desktop.git "refs/tags/$TAG" | cut -f1)"
fi
if [ -z "$commit" ]; then
  echo "flatpak-prepare: could not resolve tag $TAG" >&2
  exit 1
fi

curl -fsSL "https://raw.githubusercontent.com/wireapp/wire-desktop/$commit/package.json" -o "$tmp/package.json"
curl -fsSL "https://raw.githubusercontent.com/wireapp/wire-desktop/$commit/app-config/package.json" -o "$tmp/app-config.json"
electron="$(jq -r '.devDependencies.electron // empty' "$tmp/package.json")"
if [ -z "$electron" ]; then
  echo "flatpak-prepare: upstream package.json has no Electron pin" >&2
  exit 1
fi

# The manifest runs the committed Yarn release directly. Derive its version
# from upstream instead of hardcoding a path that breaks on an upstream bump.
yarn_version="$(jq -r '.packageManager // empty' "$tmp/package.json" | sed -n 's/^yarn@//p')"
yarn_version="${yarn_version%%+*}"
if [ -z "$yarn_version" ]; then
  echo "flatpak-prepare: upstream package.json has no yarn packageManager pin" >&2
  exit 1
fi
if ! curl -fsI "https://raw.githubusercontent.com/wireapp/wire-desktop/$commit/.yarn/releases/yarn-${yarn_version}.cjs" >/dev/null; then
  echo "flatpak-prepare: upstream has no .yarn/releases/yarn-${yarn_version}.cjs" >&2
  exit 1
fi

config_spec="$(jq -r '.dependencies["wire-web-config-production"]' "$tmp/app-config.json")"
config_repo="${config_spec%%#*}"
config_ref="${config_spec##*#}"
if [ -z "$config_ref" ] || [ "$config_ref" = "$config_spec" ]; then
  echo "flatpak-prepare: could not parse production config pin: $config_spec" >&2
  exit 1
fi
config_url="${config_repo}/archive/refs/tags/${config_ref}.tar.gz"
curl -fsSL "$config_url" -o "$tmp/config.tar.gz"
config_sha256="$(sha256sum "$tmp/config.tar.gz" | cut -d' ' -f1)"

curl -fsSL "https://raw.githubusercontent.com/wireapp/wire-desktop/$commit/yarn.lock" -o "$tmp/yarn.lock"
flatpak-node-generator yarn --no-playwright-browsers "$tmp/yarn.lock" -o "$ROOT/flatpak/generated-sources.json"

render_args=(
  --tag "$TAG"
  --commit "$commit"
  --version "$VERSION"
  --build "$BUILD"
  --electron "$electron"
  --yarn "$yarn_version"
  --runtime "$RUNTIME_VERSION"
  --base "$BASE_VERSION"
  --node "$NODE_VERSION"
  --date "$(date -u +%F)"
  --config-url "$config_url"
  --config-sha256 "$config_sha256"
)
if [ -n "${OUTPUT:-}" ]; then
  render_args+=(--output "$OUTPUT")
fi

node "$ROOT/tools/flatpak-render-manifest.mjs" "${render_args[@]}"

jq -n \
  --arg app_id "io.github.nichu42.wire-desktop-linux" \
  --arg tag "$TAG" \
  --arg commit "$commit" \
  --arg version "$VERSION" \
  --arg build "$BUILD" \
  --arg electron "$electron" \
  --arg yarn "$yarn_version" \
  --arg runtime "$RUNTIME_VERSION" \
  --arg base "$BASE_VERSION" \
  --arg node "$NODE_VERSION" \
  --arg config_ref "$config_ref" \
  --arg config_url "$config_url" \
  --arg config_sha256 "$config_sha256" \
  --arg date "$(date -u +%F)" \
  '{
    schema: 1,
    app_id: $app_id,
    upstream_tag: $tag,
    upstream_commit: $commit,
    version: $version,
    build: $build,
    electron: $electron,
    yarn: $yarn,
    runtime: $runtime,
    base: $base,
    node: $node,
    config_ref: $config_ref,
    config_url: $config_url,
    config_sha256: $config_sha256,
    prepared_at: $date
  }' > flatpak/prepared.json

echo "flatpak-prepare: prepared Wire $VERSION (Electron $electron, config $config_ref)"
