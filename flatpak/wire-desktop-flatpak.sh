#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Flatpak entry point. zypak-wrapper makes Electron use the sandbox provided by
# Flatpak instead of the setuid helper that is not available inside /app.

set -eu

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
FLATPAK_ID="${FLATPAK_ID:-io.github.nichu42.wire-desktop-linux}"
export TMPDIR="${XDG_RUNTIME_DIR}/app/${FLATPAK_ID}"
mkdir -p "$TMPDIR"

exec zypak-wrapper /app/wire-desktop/wire-desktop \
  --enable-features=WebRtcPipeWireCamera "$@"
