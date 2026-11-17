# Wire Desktop for Linux (unofficial Flatpak and AppImage builds)

[![Build Linux AppImage](https://github.com/nichu42/wire-desktop-linux/actions/workflows/build-linux.yml/badge.svg)](https://github.com/nichu42/wire-desktop-linux/actions/workflows/build-linux.yml)
[![Build Flatpak repository](https://github.com/nichu42/wire-desktop-linux/actions/workflows/flatpak.yml/badge.svg)](https://github.com/nichu42/wire-desktop-linux/actions/workflows/flatpak.yml)
[![Latest release](https://img.shields.io/github/v/release/nichu42/wire-desktop-linux?label=release)](https://github.com/nichu42/wire-desktop-linux/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)

Unofficial, automatically rebuilt Linux **Flatpak** and **AppImage** packages of
the [Wire desktop client](https://github.com/wireapp/wire-desktop) (the Electron
wrapper around `https://app.wire.com` with tray icon, multi-account switching,
notifications, `wire://` links and autostart). Built from upstream `windows/*`
release tags with the removed Linux runtime behaviour restored and Electron kept
on a supported patch release.

> **Not affiliated with or endorsed by Wire Swiss GmbH.** “Wire” is a
> trademark of Wire Swiss GmbH. Wire dropped official Linux support in 2026
> ([wireapp/wire-desktop#9747](https://github.com/wireapp/wire-desktop/issues/9747);
> last official build `3.40.3882`). These builds receive no QA from Wire or the
> maintainer; calls and screen sharing may have distribution- or
> session-specific issues.

## Install

Install **either** the Flatpak **or** the AppImage, not both — they register
the same `wire://` handler and create duplicate launcher entries.

### Flatpak

Published from this repository's signed OSTree remote (not Flathub):

```sh
flatpak remote-add --if-not-exists --user wire \
  https://nichu42.github.io/wire-desktop-linux/flatpak/wire.flatpakrepo
flatpak install --user wire io.github.nichu42.wire-desktop-linux
```

Or download `Wire-*.flatpak` from
[Releases](https://github.com/nichu42/wire-desktop-linux/releases/latest) and run
`flatpak install --user --bundle Wire-*.flatpak` (this also configures the
signed remote so `flatpak update --user` works afterward).

The Flatpak profile lives in `~/.var/app/io.github.nichu42.wire-desktop-linux/`.
See [docs/flatpak.md](docs/flatpak.md) to migrate an existing AppImage profile
or configure managed deployments (`/run/host/etc/wire/managed.json`).

### AppImage

- **With [Gear Lever](https://github.com/mijorus/gearlever) (recommended):**
  download `Wire-*.AppImage` from
  [Releases](https://github.com/nichu42/wire-desktop-linux/releases/latest) and
  add or drag it into Gear Lever. Updates are detected via the embedded
  `.zsync` source (manual fallback: GitHub → `nichu42/wire-desktop-linux`,
  filename `Wire-*x86_64.AppImage`).
- **With `install.sh` (without Gear Lever):** installs into `~/.local/bin` and
  `~/.local/share` (do **not** mix with Gear Lever):

  ```bash
  curl -fsSL https://raw.githubusercontent.com/nichu42/wire-desktop-linux/linux/install.sh \
    -o /tmp/wire-install.sh
  less /tmp/wire-install.sh   # optional, recommended
  bash /tmp/wire-install.sh
  ```

  Re-run to update; options include `--version <tag>`, `--dry-run`,
  `--uninstall` (keeps `~/.config/Wire`), and `--apparmor`.
- **Manual:** `chmod +x` the AppImage and run it directly (static runtime; no
  FUSE package required).

## Verify

AppImage releases include `SHA256SUMS` and a Sigstore provenance attestation
(`.zsync` is for Gear Lever transport/delta checks, not a signature):

```bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo nichu42/wire-desktop-linux
```

Flatpak commits and summary metadata are GPG-signed (signing key fingerprint in
[`build-info.json`](https://nichu42.github.io/wire-desktop-linux/flatpak/build-info.json)),
and release bundles include `.sha256` and Sigstore attestations:

```bash
flatpak remote-info --user wire io.github.nichu42.wire-desktop-linux
sha256sum -c Wire-*.flatpak.sha256
gh attestation verify Wire-*.flatpak --repo nichu42/wire-desktop-linux
```

See [SECURITY.md](SECURITY.md) for provenance details and vulnerability
reporting.

## Requirements and desktop notes

- **System requirements:** `x86_64` Linux (smoke-tested on Ubuntu 22.04+ /
  glibc 2.35+), a Secret Service keyring (`gnome-keyring` or `kwallet`) for
  encrypted cookie storage, PipeWire for Wayland screen sharing, and an emoji
  font (e.g. `noto-fonts-emoji`). Flatpak additionally requires Flatpak 1.12+,
  Flathub (for the Freedesktop runtime), and `xdg-desktop-portal` with a camera
  backend for video calls.
- **Ubuntu 24.04+ Chromium sandbox (AppImage):** Ubuntu restricts unprivileged
  user namespaces (`kernel.apparmor_restrict_unprivileged_userns=1`), which
  blocks the AppImage's sandbox. Apply the provided AppArmor profile instead of
  passing `--no-sandbox` (Flatpak does not need this):
  - With `install.sh`: `bash /tmp/wire-install.sh --apparmor`
  - With Gear Lever (adjust the AppImage path to match your file):

    ```bash
    curl -fsSLO https://github.com/nichu42/wire-desktop-linux/releases/latest/download/apparmor.profile
    sed -i "s|@APPIMAGE_PATH@|$HOME/AppImages/wire.appimage|" apparmor.profile
    sudo install -m 644 apparmor.profile /etc/apparmor.d/wire-desktop
    sudo apparmor_parser -r /etc/apparmor.d/wire-desktop
    ```
- **Wayland:** Electron defaults to native Wayland when
  `XDG_SESSION_TYPE=wayland`. Pass `--ozone-platform=x11` if your compositor or
  screen sharing misbehaves.
- **Starting hidden:** Enable **Wire → Start Hidden in Tray** (or
  `"startHidden": true` in `config/init.json`), or pass `--hidden` /
  `--startup`. In the Flatpak, **Launch Wire On Startup** is hidden because the
  sandbox cannot write host autostart files — add
  `flatpak run io.github.nichu42.wire-desktop-linux --hidden` to your desktop's
  startup applications instead.

## Troubleshooting

- **No tray icon on GNOME:** install the AppIndicator extension. If started
  hidden without a tray, re-launch Wire from the app menu to show the window.
- **`wire://` links do not open Wire:** re-register the handler for your
  install method:

  ```bash
  xdg-mime default wire.desktop x-scheme-handler/wire                          # Gear Lever
  xdg-mime default wire-desktop.desktop x-scheme-handler/wire                  # install.sh
  xdg-mime default io.github.nichu42.wire-desktop-linux.desktop x-scheme-handler/wire  # Flatpak
  ```
- **Camera/video in Flatpak:** uses the XDG Camera portal
  (`WebRtcPipeWireCamera`; no `--device=all` required). Reset a denied prompt
  with
  `flatpak permission-remove devices camera io.github.nichu42.wire-desktop-linux`.
  If your desktop has no camera portal backend, use the AppImage for video
  calls.
- **Screen sharing, keyring, or mount errors:** try `--ozone-platform=x11` and
  ensure PipeWire is running; make sure `gnome-keyring` or `kwallet` is
  unlocked; if AppImage mount execution is blocked, run with
  `--appimage-extract-and-run`.
- **Logs:** written to `console.log` in `~/.config/Wire/` (AppImage) or
  `~/.var/app/io.github.nichu42.wire-desktop-linux/config/Wire/` (Flatpak).
  Redact personal data before sharing.

## How it works and development

GitHub Actions workflows automatically build from upstream `windows/*` tags with
`patches/`, keep Electron on a supported patch release, run lint, upstream
tests (AppImage), artifact assertions, and Xvfb startup smoke tests to
`app.wire.com`, and publish releases with Sigstore/GPG signatures. Login,
messaging, calls, and screen sharing are not tested automatically in CI.

Code, workflows, and documentation in this repository were developed with AI
assistance and reviewed by the maintainer; CI releases run deterministically
from upstream source without AI. See [AGENTS.md](AGENTS.md) for the CI pipeline,
dependency policy, and local build steps, and [docs/flatpak.md](docs/flatpak.md)
for Flatpak operations.

## License and disclaimer

GPL-3.0-**or-later**, matching upstream: Wire's source files carry the
"either version 3 of the License, or (at your option) any later version"
boilerplate, so this fork keeps that grant rather than narrowing it. Source:
the upstream tag/commit recorded in each release, plus `patches/` and `tools/`
in this repository.

Every artifact ships the attribution instead of only pointing at it:

| Where | What |
|---|---|
| `<app>/LICENSE`, `<app>/NOTICE` (AppImage and Flatpak app directory) | Upstream's GPL text and the notice naming the upstream commit, the copyright holder and the modifications applied |
| `/app/share/licenses/io.github.nichu42.wire-desktop-linux/` (Flatpak) | The same two files, in the location Flatpak tooling expects |
| `<app>/LICENSE.electron.txt`, `<app>/LICENSES.chromium.html` | Electron and Chromium third-party notices, as shipped by electron-builder |

`NOTICE` lists the changes this fork makes (`patches/01-linux-runtime.patch`,
`02-flatpak-runtime.patch`); the About window repeats the "unofficial" build
line and links back to this repository. The launcher and AppStream entries are
named **Wire Desktop (unofficial)** so no official-looking name is shipped —
the window class stays `Wire`, which keeps taskbar grouping and pinning
working.

Provided **as-is, without warranty of any kind**; use at your own risk. The
maintainer accepts no liability for data loss, account or service issues, or
other damages.
