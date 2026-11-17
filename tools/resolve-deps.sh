#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Resolve the Electron, electron-builder and @electron/fuses versions for a
# Linux build according to the repository's support policy.
#
# Usage:
#   tools/resolve-deps.sh --package-json <file> \
#     [--electron supported|latest|upstream] [--builder latest|upstream]
#   tools/resolve-deps.sh --tag <windows/x.y.z> \
#     [--electron supported|latest|upstream] [--builder latest|upstream]

set -euo pipefail

PACKAGE_JSON=""
TAG=""
ELECTRON_POLICY="${ELECTRON_POLICY:-supported}"
BUILDER_POLICY="${BUILDER_POLICY:-latest}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package-json) PACKAGE_JSON="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --electron) ELECTRON_POLICY="${2:-}"; shift 2 ;;
    --builder) BUILDER_POLICY="${2:-}"; shift 2 ;;
    -h | --help)
      sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "resolve-deps: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "resolve-deps: missing required command: $cmd" >&2
    exit 2
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -z "$PACKAGE_JSON" ]; then
  if [ -z "$TAG" ]; then
    echo "resolve-deps: pass --package-json or --tag" >&2
    exit 2
  fi
  PACKAGE_JSON="$tmp/package.json"
  curl -fsSL "https://raw.githubusercontent.com/wireapp/wire-desktop/$TAG/package.json" \
    -o "$PACKAGE_JSON"
fi

if [ ! -f "$PACKAGE_JSON" ]; then
  echo "resolve-deps: missing file: $PACKAGE_JSON" >&2
  exit 2
fi

upstream_electron="$(jq -r '.devDependencies.electron // empty' "$PACKAGE_JSON")"
upstream_builder="$(jq -r '.devDependencies["electron-builder"] // empty' "$PACKAGE_JSON")"
target_fuses="$(jq -r '.devDependencies["@electron/fuses"] // empty' "$PACKAGE_JSON")"
if [ -z "$upstream_electron" ] || [ -z "$upstream_builder" ] || [ -z "$target_fuses" ]; then
  echo "resolve-deps: $PACKAGE_JSON is missing expected devDependencies pins" >&2
  exit 1
fi
upstream_major="${upstream_electron%%.*}"

registry="$(curl -fsSL https://registry.npmjs.org/electron)"
latest="$(jq -r '.["dist-tags"].latest // empty' <<<"$registry")"
if [ -z "$latest" ]; then
  echo "resolve-deps: could not resolve Electron dist-tags.latest" >&2
  exit 1
fi
latest_major="${latest%%.*}"
oldest_supported=$((latest_major - 2))

target_major="$upstream_major"
if [ "$target_major" -lt "$oldest_supported" ]; then
  target_major="$oldest_supported"
fi

case "$ELECTRON_POLICY" in
  upstream)
    target_electron="$upstream_electron"
    ;;
  latest)
    target_major="$latest_major"
    target_electron="$(jq -r --arg t "${target_major}-x-y" '.["dist-tags"][$t] // empty' <<<"$registry")"
    ;;
  supported)
    target_electron="$(jq -r --arg t "${target_major}-x-y" '.["dist-tags"][$t] // empty' <<<"$registry")"
    ;;
  *)
    echo "resolve-deps: unknown electron policy: $ELECTRON_POLICY" >&2
    exit 1
    ;;
esac

if [ -z "$target_electron" ] || [ "$target_electron" = "null" ]; then
  target_electron="$(jq -r --arg p "${target_major}." \
    '[.versions | keys[] | select(startswith($p)) | select(test("-") | not)] | sort_by(split(".") | map(tonumber)) | last // empty' \
    <<<"$registry")"
fi
if [ -z "$target_electron" ] || [ "$target_electron" = "null" ]; then
  echo "resolve-deps: could not resolve an Electron version for major $target_major" >&2
  exit 1
fi

case "$BUILDER_POLICY" in
  upstream)
    target_builder="$upstream_builder"
    ;;
  latest)
    target_builder="$(curl -fsSL https://registry.npmjs.org/electron-builder | jq -r '.["dist-tags"].latest // empty')"
    ;;
  *)
    echo "resolve-deps: unknown builder policy: $BUILDER_POLICY" >&2
    exit 1
    ;;
esac
if [ -z "$target_builder" ] || [ "$target_builder" = "null" ]; then
  echo "resolve-deps: could not resolve electron-builder version" >&2
  exit 1
fi

eol_escape=false
if [ "$target_major" != "$upstream_major" ]; then
  eol_escape=true
fi

jq -n \
  --arg upstream_electron "$upstream_electron" \
  --arg upstream_builder "$upstream_builder" \
  --argjson upstream_major "$upstream_major" \
  --arg electron "$target_electron" \
  --argjson target_major "$target_major" \
  --arg latest_electron "$latest" \
  --argjson oldest_supported_major "$oldest_supported" \
  --arg builder "$target_builder" \
  --arg fuses "$target_fuses" \
  --argjson eol_escape "$eol_escape" \
  --arg electron_policy "$ELECTRON_POLICY" \
  --arg builder_policy "$BUILDER_POLICY" \
  '{
    upstream_electron: $upstream_electron,
    upstream_builder: $upstream_builder,
    upstream_major: $upstream_major,
    electron: $electron,
    target_major: $target_major,
    latest_electron: $latest_electron,
    oldest_supported_major: $oldest_supported_major,
    builder: $builder,
    fuses: $fuses,
    eol_escape: $eol_escape,
    electron_policy: $electron_policy,
    builder_policy: $builder_policy
  }'
