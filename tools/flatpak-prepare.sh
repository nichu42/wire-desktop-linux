#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Prepare a reproducible Flatpak source build using the same dependency policy
# as the AppImage:
#   - resolve the upstream tag, commit and target Electron/builder/fuses
#   - update the upstream manifest/lockfile with `yarn up --mode=update-lockfile`
#   - download the production config archive and pin its checksum
#   - generate the offline Yarn/Electron sources
#   - render flatpak/<app-id>.yml from the template
#
# Usage:
#   tools/flatpak-prepare.sh [tag] [--electron supported|latest|upstream] \
#     [--builder latest|upstream] [--electron-version v] [--builder-version v] \
#     [--fuses-version v] [--output path]
#
# Environment:
#   ELECTRON_POLICY   Electron version policy (default: supported)
#   BUILDER_POLICY    electron-builder version policy (default: latest)
#   RUNTIME_VERSION   Freedesktop runtime/BaseApp branch (default: 26.08)
#   BASE_VERSION      Electron2 BaseApp branch (default: RUNTIME_VERSION)
#   NODE_VERSION      Node SDK extension major (default: 24)
#   OUTPUT            Rendered manifest path

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TAG="${TAG:-}"
ELECTRON_POLICY="${ELECTRON_POLICY:-supported}"
BUILDER_POLICY="${BUILDER_POLICY:-latest}"
TARGET_ELECTRON="${TARGET_ELECTRON:-}"
TARGET_BUILDER="${TARGET_BUILDER:-}"
TARGET_FUSES="${TARGET_FUSES:-}"
OUTPUT="${OUTPUT:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift 2 ;;
    --electron) ELECTRON_POLICY="${2:-}"; shift 2 ;;
    --builder) BUILDER_POLICY="${2:-}"; shift 2 ;;
    --electron-version) TARGET_ELECTRON="${2:-}"; shift 2 ;;
    --builder-version) TARGET_BUILDER="${2:-}"; shift 2 ;;
    --fuses-version) TARGET_FUSES="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h | --help)
      sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "flatpak-prepare: unknown argument: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$TAG" ]; then
        TAG="$1"
        shift
      else
        echo "flatpak-prepare: unexpected argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

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

for cmd in curl git jq sha256sum node flatpak-node-generator; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "flatpak-prepare: missing required command: $cmd" >&2
    exit 1
  fi
done

RUNTIME_VERSION="${RUNTIME_VERSION:-26.08}"
BASE_VERSION="${BASE_VERSION:-$RUNTIME_VERSION}"
NODE_VERSION="${NODE_VERSION:-24}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --quiet --depth 1 --branch "$TAG" \
  https://github.com/wireapp/wire-desktop.git "$tmp/upstream"
commit="$(git -C "$tmp/upstream" rev-parse HEAD)"

deps="$(bash "$ROOT/tools/resolve-deps.sh" \
  --package-json "$tmp/upstream/package.json" \
  --electron "$ELECTRON_POLICY" \
  --builder "$BUILDER_POLICY")"

upstream_electron="$(jq -r '.upstream_electron' <<<"$deps")"
upstream_builder="$(jq -r '.upstream_builder' <<<"$deps")"
electron="${TARGET_ELECTRON:-$(jq -r '.electron' <<<"$deps")}"
builder="${TARGET_BUILDER:-$(jq -r '.builder' <<<"$deps")}"
fuses="${TARGET_FUSES:-$(jq -r '.fuses' <<<"$deps")}"
eol_escape=false
if [ "${electron%%.*}" != "${upstream_electron%%.*}" ]; then
  eol_escape=true
fi

# The manifest runs the committed Yarn release directly. Derive its version
# from upstream instead of hardcoding a path that breaks on an upstream bump.
yarn_version="$(jq -r '.packageManager // empty' "$tmp/upstream/package.json" | sed -n 's/^yarn@//p')"
yarn_version="${yarn_version%%+*}"
if [ -z "$yarn_version" ]; then
  echo "flatpak-prepare: upstream package.json has no yarn packageManager pin" >&2
  exit 1
fi
yarn_bin=".yarn/releases/yarn-${yarn_version}.cjs"
if [ ! -f "$tmp/upstream/$yarn_bin" ]; then
  echo "flatpak-prepare: upstream has no $yarn_bin" >&2
  exit 1
fi

(
  cd "$tmp/upstream"
  node "$yarn_bin" up --mode=update-lockfile \
    "electron@$electron" "electron-builder@$builder" "@electron/fuses@$fuses"
)

if ! jq -e \
  --arg e "$electron" \
  --arg b "$builder" \
  --arg f "$fuses" \
  '.devDependencies.electron == $e and .devDependencies["electron-builder"] == $b and .devDependencies["@electron/fuses"] == $f' \
  "$tmp/upstream/package.json" >/dev/null; then
  echo "flatpak-prepare: yarn up did not record expected devDependencies" >&2
  exit 1
fi

cp "$tmp/upstream/package.json" "$ROOT/flatpak/package.json"
cp "$tmp/upstream/yarn.lock" "$ROOT/flatpak/yarn.lock"
lockfile_sha256="$(sha256sum "$ROOT/flatpak/yarn.lock" | cut -d' ' -f1)"

config_spec="$(jq -r '.dependencies["wire-web-config-production"] // empty' "$tmp/upstream/app-config/package.json")"
if [ -z "$config_spec" ]; then
  echo "flatpak-prepare: app-config/package.json has no wire-web-config-production pin" >&2
  exit 1
fi
config_repo="${config_spec%%#*}"
config_ref="${config_spec##*#}"
if [ -z "$config_ref" ] || [ "$config_ref" = "$config_spec" ]; then
  echo "flatpak-prepare: could not parse production config pin: $config_spec" >&2
  exit 1
fi
# `archive/<ref>.tar.gz` resolves tags, branches and commit SHAs alike; the
# `refs/tags/` form breaks if upstream ever pins a commit.
config_url="${config_repo}/archive/${config_ref}.tar.gz"
curl -fsSL "$config_url" -o "$tmp/config.tar.gz"
config_sha256="$(sha256sum "$tmp/config.tar.gz" | cut -d' ' -f1)"

flatpak-node-generator yarn --no-playwright-browsers \
  "$ROOT/flatpak/yarn.lock" -o "$ROOT/flatpak/generated-sources.json"

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
if [ -n "$OUTPUT" ]; then
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
  --arg upstream_electron "$upstream_electron" \
  --arg builder "$builder" \
  --arg upstream_builder "$upstream_builder" \
  --arg fuses "$fuses" \
  --argjson eol_escape "$eol_escape" \
  --arg electron_policy "$ELECTRON_POLICY" \
  --arg builder_policy "$BUILDER_POLICY" \
  --arg lockfile_sha256 "$lockfile_sha256" \
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
    upstream_electron: $upstream_electron,
    builder: $builder,
    upstream_builder: $upstream_builder,
    fuses: $fuses,
    eol_escape: $eol_escape,
    electron_policy: $electron_policy,
    builder_policy: $builder_policy,
    lockfile_sha256: $lockfile_sha256,
    yarn: $yarn,
    runtime: $runtime,
    base: $base,
    node: $node,
    config_ref: $config_ref,
    config_url: $config_url,
    config_sha256: $config_sha256,
    prepared_at: $date
  }' > flatpak/prepared.json

echo "flatpak-prepare: prepared Wire $VERSION (Electron $electron, builder $builder, config $config_ref)"
