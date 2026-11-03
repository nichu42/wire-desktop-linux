#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Install or update the unofficial Wire Linux AppImage in the user's home
# directory. Gear Lever is the recommended update path; this script is for
# people who do not use Gear Lever.
#
# Usage: install.sh [--version <tag>] [--dry-run] [--uninstall] [--apparmor]

set -euo pipefail
umask 022

REPO="${WIRE_REPO:-nichu42/wire-desktop-linux}"
VERSION=""
DRY_RUN=false
UNINSTALL=false
INSTALL_APPARMOR=false

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --version <tag>  Install a specific release (e.g. v3.46.5382)
  --dry-run        Download and verify, but do not write anything
  --uninstall      Remove the AppImage, desktop entry, icon and metainfo
  --apparmor       Install the AppArmor profile (Ubuntu 24.04+; uses sudo)
  -h, --help       Show this help

Environment:
  WIRE_REPO        GitHub repository (default: nichu42/wire-desktop-linux)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      [ -n "$VERSION" ] || { echo "--version needs a value" >&2; exit 1; }
      shift 2
      ;;
    --version=*)
      VERSION="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    --apparmor)
      INSTALL_APPARMOR=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
APPIMAGE="$BIN_DIR/wire-desktop.AppImage"
DESKTOP="$DATA_DIR/applications/wire-desktop.desktop"
ICON="$DATA_DIR/icons/hicolor/256x256/apps/wire-desktop.png"
METAINFO="$DATA_DIR/metainfo/io.github.nichu42.WireDesktop.metainfo.xml"

if $UNINSTALL; then
  rm -f "$APPIMAGE" "$APPIMAGE.old" "$DESKTOP" "$ICON" "$METAINFO"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DATA_DIR/applications" >/dev/null 2>&1 || true
  fi
  echo "Removed Wire AppImage integration. The profile in ~/.config/Wire was kept."
  echo "If an AppArmor profile was installed, remove /etc/apparmor.d/wire-desktop manually."
  exit 0
fi

for cmd in curl jq sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

api="https://api.github.com/repos/$REPO/releases"
if [ -n "$VERSION" ]; then
  case "$VERSION" in
    v*) api="$api/tags/$VERSION" ;;
    *) api="$api/tags/v$VERSION" ;;
  esac
else
  api="$api/latest"
fi

release_json="$(curl -fsSL --proto '=https' --tlsv1.2 \
  -H 'Accept: application/vnd.github+json' "$api")"
tag="$(jq -r '.tag_name' <<<"$release_json")"
appimage_name="$(jq -r '.assets[] | select(.name | endswith(".AppImage")) | .name' <<<"$release_json" | head -1)"

if [ -z "$appimage_name" ] || [ "$appimage_name" = "null" ]; then
  echo "No AppImage asset found in release $tag" >&2
  exit 1
fi

asset_url() {
  jq -r --arg name "$1" '.assets[] | select(.name == $name) | .browser_download_url' \
    <<<"$release_json" | head -1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

download_asset() {
  local name="$1" url
  url="$(asset_url "$name")"
  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "Missing release asset: $name" >&2
    exit 1
  fi
  curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp/$name" "$url"
}

download_asset "$appimage_name"
download_asset wire-desktop.png
download_asset wire-desktop.metainfo.xml
download_asset SHA256SUMS
if $INSTALL_APPARMOR; then
  download_asset apparmor.profile
fi

(
  cd "$tmp"
  sha256sum -c --ignore-missing SHA256SUMS
)

if $DRY_RUN; then
  echo "Would install $appimage_name ($tag) to $APPIMAGE"
  exit 0
fi

install -d "$BIN_DIR" \
  "$DATA_DIR/applications" \
  "$DATA_DIR/icons/hicolor/256x256/apps" \
  "$DATA_DIR/metainfo"

if [ -f "$APPIMAGE" ]; then
  cp -f "$APPIMAGE" "$APPIMAGE.old"
fi
install -m 755 "$tmp/$appimage_name" "$APPIMAGE.tmp"
mv -f "$APPIMAGE.tmp" "$APPIMAGE"
install -m 644 "$tmp/wire-desktop.png" "$ICON"
install -m 644 "$tmp/wire-desktop.metainfo.xml" "$METAINFO"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Wire
GenericName=Secure messenger
Comment=Unofficial Linux AppImage build of Wire Desktop
Exec="$APPIMAGE" %U
Icon=wire-desktop
Terminal=false
Categories=Network;InstantMessaging;Chat;VideoConference;
Keywords=chat;encrypt;e2e;messenger;videocall;
MimeType=x-scheme-handler/wire;
StartupWMClass=Wire
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DATA_DIR/applications" >/dev/null 2>&1 || true
fi
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default wire-desktop.desktop x-scheme-handler/wire >/dev/null 2>&1 || true
fi

if $INSTALL_APPARMOR; then
  if [ "$(id -u)" -eq 0 ]; then
    echo "--apparmor must be run as a normal user; it invokes sudo itself" >&2
    exit 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required for --apparmor" >&2
    exit 1
  fi
  sed "s|@APPIMAGE_PATH@|$APPIMAGE|g" "$tmp/apparmor.profile" \
    | sudo tee /etc/apparmor.d/wire-desktop >/dev/null
  sudo apparmor_parser -r /etc/apparmor.d/wire-desktop
  echo "Installed AppArmor profile /etc/apparmor.d/wire-desktop"
fi

echo "Installed Wire $tag to $APPIMAGE"
echo "Previous version (if any) kept as $APPIMAGE.old"
echo "If the app fails to start due to the Chromium sandbox on Ubuntu 24.04+, re-run with --apparmor."
