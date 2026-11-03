# Wire Desktop for Linux (unofficial AppImage builds)

[![Build Linux AppImage](https://github.com/nichu42/wire-desktop-linux/actions/workflows/build-linux.yml/badge.svg)](https://github.com/nichu42/wire-desktop-linux/actions/workflows/build-linux.yml)
[![Latest release](https://img.shields.io/github/v/release/nichu42/wire-desktop-linux?label=release)](https://github.com/nichu42/wire-desktop-linux/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)

Unofficial, automatically rebuilt Linux AppImage of the
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
runtime changes Wire removed, keeps Electron on the newest **supported**
patch, runs the upstream test suite, and publishes an AppImage with Gear
Lever-compatible update metadata.

- Builds are triggered by new upstream `windows/*` release tags and by
  Electron patch releases.
- App versions match upstream build numbers (e.g. `3.46.5382`).
- Nothing is published unless lint, the upstream test suite, artifact
  assertions, a runtime smoke test and draft-asset verification pass.

## Install

### Gear Lever (recommended)

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

Every release publishes `SHA256SUMS` and a Sigstore build-provenance
attestation:

```bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo nichu42/wire-desktop-linux
```

Gear Lever's `.zsync` check is transport integrity, not authenticity; use the
attestation when you need to know the file was produced by this repository's
workflow.

## Requirements

- x86_64 Linux, glibc ≥ 2.31 (Ubuntu 22.04+, Debian 12+, Fedora 36+, Arch,
  CachyOS, …)
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

## Troubleshooting

- **No tray icon on GNOME:** install the AppIndicator extension; GNOME does not
  ship tray support by default.
- **`wire://` links do not open the app:** re-register the handler for the
  desktop file you actually have — Gear Lever uses `wire.desktop`,
  `install.sh` uses `wire-desktop.desktop`:

  ```bash
  xdg-mime default wire.desktop x-scheme-handler/wire          # Gear Lever
  xdg-mime default wire-desktop.desktop x-scheme-handler/wire  # install.sh
  ```
- **Keyring prompt / no encrypted cookies:** install `gnome-keyring` or
  `kwallet` and log in to the session keyring.
- **Screen sharing shows the wrong content:** try the opposite of your current
  mode (`--ozone-platform=x11` or native Wayland) and make sure PipeWire is
  running.
- **AppImage will not start:** run it from a terminal and check the output.
  If execution from the mount point is blocked, use
  `--appimage-extract-and-run`.
- Logs: the app writes `console.log` in its user-data directory
  (`~/.config/Wire/`). Redact personal data before sharing.

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

Dependency policy: no application dependency versions are pinned here. Electron
is resolved at build time to the newest patch of upstream's major, or to the
oldest still-supported major if upstream's choice is EOL. Other app
dependencies stay at the versions Wire ships; they move with each upstream tag.
electron-builder is resolved to the latest release, with an automatic fallback
to upstream's version if packaging fails; `@electron/fuses` follows upstream's
`1.8.x` pin because 2.x breaks the upstream TypeScript configuration.

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
22.04. Playwright cannot drive the packaged app because the production fuses
disable `--inspect`; the smoke test reads the app's own log instead.

Not automated: login, sending messages, calls and screen sharing — these need a
Wire test account or a test backend. They are checked manually after setup and
after Electron-major changes.

## Packaging status

AppImage + Gear Lever is the current packaging path. The upstream source and
Linux runtime patch are packaging-agnostic, so Flatpak, AUR or another format
can be added later without changing the build source.

- Flathub's Wire package is archived (the app was declared EOL); a community
  Flatpak would need its own repository and maintenance.
- AUR packages are third-party; `wire-desktop-git` uses the internal-branded
  configuration, and we do not maintain one.
- AppImage + Gear Lever currently gives upstream-versioned builds, update
  metadata and one install path across distributions.

## Development

This is an AI-assisted project: the code, workflows and documentation were
developed with AI assistance and are reviewed by the maintainer. The release
pipeline itself is deterministic GitHub Actions from upstream source; no AI
runs at build or release time.

See [AGENTS.md](AGENTS.md) for the CI-equivalent local build sequence and
prerequisites; the release workflow is the reference implementation.

## Disclaimer

These builds receive no formal QA from Wire or from the maintainer and are
provided **as-is, without warranty of any kind**, to the extent permitted by
law. Use them at your own risk. The maintainer accepts no liability for data
loss, account or service issues, or any other damages arising from their use.
The GPL-3.0 license's warranty and liability provisions apply.

## License

GPL-3.0-only, matching upstream. Source: the upstream tag recorded in each
release, plus `patches/` and `tools/` in this repository.
