# Flatpak distribution decision

**Status:** implemented; the first publish requires the one-time key and Pages
setup below. The Flatpak is published from a signed, GitHub-hosted OSTree
repository; Flathub is intentionally out of scope. See
[`docs/flatpak.md`](flatpak.md) for build, signing and repository operations.

## Decision

Ship the Flatpak in addition to the AppImage from:

```text
https://nichu42.github.io/wire-desktop-linux/flatpak/
```

Users add the remote once and install/update through `flatpak`. The AppImage,
Gear Lever metadata and `install.sh` are unchanged.

## Why not Flathub

Flathub was considered first but is not used:

- its current rules require the application name and icon to be distinct from
  the vendor's for an unofficial build, which would require a rebrand of a
  wrapper that still displays Wire's hosted web UI;
- its generative-AI policy requires the manifest and submission PR to be
  human-authored and limits undisclosed AI-assisted material;
- the old `com.wire.WireDesktop` package is archived as EOL and repacked a
  `.deb`, so it cannot be reused, and a community rebuild would need to pass
  duplicate/thin-wrapper/development-history review.

The GitHub-hosted repository has none of those constraints, gives the project
control over signing and update cadence, and still provides automatic
`flatpak update` for users. If the project later wants Flathub, the source build
and metadata can be submitted separately; that is a policy decision, not a
rewrite of the build.

## Implemented pieces

- `flatpak/` — manifest template, desktop entry, metainfo, zypak wrapper and
  Flatpak-specific electron-builder config.
- `patches/01-linux-runtime.patch` and `patches/02-flatpak-runtime.patch` —
  upstream Linux runtime behavior, the Flatpak autostart menu adjustment and
  the `/run/host/etc` managed-config fallback.
- `tools/flatpak-prepare.sh` — resolves the tag, pins the production config,
  generates offline Yarn/Electron sources and renders the manifest.
- `tools/flatpak-repo.sh` — exports and signs the OSTree repository, refreshes
  static deltas and creates a bundle.
- `tools/assert-flatpak.mjs` — fails the build if the installed `/app` tree does
  not match the production expectations.
- `tools/smoke-test-flatpak.sh` — launches the installed Flatpak and waits for
  `app.wire.com`.
- `tools/flatpak-keygen.sh` — creates the signing key and prints the secrets.
- `.github/workflows/flatpak.yml` — resolve, offline build, test-signed install,
  lint, production signing, signed install/smoke, attestation and Pages deploy.
- `docs/flatpak.md` — user/operator documentation.

## One-time setup

1. Run `tools/flatpak-keygen.sh` on a trusted machine.
2. Add the printed `FLATPAK_GPG_PRIVATE_KEY` and `FLATPAK_GPG_KEY_ID` repository
   secrets; delete the local private-key file.
3. Enable **Pages → Build and deployment → Source: GitHub Actions**.
4. Dispatch `flatpak.yml` with `publish=false` first, then with publishing
   enabled once the build passes.

## Known limitations

- The Flatpak autostart menu item is hidden; use the desktop's own startup
  configuration with `flatpak run <app-id> --hidden`.
- Managed deployments can expose host `/etc` read-only with
  `--filesystem=host-etc:ro`; the app then reads
  `/run/host/etc/wire/managed.json`. `/etc/wire:ro` alone is not possible
  because `/etc` is a reserved Flatpak path.
- Camera access uses the XDG Camera portal (`WebRtcPipeWireCamera` in the
  wrapper); no `--device=all` is required. Keyring uses the host Secret Service.
- The Flatpak profile is under `~/.var/app/<app-id>/`, separate from the
  AppImage's `~/.config/Wire`.
