#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Export a flatpak-builder build directory into a signed OSTree repository,
# refresh the static deltas and create a single-file bundle.
#
# Usage:
#   tools/flatpak-repo.sh <build-dir> <repo-dir> <app-id> <version> \
#     <key-id|-> [gpg-home] [output-dir]
#
# A key-id of "-" creates an unsigned repository for local testing. Production
# publishing must pass a real key.

set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "usage: flatpak-repo.sh <build-dir> <repo-dir> <app-id> <version> <key-id|-> [gpg-home] [output-dir]" >&2
  exit 2
fi

BUILD_DIR="$1"
REPO_DIR="$2"
APP_ID="$3"
VERSION="$4"
KEY_ID="${5:--}"
GPG_HOME="${6:-${GNUPGHOME:-$HOME/.gnupg}}"
OUTPUT_DIR="${7:-dist}"

for entry in files export metadata; do
  if [ ! -e "$BUILD_DIR/$entry" ]; then
    echo "flatpak-repo: $BUILD_DIR is not a finalized build directory (missing $entry)" >&2
    exit 1
  fi
done

mkdir -p "$REPO_DIR" "$OUTPUT_DIR"

sign_args=()
export_args=()
if [ "$KEY_ID" != "-" ]; then
  sign_args=(--gpg-sign="$KEY_ID" --gpg-homedir="$GPG_HOME")
  export_args=(--homedir "$GPG_HOME" --armor --export "$KEY_ID")
fi

flatpak build-export "${sign_args[@]}" "$REPO_DIR" "$BUILD_DIR" stable
flatpak build-update-repo "${sign_args[@]}" \
  --generate-static-deltas --prune --prune-depth=2 "$REPO_DIR"

bundle_args=()
if [ "$KEY_ID" != "-" ]; then
  gpg "${export_args[@]}" > "$OUTPUT_DIR/wire-desktop.gpg"
  bundle_args+=(--gpg-keys="$OUTPUT_DIR/wire-desktop.gpg")
fi
if [ -n "${FLATPAK_REPO_URL:-}" ]; then
  bundle_args+=(--repo-url="$FLATPAK_REPO_URL")
fi
if [ -n "${FLATPAK_RUNTIME_REPO:-}" ]; then
  bundle_args+=(--runtime-repo="$FLATPAK_RUNTIME_REPO")
fi

flatpak build-bundle "${bundle_args[@]}" "$REPO_DIR" \
  "$OUTPUT_DIR/Wire-${VERSION}-x86_64.flatpak" "$APP_ID" stable

echo "flatpak-repo: exported $APP_ID $VERSION to $REPO_DIR"
