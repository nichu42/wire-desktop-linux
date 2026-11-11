# AGENTS.md

Instructions for agents working in this repository.

## What this is

Unofficial Linux AppImage and Flatpak builds of Wire Desktop, produced from a
fork of [`wireapp/wire-desktop`](https://github.com/wireapp/wire-desktop).
Upstream removed Linux support; this fork rebuilds the Electron wrapper from
upstream release tags and publishes the AppImage plus a signed, GitHub-hosted
Flatpak repository.

- Repository: `nichu42/wire-desktop-linux` (public fork; keep the fork
  relationship intact).
- Default branch: `linux` — project files, workflows and tooling.
- `dev`: pristine upstream mirror. Never build from it directly.
- Upstream build source: newest tag matching `windows/*`.
- Current release: `gh release list --repo nichu42/wire-desktop-linux --limit 1`.
  Do not hardcode version numbers in these docs.
- AppImage is the primary single-file artifact; the Flatpak is published from a
  signed OSTree repository on GitHub Pages. Flathub is intentionally out of
  scope. Keep packaging-specific decisions in `tools/` and `flatpak/` instead of
  assuming one format.

## Invariants

1. Build from upstream release tags, not `dev` HEAD.
2. The only upstream source change is `patches/01-linux-runtime.patch`, applied
   with `git apply --3way`. If it fails, continue unpatched and say so in the
   release notes; never delete the tests to make it apply.
3. Never publish without the full gate: upstream tests, artifact assertions,
   runtime smoke on Ubuntu 24.04 and 22.04, and draft-asset verification.
   Releases are created as drafts and only published after verification.
4. The `build` job is read-only: `contents: read`, `persist-credentials:
   false`, no `GH_TOKEN` in its environment. Only `publish` gets write
   permissions. Never give the build job a write token.
5. Pin every third-party action to a full commit SHA. Dependabot updates them.
   Do not use `ubuntu-latest` for the artifact build; use explicit LTS labels.
6. Do not add a lockfile or pin app dependencies in this repository. Resolve
   Electron and electron-builder at build time with `yarn up`; never edit the
   lockfile with `jq`, add a `resolutions` block, or use
   `COREPACK_ENABLE_STRICT`/immutable-install environment hacks.
7. Keep `@electron/fuses` at upstream's `1.8.x`. The 2.x `exports` map breaks
   upstream's `moduleResolution: node` typecheck.
8. Do not put `--no-sandbox` in the desktop entry. electron-builder 26.18 adds
   it by default when `toolsets.appimage` is unset; `appImage.executableArgs:
   []` and `buildVersion` in `tools/electron-builder.config.cjs` must stay.
9. Do not use Playwright for the runtime smoke test. Production fuses disable
   `--inspect`; `tools/smoke-test.sh` launches the extracted AppImage and
   checks for a window plus `https://app.wire.com` in the app log.
10. Keep Gear Lever compatibility: `.upd_info` must contain
    `gh-releases-zsync|nichu42|wire-desktop-linux|latest|Wire-*x86_64.AppImage.zsync`
    and every release must include the matching `.zsync` asset.
11. Keep `PINNED` in `.github/workflows/runner-freshness.yml` in sync with the
    `runner` input default in `build-linux.yml`.
12. No personal data in releases or `build-info.json`. Wire logs can contain
    member data: never commit them or paste them outside the session.
13. The Flatpak is a source build: apply both runtime patches, fail closed if
    either does not apply, and do not package a Flatpak without the assertions
    and smoke test. The AppImage keeps its best-effort patch behavior.
14. The Flatpak uses the upstream tag's `yarn.lock` and Electron/electron-builder
    pins; do not run `yarn up` or modify the lockfile in the Flatpak build. A
    documented security exception may vendor an updated lockfile and regenerated
    sources.
15. The Flatpak never passes `--no-sandbox`; it uses zypak from the Electron2
    BaseApp and the same fuses as the AppImage. Camera access goes through the
    XDG Camera portal with `WebRtcPipeWireCamera`; do not add `--device=all`.
    Do not add AppArmor/AppImage update metadata to the Flatpak.
16. The Flatpak signing key is available only to the publish job. Build jobs are
    read-only and must never receive `FLATPAK_GPG_PRIVATE_KEY`. Publish only
    from the protected `linux` branch or a tag.
17. Keep the GitHub Pages repository URL and Flatpak app ID stable. A change
    breaks installed remotes; the app ID is fixed before the first public
    release.

## Layout

| Path | Purpose |
|---|---|
| `README.md` | User-facing install/update/verification docs |
| `SECURITY.md` | Private reporting, scope, attestation verification |
| `install.sh` | Non-Gear-Lever install/update helper |
| `patches/01-linux-runtime.patch` | Restores the Linux runtime behavior upstream removed |
| `patches/02-flatpak-runtime.patch` | Hides the Flatpak-incompatible autostart toggle |
| `flatpak/` | Manifest template, desktop entry, metainfo, zypak wrapper, Flatpak electron-builder config |
| `tools/flatpak-prepare.sh` | Resolves the tag/config, generates offline sources, renders the manifest |
| `tools/flatpak-render-manifest.mjs` | Fills the Flatpak manifest template |
| `tools/flatpak-repo.sh` | Exports/signs the OSTree repo and builds a bundle |
| `tools/flatpak-keygen.sh` | Generates the Flatpak signing key and prints the secrets |
| `tools/assert-flatpak.mjs` | Asserts the installed `/app` tree (asar, fuses, metadata, size) |
| `tools/smoke-test-flatpak.sh` | `flatpak run` runtime smoke test (Xvfb) |
| `docs/flatpak.md` | Flatpak build, signing and repository operations |
| `tools/stamp-config.mjs` | Writes production `electron/wire.json` + `package.json` |
| `tools/electron-builder.config.cjs` | AppImage packaging, files, desktop entry, fuses hook |
| `tools/after-pack.cjs` | Flips the production Electron fuses |
| `tools/assert-artifact.mjs` | Asserts asar config, fuses, desktop, update info, zsync, size |
| `tools/smoke-test.sh` | Direct-launch runtime smoke test (Xvfb) |
| `tools/embed-updateinfo.mjs` | Writes Gear Lever update info into `.upd_info` in place |
| `tools/release-notes.sh` | Release notes from `build-info.json` + changelog |
| `resources/` | AppStream metainfo + AppArmor profile |
| `.github/workflows/build-linux.yml` | Resolve → build → 22.04 smoke → publish |
| `.github/workflows/flatpak.yml` | Flatpak resolve → build/test → sign → Pages |
| `.github/workflows/runner-freshness.yml` | Weekly runner migration check + canary |
| `.github/workflows/lint.yml` | actionlint, zizmor, shellcheck, node --check |
| `.github/workflows/scorecard.yml` | OpenSSF Scorecard |
| `.github/workflows/keepalive.yml` | Monthly commit against the 60-day schedule disable |
| `.github/dependabot.yml` | GitHub Actions updates |

## CI

`build-linux.yml` triggers on the daily 05:17 UTC schedule and
`workflow_dispatch` with inputs:

- `tag` — upstream tag; empty means latest `windows/*`.
- `electron` — `supported` (default), `latest`, `upstream`.
- `builder` — `latest` (default), `upstream`.
- `force` — rebuild as a new revision.
- `runner` — default `ubuntu-26.04`; `ubuntu-latest` is for canaries.
- `publish` — default `true`; `false` skips the publish job and forces a build
  even when a release already exists.

Jobs: `resolve` → `build` → `smoke-2204` → `publish`, plus `report-failure` and
`report-success`. A canary (`publish=false`) runs the full gate but creates no
release; a failure creates a `Canary build failure` issue.

`flatpak.yml` triggers on the daily 06:37 UTC schedule, `workflow_dispatch`
(`tag`, `force`, `publish`) and pushes to the Flatpak files. Jobs:
`resolve` → `build` (offline source build, test-signed repo, smoke, manifest/
AppStream lint) → `publish` (production GPG signing, signed install/smoke,
attestation, Pages).
A skipped resolve means the published tag/fingerprint is current. Push runs do
not publish; a scheduled failure opens a `flatpak-failure` issue.

Runner pins:

- artifact `resolve`/`build`: `ubuntu-26.04` (green canary);
- Flatpak `resolve`/`build`/`publish`: `ubuntu-24.04`;
- `publish`, reporting, lint, Scorecard, keepalive: `ubuntu-24.04`;
- compatibility smoke: `ubuntu-22.04`.

Runner freshness runs weekly on `ubuntu-latest`. If latest is newer than
`PINNED`, it opens a `runner-freshness` issue and dispatches a no-publish
canary on the new image. If the pinned image is ahead, it does nothing; when
they match, it closes stale issues.

Useful commands:

```bash
# canary on the moving latest image, no release
gh workflow run build-linux.yml --repo nichu42/wire-desktop-linux \
  -f runner=ubuntu-latest -f publish=false

# force a revision release
gh workflow run build-linux.yml --repo nichu42/wire-desktop-linux \
  -f tag=windows/3.46.5382 -f force=true

# Flatpak build/test only (no Pages publish)
gh workflow run flatpak.yml --repo nichu42/wire-desktop-linux \
  -f tag=windows/3.46.5382 -f publish=false

gh run list --repo nichu42/wire-desktop-linux --limit 5
gh run watch <run-id> --repo nichu42/wire-desktop-linux --compact
gh issue list --repo nichu42/wire-desktop-linux --label build-failure
gh issue list --repo nichu42/wire-desktop-linux --label flatpak-failure
```

## Releases

- App version = upstream tag suffix (`3.46.5382`).
- Tags: `v<version>` for the first build, `v<version>-rN` for rebuilds caused
  by Electron/tooling/fingerprint changes.
- Assets: AppImage, `.zsync`, `wire-desktop.png`,
  `wire-desktop.metainfo.xml`, `apparmor.profile`, `SHA256SUMS`,
  `build-info.json`.
- `build-info.json` (schema 1) records upstream tag/commit, upstream and
  shipped Electron, builder, fuses, revision, fingerprint, lockfile hash,
  policy, EOL flag, build time and run id.
- Publish flow: draft → attest provenance → download assets back and verify →
  publish. Never upload directly to a published release.
- The Flatpak is **not** a GitHub release asset. It is published to
  `https://nichu42.github.io/wire-desktop-linux/flatpak/` with a signed OSTree
  repository, `wire.flatpakrepo`, `build-info.json` and the rendered manifest.
  AppImage release assets and Gear Lever metadata are unchanged.
- Verify a release:

```bash
sha256sum -c SHA256SUMS
gh attestation verify Wire-*.AppImage --repo nichu42/wire-desktop-linux
```

Do not prune releases; they are kept for rollback and version pinning.

## Dependency policy

- **Electron**: read the upstream pin from the tag. Use the newest patch of
  that major; if the upstream major is older than the newest two supported
  majors, use the oldest supported major. `electron=latest` forces the newest
  stable major; `electron=upstream` reproduces the pin.
- **electron-builder**: npm `latest`; retry with upstream's version if
  packaging fails.
- **@electron/fuses**: upstream pin (`1.8.x`).
- **App dependencies**: upstream's tested set; never auto-bump them.
- Apply overrides with
  `yarn up electron@<v> electron-builder@<v> @electron/fuses@<v>`, then
  `yarn install --immutable`. For the AppImage, `postinstall: yarn configure`
  must run; it fetches the production config and icons. The Flatpak replaces it
  with the pinned offline config sources.
- **Flatpak:** the upstream tag's lockfile and Electron/electron-builder pins are
  used unchanged with `yarn install --immutable`; `yarn up` is forbidden in the
  Flatpak build. `flatpak-node-generator` supplies all Yarn/Electron sources and
  the production config archive is pinned by URL + SHA-256. The Flatpak may
  trail the AppImage by Electron patch releases; a documented security exception
  may vendor a new lockfile and regenerated sources.

## Local checks

The build runs in CI; a full local build needs Node 22 (`.node-version`), the
committed Yarn 3.3.1, Xvfb, `x11-utils`, `zsync`, `binutils` and `shellcheck`.
The Flatpak build additionally needs Flatpak, `flatpak-builder`,
`flatpak-node-generator`, `jq` and `patch`.

```bash
node .yarn/releases/yarn-3.3.1.cjs install
./node_modules/.bin/tsc --noEmit                     # typecheck
xvfb-run -a yarn test                                # upstream suite
node tools/stamp-config.mjs                          # BUILD_NUMBER required
yarn build:prepare
RELEASE_REVISION= yarn electron-builder --linux AppImage --x64 \
  --config tools/electron-builder.config.cjs

# Flatpak (writes generated sources and a rendered manifest)
tools/flatpak-prepare.sh windows/<version>
flatpak-builder --user --install-deps-from=flathub \
  --force-clean --disable-rofiles-fuse \
  flatpak/build flatpak/io.github.nichu42.wire-desktop-linux.yml
```

The CI build clones upstream into `src/`, applies the patch, copies `tools/`
and `resources/` into it, then stamps/builds/packages. A local full build must
replicate that layout. The Flatpak build applies `patches/01` **and**
`patches/02` inside `flatpak-builder` and fails closed if either fails.

Manual acceptance after a build: launch, log in, send a message, place one call
and try screen sharing, verify `wire://`, and confirm the tray/version. The
AppImage's old and new clients share `~/.config/Wire`; the Flatpak uses
`~/.var/app/io.github.nichu42.wire-desktop-linux/`. Only one instance should run
at a time.

## Gear Lever and install

Gear Lever is the primary AppImage update path. The AppImage embeds the update source;
`.zsync` SHA-1 comparison drives detection. Users add the AppImage once and use
Gear Lever's Update button. `install.sh` is the fallback for systems without
Gear Lever; do not use both for the same install.

`install.sh` supports `--version`, `--dry-run`, `--uninstall` and `--apparmor`.
`--apparmor` is the only sudo path and must remain explicit.

## Common tasks

- **New upstream release**: nothing; the schedule builds it. If a release is
  wrong, dispatch with `force=true` and a new revision is produced.
- **Runtime patch fails**: the build continues unpatched and the release notes
  warn. Refresh the patch by checking out the target tag and re-applying the
  curated runtime revert for `electron/src` (menu, tray, autostart, shortcuts,
  portable data, MDM, plus the two test files). Validate with
  `git apply --3way --check` against a clean tag checkout.
- **Patch/types fail after an upstream change**: fix the patch, not the tests;
  keep the restored `IS_LINUX` platform field and `appImagePath` test data.
- **Startup hidden**: the Linux menu's `Start Hidden in Tray` toggle stores
  `startHidden` in `init.json`; `--hidden`/`--startup` still force it. Defer
  `electron-window-state` restore until the first `show`, because `maximize()`
  on a hidden window makes Electron show it.
- **Runner migration**: update the `runner` default and fixed `runs-on`
  entries, update `PINNED`, run a canary on the new image, then push. The
  weekly check will flag the next migration.
- **Packaging regression**: run the canary; check `assert-artifact` output and
  the smoke log. Keep `files` excludes root-relative: a `!**/config` glob once
  stripped `@wireapp/commons/lib/config` and broke startup. Never add a
  positive `**/*` to `files`: it packs `node_modules/electron` (316 MiB of
  dev-only Electron). `typescript` is a production dependency of
  `@wireapp/protocol-messaging` and therefore ships legitimately.
- **Build failed on schedule**: check the `build-failure` issue/run log, fix
  the patch or tooling, push; a successful scheduled run closes the issue.
- **Gear Lever metadata**: if detection breaks, verify `.upd_info`, the
  `.zsync` SHA-1, the asset glob and `/releases/latest`.
- **Flatpak new upstream release**: the `flatpak.yml` schedule resolves it.
  If the config tag or lockfile changed, rerun `tools/flatpak-prepare.sh` and
  commit any packaging changes; the build job regenerates sources each run.
- **Flatpak patch fails**: the build fails closed; refresh `patches/01` and/or
  `patches/02` against the target tag. Never ship a Flatpak without both.
- **Flatpak repository/signing**: run `tools/flatpak-keygen.sh` once, add the
  `FLATPAK_GPG_PRIVATE_KEY` and `FLATPAK_GPG_KEY_ID` secrets, enable Pages with
  GitHub Actions as the source. Keep the key and Pages URL stable.
- **Flatpak managed config**: do not add `/etc/wire` to `--filesystem`; `/etc`
  is reserved and subpaths do not work. Managed deployments can opt in with
  `--filesystem=host-etc:ro`; the app reads `/run/host/etc/wire/managed.json`.
  This exposes all of host `/etc` read-only, so use it only on managed devices.
- **Flatpak Pages too large**: prune with `flatpak build-update-repo --prune
  --prune-depth=2`; if the 1 GB Pages limit is still exceeded, move the OSTree
  objects to an object store and update the `.flatpakrepo` URL.
- **Flatpak build failed on schedule**: check the `flatpak-failure` issue/run
  log; push a fix; a successful scheduled run does not yet auto-close it.

## Repository settings

Public fork; default branch `linux`; Actions enabled with read-only default;
workflows `build-linux`, `flatpak`, `lint`, `scorecard`, `keepalive`,
`runner-freshness` enabled; upstream workflows removed from `linux`. Issues
enabled; private vulnerability reporting, secret scanning and push protection
enabled. GitHub Pages uses GitHub Actions as the source; the Flatpak site is
`https://nichu42.github.io/wire-desktop-linux/flatpak/`. The automatic
`GITHUB_TOKEN` is used for normal operations. The Flatpak publish job
additionally uses `FLATPAK_GPG_PRIVATE_KEY` and `FLATPAK_GPG_KEY_ID`; no
personal access tokens are used.

Scorecard publishes SARIF to the code-scanning page. Those alerts are
repository-health checks, not a scan of upstream source. The by-design ones
(branch protection, token permissions, SAST, fuzzing, code review, CII badge,
repo-age Maintained)
and the upstream dependency advisories are dismissed as "won't fix" with a
reason; keep the Scorecard workflow running. Revisit dismissed alerts when the
release model changes, and do not blanket-disable SARIF upload.

Upstream project: <https://github.com/wireapp/wire-desktop> ·
Removal context: <https://github.com/wireapp/wire-desktop/issues/9747> ·
Gear Lever: <https://gearlever.mijorus.it>
