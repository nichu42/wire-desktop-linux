# Wire Desktop for Linux (unofficial AppImage and Flatpak builds)

[![Build Linux AppImage](https://github.com/nichu42/wire-desktop-linux/actions/workflows/build-linux.yml/badge.svg)](https://github.com/nichu42/wire-desktop-linux/actions/workflows/build-linux.yml)
[![Build Flatpak repository](https://github.com/nichu42/wire-desktop-linux/actions/workflows/flatpak.yml/badge.svg)](https://github.com/nichu42/wire-desktop-linux/actions/workflows/flatpak.yml)
[![Latest AppImage release](https://img.shields.io/github/v/release/nichu42/wire-desktop-linux?label=AppImage%20release)](https://github.com/nichu42/wire-desktop-linux/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)

Unofficial, automatically rebuilt Linux AppImage **and Flatpak** of the
[Wire desktop client](https://github.com/wireapp/wire-desktop).

> **Not affiliated with or endorsed by Wire Swiss GmbH.** “Wire” is a
> trademark of Wire Swiss GmbH. These builds are not QA-tested by Wire or by
> this repository's maintainer; calls and screen sharing may have
> distribution- or session-specific problems.
> Wire's last Linux release was `3.40.3882` in December 2025; upstream removed
> Linux support in 2026
> ([wireapp/wire-desktop#9747](https://github.com/wireapp/wire-desktop/issues/9747)).
> This fork exists so Linux users can keep using the open-source desktop
> wrapper.

## What this is

The desktop app is a thin shell around the Wire web app: it hosts
`https://app.wire.com` in an Electron webview and adds the tray icon,
multi-account switching, notifications, `wire://` handling and autostart. The
web app itself is hosted by Wire and updates automatically.

This repository rebuilds that shell from Wire's source, applies the Linux
runtime changes Wire removed, runs the upstream test suite for AppImage
releases, and publishes both an AppImage with Gear Lever-compatible update
metadata and a Flatpak from a signed GitHub-hosted repository. The AppImage
keeps Electron on the newest **supported** patch; the Flatpak uses the upstream
tag's Electron pin so its source build stays reproducible and offline.

- Builds are triggered by new upstream `windows/*` release tags; the AppImage
  also rebuilds for Electron patch releases.
- App versions match the upstream build number (the tag suffix).
- The AppImage is published through a draft/verification flow; the Flatpak is
  published only after its own source-build, lint, assertion and smoke gate.

## Install

### Flatpak (GitHub-hosted repository)

The Flatpak is published from this repository's own signed Flatpak repository,
not Flathub:

```sh
flatpak remote-add --if-not-exists --user wire \
  https://nichu42.github.io/wire-desktop-linux/flatpak/wire.flatpakrepo
flatpak install --user wire io.github.nichu42.wire-desktop-linux
```

Update it with `flatpak update --user`. The signing key fingerprint is published
in `flatpak/build-info.json`; `flatpak remote-info --user wire
io.github.nichu42.wire-desktop-linux` shows the signed ref. Install either the
Flatpak or the AppImage, not both: they register the same `wire://` handler and
both create a “Wire” launcher.
The Flatpak profile is under
`~/.var/app/io.github.nichu42.wire-desktop-linux/`, separate from the AppImage's
`~/.config/Wire`; see [docs/flatpak.md](docs/flatpak.md) for migration details
and build/signing instructions.

### Gear Lever (recommended for the AppImage)

[Gear Lever](https://gearlever.mijorus.it) integrates AppImages into your app
menu and manages updates.

1. Download `Wire-*.AppImage` from
   [Releases](https://github.com/nichu42/wire-desktop-linux/releases/latest).
2. Open Gear Lever → **Add AppImage** (or drag the file onto it).
3. Gear Lever reads the update source embedded in the AppImage. Future
   releases appear as updates; clicking **Update** replaces the AppImage and
   keeps the menu entry.

If automatic detection ever fails: **Set update source** → GitHub →
`nichu42/wire-desktop-linux`, filename `Wire-*x86_64.AppImage`.

> Do **not** also use `install.sh` for an install managed by Gear Lever — you
> would end up with two copies and duplicate menu entries.

### install.sh (alternative)

For systems without Gear Lever. Installs into `~/.local/bin` and
`~/.local/share`, no root required for the normal install:

```bash
curl -fsSL https://raw.githubusercontent.com/nichu42/wire-desktop-linux/linux/install.sh \
  -o /tmp/wire-install.sh
less /tmp/wire-install.sh   # optional, but recommended
bash /tmp/wire-install.sh
```

Re-run the same command to update. `--version <release-tag>` pins a release
(see the [releases page](https://github.com/nichu42/wire-desktop-linux/releases)),
`--dry-run` verifies without writing, `--uninstall` removes the integration
(the profile in `~/.config/Wire` is kept).

### Manual

Download the AppImage, `chmod +x` it, and run it. The AppImage uses a static
runtime, so FUSE is not required.

## Verify

Every AppImage release publishes `SHA256SUMS` and a Sigstore
build-provenance attestation:

```bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo nichu42/wire-desktop-linux
```

Gear Lever's `.zsync` check is transport integrity, not authenticity; use the
attestation when you need to know the file was produced by this repository's
workflow.

For the Flatpak, the OSTree commits and summary are signed by this repository's
Flatpak key. The fingerprint is in `flatpak/build-info.json`; verify the remote
with `flatpak remote-info --user wire io.github.nichu42.wire-desktop-linux`.

## Requirements

- x86_64 Linux, glibc ≥ 2.31 (Ubuntu 22.04+, Debian 12+, Fedora 36+, Arch,
  CachyOS, …) for the AppImage
- Flatpak 1.12+ and a working Flathub remote for the Flatpak runtime; the
  application itself comes from this repository's remote
- `xdg-desktop-portal` with a camera backend (GNOME/KDE) for Flatpak video calls
- GTK 3, libnotify (notifications), NSS
- libsecret + a keyring (GNOME Keyring/KWallet) for encrypted cookie storage;
  the app still runs without one, with weaker cookie protection
- PipeWire for screen sharing on Wayland
- An emoji font (e.g. `noto-fonts-emoji`) for colour emoji
- No FUSE package: the electron-builder static AppImage runtime extracts
  itself when needed

## Wayland

Electron 38+ already defaults to native Wayland when `XDG_SESSION_TYPE=wayland`
(`--ozone-platform=auto`); no extra flag is needed. If your compositor or
screen-sharing setup misbehaves, force XWayland:

```bash
./Wire-*.AppImage --ozone-platform=x11
```

Native Wayland is tested manually on KDE Plasma; the CI smoke test runs under
Xvfb (X11) because Wayland sessions are not available on GitHub runners.

## Startup behaviour

The app shows its main window on launch by default. To start it in the tray
instead, enable **Wire → Start Hidden in Tray** in the menu, or set
`"startHidden": true` in the app's `config/init.json` (`~/.config/Wire` for the
AppImage, `~/.var/app/io.github.nichu42.wire-desktop-linux/config/Wire` for the
Flatpak). The change takes effect on the next launch.

A `wire://` link still opens the window, and **Launch Wire On Startup**
already passes `--hidden`, so autostart starts in the tray. You can also pass
`--hidden` or `--startup` on the command line to start in the tray for a
single run.

In the Flatpak, **Launch Wire On Startup** is hidden: the sandbox cannot write
the host's autostart directory. Add this command to your desktop's own startup
applications instead:

```sh
flatpak run io.github.nichu42.wire-desktop-linux --hidden
```

## Ubuntu 24.04 / 26.04 and the Chromium sandbox

Ubuntu 24.04+ restricts unprivileged user namespaces by default
(`kernel.apparmor_restrict_unprivileged_userns=1`). Chromium's user-namespace
sandbox is then blocked, and the AppImage may fail to start.

Use the provided AppArmor profile instead of `--no-sandbox`. If you installed
with `install.sh`, re-run the downloaded script with `--apparmor`:

```bash
bash /tmp/wire-install.sh --apparmor
```

With Gear Lever, apply the profile manually — running `install.sh --apparmor`
would create a second installation. Adjust the path to your Gear Lever
AppImage:

```bash
curl -fsSLO https://github.com/nichu42/wire-desktop-linux/releases/latest/download/apparmor.profile
sed -i "s|@APPIMAGE_PATH@|$HOME/AppImages/wire.appimage|" apparmor.profile
sudo install -m 644 apparmor.profile /etc/apparmor.d/wire-desktop
sudo apparmor_parser -r /etc/apparmor.d/wire-desktop
```

This grants the AppImage permission to create a user namespace; it does **not**
disable the sandbox. `--no-sandbox` disables renderer sandboxing and is a
security regression for a messenger.

The Flatpak does not need this AppArmor profile: zypak and Flatpak's own sandbox
provide the runtime environment, and the desktop entry/Wrapper never pass
`--no-sandbox`.

## Troubleshooting

- **No tray icon on GNOME:** install the AppIndicator extension; GNOME does not
  ship tray support by default. If you enabled **Start Hidden in Tray** without
  a working tray, launch the app again from the menu to show the window.
- **Flatpak autostart:** **Launch Wire On Startup** is intentionally hidden in
  the Flatpak. Add `flatpak run io.github.nichu42.wire-desktop-linux --hidden`
  to your desktop's startup applications. The same command works for
  `--startup`.
- **Flatpak managed configuration:** `/etc` is not visible at that path inside
  the sandbox. Managed deployments can opt in; the app then reads
  `/run/host/etc/wire/managed.json`. This exposes the host's `/etc` read-only,
  so apply it only on managed devices:

  ```sh
  flatpak override --user --filesystem=host-etc:ro \
    io.github.nichu42.wire-desktop-linux
  ```
- **`wire://` links do not open the app:** re-register the handler for the
  desktop file you actually have — Gear Lever uses `wire.desktop`,
  `install.sh` uses `wire-desktop.desktop`, and the Flatpak exports
  `io.github.nichu42.wire-desktop-linux.desktop`:

  ```bash
  xdg-mime default wire.desktop x-scheme-handler/wire          # Gear Lever
  xdg-mime default wire-desktop.desktop x-scheme-handler/wire  # install.sh
  xdg-mime default io.github.nichu42.wire-desktop-linux.desktop \
    x-scheme-handler/wire                                      # Flatpak
  ```
- **Keyring prompt / no encrypted cookies:** install `gnome-keyring` or
  `kwallet` and log in to the session keyring. For the Flatpak, check
  `flatpak info --show-permissions io.github.nichu42.wire-desktop-linux` and
  make sure the Secret Service is running.
- **Camera/video in the Flatpak:** the app uses the XDG Camera portal
  (`WebRtcPipeWireCamera` is enabled in the wrapper), so no broad
  `--device=all` permission is required. The first camera use should prompt for
  permission; if it was denied, reset it with:

  ```sh
  flatpak permission-remove devices camera \
    io.github.nichu42.wire-desktop-linux
  ```

  Check that `xdg-desktop-portal` and a desktop backend are running. If your
  desktop has no camera portal backend, use the AppImage for video calls.
- **Screen sharing shows the wrong content:** try the opposite of your current
  mode (`--ozone-platform=x11` or native Wayland) and make sure PipeWire is
  running. The Flatpak uses the desktop's ScreenCast portal.
- **AppImage will not start:** run it from a terminal and check the output.
  If execution from the mount point is blocked, use
  `--appimage-extract-and-run`.
- Logs: the app writes `console.log` in its user-data directory
  (`~/.config/Wire/` for the AppImage,
  `~/.var/app/io.github.nichu42.wire-desktop-linux/config/Wire/` for the
  Flatpak). Redact personal data before sharing.

## How it works

```
new upstream windows/* tag  (or Electron patch release)
  → resolve version + newest supported Electron
  → clone upstream at the tag
  → apply the Linux runtime patch (best effort)
  → yarn up Electron/electron-builder, yarn install
  → upstream tests (xvfb-run yarn test)
  → stamp production config, build the AppImage
  → assert asar/fuses/desktop/update-info, direct-launch smoke test
  → runtime smoke on the build image and Ubuntu 22.04 (older glibc)
  → draft release, attest, verify assets, publish
```

The Flatpak pipeline is separate:

```
tools/flatpak-prepare.sh <windows/* tag>
  → resolve commit and Electron pin, pin the production config checksum
  → flatpak-node-generator: offline Yarn/Electron sources
  → flatpak-builder: patch, build, unpacked electron-builder output
  → assert asar/fuses/desktop/metainfo/wrapper + Xvfb smoke
  → test-signed repo in CI; production GPG signing and Pages publish
```

Dependency policy: no application dependency versions are pinned here. Electron
is resolved at build time to the newest patch of upstream's major, or to the
oldest still-supported major if upstream's choice is EOL. Other app
dependencies stay at the versions Wire ships; they move with each upstream tag.
electron-builder is resolved to the latest release, with an automatic fallback
to upstream's version if packaging fails; `@electron/fuses` follows upstream's
`1.8.x` pin because 2.x breaks the upstream TypeScript configuration. The
Flatpak deliberately uses the upstream tag's Electron/electron-builder pins so
its source build remains reproducible and offline; it may trail the AppImage by
Electron patch releases.

The release workflow is split into read-only build jobs and a write-only
publish job; `yarn install` never sees a write token. All actions are pinned to
commit SHAs and updated by Dependabot. Releases carry a Sigstore provenance
attestation.

## Testing scope

Automated on every build: workflow/script lint, upstream typecheck + unit
tests, artifact structure (production config, version, fuses, desktop entry,
no source maps/dev files), update-info/`.zsync` integrity, and a direct launch
that waits for the wrapper window and for the privileged webview to reach
`app.wire.com` on the pinned build image (currently Ubuntu 26.04) and Ubuntu
22.04. The Flatpak job additionally checks the offline source build,
manifest/AppStream lint, asar/fuses/desktop/metainfo/wrapper
assertions and a `flatpak run` smoke test. Playwright cannot drive the packaged
app because the production fuses disable `--inspect`; the smoke tests read the
app's own log instead.

Not automated: login, sending messages, calls and screen sharing — these need a
Wire test account or a test backend. They are checked manually after setup and
after Electron-major changes.

## Packaging status

AppImage + Gear Lever and the GitHub-hosted Flatpak repository are the current
packaging paths. They share the same upstream source and Linux runtime patches,
but have separate build gates.

- **AppImage + Gear Lever:** upstream-versioned builds, embedded update source
  and a single-file install across distributions.
- **Flatpak:** source build from the upstream tag, signed OSTree repository on
  GitHub Pages, automatic `flatpak update`. It is not on Flathub; Flathub's
  archived Wire package and its review requirements are out of scope.
- **AUR:** third-party; `wire-desktop-git` uses the internal-branded
  configuration, and we do not maintain one.
- Do not install the AppImage and the Flatpak together; pick one update path.

## Development

This is an AI-assisted project: the code, workflows and documentation were
developed with AI assistance and are reviewed by the maintainer. The release
pipeline itself is deterministic GitHub Actions from upstream source; no AI
runs at build or release time.

See [AGENTS.md](AGENTS.md) for the CI-equivalent local build sequence and
prerequisites, and [docs/flatpak.md](docs/flatpak.md) for the Flatpak build,
signing and repository operations. The release workflows are the reference
implementation.

## Disclaimer

These builds receive no formal QA from Wire or from the maintainer and are
provided **as-is, without warranty of any kind**, to the extent permitted by
law. Use them at your own risk. The maintainer accepts no liability for data
loss, account or service issues, or any other damages arising from their use.
The GPL-3.0 license's warranty and liability provisions apply.

## License

GPL-3.0-only, matching upstream. Source: the upstream tag recorded in each
release, plus `patches/` and `tools/` in this repository.
