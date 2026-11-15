#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Generate the dedicated Flatpak repository signing key and print the values
# that must be stored as GitHub Actions secrets. Run this on a trusted machine,
# then delete the generated private-key file after adding the secret.
#
# The CI signing key is intentionally passphrase-less: flatpak-builder and
# flatpak build-update-repo cannot prompt for a passphrase in the publish job.
# The private key is protected by the GitHub secret store; keep an offline
# backup and rotate it if it is exposed.

set -euo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/flatpak/dist"
mkdir -p "$OUT_DIR"

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT

gpg --batch --passphrase '' --quick-generate-key \
  "Wire Desktop Flatpak (unofficial) <flatpak@nichu42.github.io>" ed25519 sign 5y

KEY_ID="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ {print $5; exit}')"
if [ -z "$KEY_ID" ]; then
  echo "flatpak-keygen: key generation failed" >&2
  exit 1
fi
FINGERPRINT="$(gpg --with-colons --fingerprint "$KEY_ID" | awk -F: '/^fpr:/ {print $10; exit}')"

gpg --armor --export-secret-keys "$KEY_ID" | base64 -w0 > "$OUT_DIR/wire-flatpak-private-key.b64"
gpg --armor --export "$KEY_ID" > "$OUT_DIR/wire-desktop.gpg"

cat <<EOF
Generated Flatpak signing key:
  key id:      $KEY_ID
  fingerprint: $FINGERPRINT

Add these repository secrets:
  FLATPAK_GPG_PRIVATE_KEY = contents of $OUT_DIR/wire-flatpak-private-key.b64
  FLATPAK_GPG_KEY_ID      = $KEY_ID

Then delete $OUT_DIR/wire-flatpak-private-key.b64 and keep an offline backup
of the key. The public key is $OUT_DIR/wire-desktop.gpg.
EOF
