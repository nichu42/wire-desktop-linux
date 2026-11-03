# Security policy

## Scope

This repository builds and distributes an unofficial Linux AppImage of the
Wire desktop client. It does not contain Wire's server code or the web app.

In scope:

- the build workflow, release artifacts and update metadata in this
  repository;
- the Linux runtime patch in `patches/`;
- the installer (`install.sh`) and desktop/AppArmor integration files.

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

Include the release tag, the AppImage checksum, the affected component and a
reproduction. Do not attach Wire account data, message contents or unredacted
logs.

You can expect an acknowledgement within a few days. Because this is a
volunteer build project, there is no bug bounty.

## Verifying releases

Every release includes `SHA256SUMS` and a Sigstore build-provenance
attestation:

```bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo nichu42/wire-desktop-linux
```

The `.zsync` file is used by Gear Lever for update detection; it is not a
signature.

## Build provenance

Releases are built by the `build-linux.yml` workflow from a public upstream
tag. `build-info.json` records the upstream commit, Electron and
electron-builder versions, patch fingerprint and lockfile hash. The build job
runs with a read-only token; only the separate publish job can write releases.
