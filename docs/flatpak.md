# Flatpak distribution

This repository publishes a Flatpak of the same upstream Wire Desktop build as
the AppImage. It is distributed from a **signed third-party Flatpak repository
on GitHub Pages**; Flathub is intentionally not used.

The Flatpak is a source build: `flatpak-builder` clones the upstream release
tag, applies the Linux runtime patches, installs offline Yarn/Electron sources,
runs electron-builder in `--dir` mode, and packages the unpacked application.
It is not a repack of the AppImage or a `.deb`.

## Install

```sh
flatpak remote-add --if-not-exists --user wire \
  https://nichu42.github.io/wire-desktop-linux/flatpak/wire.flatpakrepo
flatpak install --user wire io.github.nichu42.wire-desktop-linux
```

Updates:

```sh
flatpak update --user
```

The remote is a third-party repository, not Flathub. Install either the AppImage
or the Flatpak; both register `wire://` and show a “Wire” launcher, and running
both is not useful. The Flatpak profile lives in
`~/.var/app/io.github.nichu42.wire-desktop-linux/`, not `~/.config/Wire`. To
migrate an AppImage profile, close the app and copy it:

```sh
mkdir -p ~/.var/app/io.github.nichu42.wire-desktop-linux/config
cp -a ~/.config/Wire ~/.var/app/io.github.nichu42.wire-desktop-linux/config/
```

To switch from the GitHub remote to another remote later, uninstall without
`--delete-data` and reinstall; the `~/.var/app/<app-id>` data is preserved.

## Verification

