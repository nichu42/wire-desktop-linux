#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Runtime smoke test for the extracted AppImage. The packaged Electron build
# deliberately disables the --inspect fuse (as upstream does), so Playwright's
# Electron driver cannot attach. Instead, run the real app, wait for a window
# and for the privileged webview to navigate to app.wire.com, then fail if it
# exits early.
#
# Usage: xvfb-run -a tools/smoke-test.sh squashfs-root

set -euo pipefail

APP_DIR="${1:-squashfs-root}"
APP="$APP_DIR/wire-desktop"
LOG="smoke.log"

if [ ! -x "$APP" ]; then
  echo "smoke-test: missing executable $APP" >&2
  exit 2
fi

rm -f "$LOG"
ELECTRON_ENABLE_LOGGING=1 "$APP" --no-sandbox --disable-gpu >"$LOG" 2>&1 &
pid=$!

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

kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

if [ "$ok" -ne 1 ]; then
  echo "smoke-test: the app did not reach app.wire.com with a visible window" >&2
  tail -200 "$LOG" >&2 || true
  exit 1
fi

echo "smoke-test: window appeared and app.wire.com loaded"
