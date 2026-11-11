# Security policy

## Scope

This repository builds and distributes an unofficial Linux AppImage and a
GitHub-hosted Flatpak of the Wire desktop client. It does not contain Wire's
server code or the web app.

In scope:

- the AppImage and Flatpak build workflows, release artifacts and update
  metadata in this repository;
- the Linux runtime patches in `patches/`;
- the installer (`install.sh`), desktop/AppArmor integration files and the
  Flatpak signing/repository setup.

Out of scope (report upstream):

- vulnerabilities in Wire's application code, protocol or servers — contact
  Wire via <https://wire.com/security/> or the
  [wire-desktop security policy](https://github.com/wireapp/wire-desktop/blob/dev/SECURITY.md);
- vulnerabilities in Electron itself — report to the Electron project, then
  open an issue here if the pinned build is affected.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** on this repository
(Security → Report a vulnerability). Do not open a public issue for a
vulnerability.

Include the release tag, the AppImage checksum or Flatpak ref/commit, the
affected component and a reproduction. Do not attach Wire account data, message contents or unredacted
logs.

You can expect an acknowledgement within a few days. Because this is a
volunteer build project, there is no bug bounty.

## Verifying releases

Every AppImage release includes `SHA256SUMS` and a Sigstore
build-provenance attestation:

```bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo nichu42/wire-desktop-linux
```

The `.zsync` file is used by Gear Lever for update detection; it is not a
signature.

The Flatpak repository is separate. `wire.flatpakrepo` embeds the public key;
the signing-key fingerprint and build metadata are published in
`https://nichu42.github.io/wire-desktop-linux/flatpak/build-info.json`:

```bash
flatpak remote-info --user wire io.github.nichu42.wire-desktop-linux
flatpak info --user io.github.nichu42.wire-desktop-linux
```

Do not install a Flatpak whose summary is not signed by that key. The Flatpak
bundle also gets a Sigstore build-provenance attestation from the workflow.

## Build provenance

AppImage releases are built by the `build-linux.yml` workflow from a public
upstream tag. `build-info.json` records the upstream commit, Electron and
electron-builder versions, patch fingerprint and lockfile hash. The build job
runs with a read-only token; only the separate publish job can write releases.

Flatpak builds are produced by `flatpak.yml` from the same upstream tag, with
the upstream lockfile and `flatpak-node-generator` sources. The build job is
read-only; only the publish job receives the Flatpak signing key and can deploy
Pages. The published `build-info.json` records the upstream commit, Electron
pin, Flatpak fingerprint, bundle SHA-256 and signing-key fingerprint.