The repository summary and commits are GPG-signed. The public key is embedded in
`wire.flatpakrepo`; the fingerprint is published in the repository's
[`build-info.json`](https://nichu42.github.io/wire-desktop-linux/flatpak/build-info.json).
See [SECURITY.md](../SECURITY.md) for the verification policy.

```sh
flatpak remote-info --user wire io.github.nichu42.wire-desktop-linux
flatpak info --user io.github.nichu42.wire-desktop-linux
```

The workflow also creates a Sigstore build-provenance attestation for the
single-file `.flatpak` bundle in the workflow run. The bundle embeds the public
key, so it can be installed directly with `flatpak install --bundle Wire-*.flatpak`;
the signed OSTree repository is still the update channel.

## Build locally

Requirements: Flatpak, `flatpak-builder`, `flatpak-node-generator`, Node 22,
`jq`, `curl`, `git`, `patch`, and the current Freedesktop runtime/SDK/BaseApp
(26.08 at the time of writing).

```sh
# 1. Resolve the tag, pin the config archive and generate offline sources.
tools/flatpak-prepare.sh windows/<version>

# 2. Build the unpacked application tree.
# If flatpak-builder cannot find the user-installed runtimes, also export
# FLATPAK_SYSTEM_DIR="$HOME/.local/share/flatpak" for this command.
flatpak-builder --user --install-deps-from=flathub \
  --force-clean --disable-rofiles-fuse \
  flatpak/build flatpak/io.github.nichu42.wire-desktop-linux.yml

# 3. Export a test repository and bundle.
tools/flatpak-repo.sh flatpak/build flatpak/repo \
  io.github.nichu42.wire-desktop-linux <version> - "" flatpak/dist

# 4. Install the unsigned test repository and run the smoke test.
flatpak remote-add --user --no-gpg-verify --if-not-exists wire-test \
  "file://$PWD/flatpak/repo"
flatpak install --user -y --noninteractive wire-test \
  io.github.nichu42.wire-desktop-linux
xvfb-run -a tools/smoke-test-flatpak.sh io.github.nichu42.wire-desktop-linux
```

`tools/flatpak-prepare.sh` writes `flatpak/generated-sources.json`,
`flatpak/prepared.json` and the rendered `flatpak/<app-id>.yml`; all three are
generated and ignored by Git.

The build intentionally uses the upstream tag's Electron pin and
`yarn install --immutable`; it does not run `yarn up`. This keeps the Flatpak
reproducible and offline. The AppImage continues to use the newest supported
Electron patch.

## Signing and publishing

The publish job signs the OSTree commits and summary with a dedicated GPG key.
Generate it once on a trusted machine:

```sh
tools/flatpak-keygen.sh
```

Add the two repository secrets it prints:

- `FLATPAK_GPG_PRIVATE_KEY` — base64 of the ASCII-armored private key
- `FLATPAK_GPG_KEY_ID` — the key id/fingerprint

The key is passphrase-less because Flatpak cannot prompt during a CI signing
step. Keep an offline backup and treat the GitHub secret as the only copy in
automation. The public key is published in the repository and embedded in
`wire.flatpakrepo`. `tools/flatpak-keygen.sh` creates a key that expires after
five years; rotate it before then and republish the public key.

Enable **Pages → Build and deployment → Source: GitHub Actions** once in the
repository settings. The publish job deploys `public/` to:

```text
https://nichu42.github.io/wire-desktop-linux/flatpak/
```

Publishing is draft-free but gated: the build job exports and installs a
test-signed repository, runs the smoke test and lints the manifest and
AppStream metadata; only the separate publish job receives the signing key. It
re-exports the uploaded build directory with the production key, installs and
smoke-tests the signed repository, attests the bundle, and then deploys Pages.

## CI

`.github/workflows/flatpak.yml` runs:

- daily at 06:37 UTC, after the AppImage build;
- on `workflow_dispatch` with `tag`, `force` and `publish` inputs;
- on pushes to `flatpak/**`, `patches/**` or the Flatpak tooling.

The resolve job skips when the published `build-info.json` already has the same
upstream tag and Flatpak fingerprint. Push-triggered runs build and test only;
they do not publish. Scheduled and manual runs publish unless `publish=false`.

A scheduled failure opens or updates a `flatpak-failure` issue; a successful
scheduled run closes open issues.

## Known limitations

- **Autostart:** the Flatpak cannot write the host autostart directory. The
  “Launch Wire On Startup” menu item is therefore hidden in the Flatpak build.
  Use the desktop environment's startup configuration with
  `flatpak run io.github.nichu42.wire-desktop-linux --hidden`.
- **Managed configuration:** the host policy file `/etc/wire/managed.json`
  is not visible at that path inside the sandbox. Managed deployments can
  expose the host's `/etc` read-only and use `/run/host/etc/wire/managed.json`;
  see [Managed deployments](#managed-deployments).
- **Flathub:** not pursued. The listing/name/icon and Flathub-specific review
  requirements are out of scope.
- **Sandbox permissions:** GPU access is `--device=dri`. The camera is
  requested through the XDG Camera portal; the wrapper enables Chromium's
  `WebRtcPipeWireCamera` feature. There is no direct `/dev/video*` access, so
  camera capture requires a working `xdg-desktop-portal` camera backend. This
  path was verified with Electron 43.1.1; `--device=all` is not needed. If
  the desktop has no camera portal backend, video calls are not available in
  the Flatpak; use the AppImage. The microphone uses PulseAudio; keyring uses
  the host Secret Service. The tray talks to
  `org.kde.StatusNotifierWatcher`; screen sharing uses the normal PipeWire
  portal where available.
- **Profile:** the Flatpak uses `~/.var/app/<app-id>/`, separate from the
  AppImage's `~/.config/Wire`.
- **Update downloads:** every publish exports into a fresh OSTree repository,
  so Pages carries only the newest commit and no N-1→N static delta exists.
  `flatpak update` still works, but it transfers the new commit in full instead
  of a delta.

## Managed deployments

The Linux managed-device signal is still `/etc/wire/managed.json` on the host.
Flatpak cannot expose only `/etc/wire` because `/etc` is a reserved path; the
narrowest available option is the `host-etc` permission, which mounts the
host's entire `/etc` read-only at `/run/host/etc`.

Managed deployments can opt in per user or system-wide:

```sh
flatpak override --user --filesystem=host-etc:ro \
  io.github.nichu42.wire-desktop-linux
# or, for a system-wide deployment (requires root):
sudo flatpak override --system --filesystem=host-etc:ro \
  io.github.nichu42.wire-desktop-linux
```

The app reads `/run/host/etc/wire/managed.json` when `FLATPAK_ID` is set.
Relaunch the app after applying the override; managed status is read once per
session. This exposes the host's `/etc` read-only to the app, so apply it only
on managed devices where that tradeoff is acceptable. The AppImage reads
`/etc/wire/managed.json` directly and needs no override.

## Troubleshooting

- **No camera or video:** the Flatpak uses the XDG Camera portal. Check that
  `xdg-desktop-portal` and a desktop backend (GNOME/KDE) are running, and reset
  a previously denied prompt with
  `flatpak permission-remove devices camera io.github.nichu42.wire-desktop-linux`.
  Do not add `--device=all`; it is not needed and grants broad host device
  access.
- **No keyring / encrypted cookie warning:** make sure a Secret Service
  (GNOME Keyring/KWallet) is running in the session.
- **No tray icon on GNOME:** install the AppIndicator extension; Flatpak does
  not change GNOME's tray behavior.
- **Screen sharing shows the wrong content:** use PipeWire and the desktop's
  portal; try `--ozone-platform=x11` as an AppImage-style fallback.
- **`wire://` opens the wrong install:** remove one of the AppImage/Flatpak
  installs, or set the handler explicitly.
- **Logs:** `~/.var/app/io.github.nichu42.wire-desktop-linux/config/Wire/` and
  `journalctl --user`. Redact personal data before sharing.
