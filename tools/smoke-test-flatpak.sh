#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Runtime smoke test for an installed Flatpak. It launches the real app, waits
# for a window and for the privileged webview to reach app.wire.com, then fails
# if it exits early.
#
# Usage:
#   xvfb-run -a tools/smoke-test-flatpak.sh <app-id> [bundle] [gpg-key]
#
# If a bundle is given it is installed into the user installation first. If a
# public key is given, the bundle signature is verified against it.

set -euo pipefail

APP_ID="${1:-io.github.nichu42.wire-desktop-linux}"
BUNDLE="${2:-}"
GPG_FILE="${3:-}"
LOG="smoke-flatpak.log"

if [ -n "$BUNDLE" ]; then
  gpg_args=()
  if [ -n "$GPG_FILE" ]; then
    gpg_args=(--gpg-file="$GPG_FILE")
  fi
  flatpak install --user -y --noninteractive "${gpg_args[@]}" --bundle "$BUNDLE"
fi

if ! flatpak info --user "$APP_ID" >/dev/null 2>&1; then
  echo "smoke-test-flatpak: $APP_ID is not installed" >&2
  exit 2
fi

rm -f "$LOG"
if [ -z "${DISPLAY:-}" ]; then
  echo "smoke-test-flatpak: run under xvfb-run or set DISPLAY" >&2
  exit 2
fi

dbus-run-session -- \
  flatpak run --user --env=ELECTRON_ENABLE_LOGGING=1 "$APP_ID" --disable-gpu >"$LOG" 2>&1 &
pid=$!

cleanup() {
  flatpak kill "$APP_ID" >/dev/null 2>&1 || true
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
}
trap cleanup EXIT

ok=0
for _ in $(seq 1 120); do
  if ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  if grep -q 'https://app\.wire\.com' "$LOG" 2>/dev/null &&
    xwininfo -root -tree 2>/dev/null | grep -qi 'wire'; then
    ok=1
    break
  fi
  sleep 1
done

cleanup
trap - EXIT

if [ "$ok" -ne 1 ]; then
  echo "smoke-test-flatpak: the app did not reach app.wire.com with a visible window" >&2
  tail -200 "$LOG" >&2 || true
  exit 1
fi

echo "smoke-test-flatpak: window appeared and app.wire.com loaded"
