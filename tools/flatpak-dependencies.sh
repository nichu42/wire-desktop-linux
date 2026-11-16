#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Report whether the Flatpak build uses supported dependencies.
#
# Resolves the Flatpak Electron and electron-builder versions using the
# repository's dependency policy (`tools/resolve-deps.sh`), and checks the
# Freedesktop runtime, Electron2 BaseApp and Node SDK extension against
# Flathub and the Node release schedule.
#
# Usage:
#   tools/flatpak-dependencies.sh [--tag windows/x.y.z] [--runtime branch] \
#     [--node major] [--report FILE]
#
# The Flathub checks need flatpak with a configured `flathub` remote.
# Exit status: 0 = all current, 1 = findings, 2 = incomplete lookup
# (a registry, Flathub or release-schedule query failed).

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TAG=""
RUNTIME_VERSION="${RUNTIME_VERSION:-}"
NODE_VERSION="${NODE_VERSION:-}"
REPORT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift 2 ;;
    --runtime) RUNTIME_VERSION="${2:-}"; shift 2 ;;
    --node) NODE_VERSION="${2:-}"; shift 2 ;;
    --report) REPORT="${2:-}"; shift 2 ;;
    -h | --help)
      sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "flatpak-dependencies: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for cmd in curl jq flatpak date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "flatpak-dependencies: missing required command: $cmd" >&2
    exit 2
  fi
done

if [ -z "$RUNTIME_VERSION" ] || [ "$RUNTIME_VERSION" = "latest" ] || [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" = "latest" ]; then
  resolve_args=()
  if [ -n "$RUNTIME_VERSION" ]; then
    resolve_args+=(--runtime "$RUNTIME_VERSION")
  fi
  if [ -n "$NODE_VERSION" ]; then
    resolve_args+=(--node "$NODE_VERSION")
  fi
  if flatpak_env="$(bash "$ROOT/tools/flatpak-resolve.sh" "${resolve_args[@]}" 2>/dev/null)"; then
    if [ -z "$RUNTIME_VERSION" ] || [ "$RUNTIME_VERSION" = "latest" ]; then
      RUNTIME_VERSION="$(jq -r '.runtime' <<<"$flatpak_env")"
    fi
    if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" = "latest" ]; then
      NODE_VERSION="$(jq -r '.node' <<<"$flatpak_env")"
    fi
  else
    echo "flatpak-dependencies: could not resolve runtime/Node from Flathub" >&2
    exit 2
  fi
fi

if [ -z "$TAG" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "flatpak-dependencies: pass --tag or install gh" >&2
    exit 2
  fi
  TAG="$(gh api "repos/wireapp/wire-desktop/releases?per_page=50" \
    --jq '[.[] | select(.tag_name | startswith("windows/"))][0].tag_name')"
fi

if ! [[ "$TAG" =~ ^windows/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "flatpak-dependencies: invalid upstream tag: $TAG" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL "https://raw.githubusercontent.com/wireapp/wire-desktop/$TAG/package.json" \
  -o "$tmp/package.json"; then
  echo "flatpak-dependencies: could not fetch upstream package.json for $TAG" >&2
  exit 2
fi

upstream_electron="$(jq -r '.devDependencies.electron // empty' "$tmp/package.json")"
upstream_builder="$(jq -r '.devDependencies["electron-builder"] // empty' "$tmp/package.json")"
yarn_pin="$(jq -r '.packageManager // empty' "$tmp/package.json" | sed -n 's/^yarn@//p')"

findings=()
notes=()
lookup_failed=false

# Electron & electron-builder: Flatpak follows the same `supported` / `latest`
# policy as the AppImage via `tools/resolve-deps.sh`.
electron_status="❔ unknown"
electron=""
builder=""
latest_electron=""
oldest_supported=""
eol_escape=false
if deps="$(bash "$ROOT/tools/resolve-deps.sh" --package-json "$tmp/package.json" \
  --electron supported --builder latest 2>/dev/null)"; then
  electron="$(jq -r '.electron' <<<"$deps")"
  builder="$(jq -r '.builder' <<<"$deps")"
  latest_electron="$(jq -r '.latest_electron' <<<"$deps")"
  oldest_supported="$(jq -r '.oldest_supported_major' <<<"$deps")"
  target_major="$(jq -r '.target_major' <<<"$deps")"
  latest_major="${latest_electron%%.*}"
  eol_escape="$(jq -r '.eol_escape' <<<"$deps")"
  if [ "$target_major" -lt "$oldest_supported" ]; then
    electron_status="❌ out of support"
    findings+=("Resolved Electron \`$electron\` is outside the supported window (oldest supported major: $oldest_supported, npm latest: $latest_electron).")
  elif [ "$target_major" -lt "$latest_major" ]; then
    electron_status="✅ supported"
    notes+=("Flatpak builds with Electron \`$electron\` (upstream pin: \`$upstream_electron\`), inside the supported window (npm latest: \`$latest_electron\`).")
  else
    electron_status="✅ current"
  fi
  if [ "$eol_escape" = "true" ]; then
    notes+=("Upstream Electron pin \`$upstream_electron\` is outside the supported window; Flatpak upgrades to \`$electron\`.")
  fi
else
  lookup_failed=true
  notes+=("Could not resolve the Electron/electron-builder versions from the npm registry.")
fi

# Freedesktop runtime, Electron2 BaseApp and the Node SDK extension: Flathub
# drops end-of-life Platform branches from its summary, so a missing runtime
# branch is the strongest available end-of-life signal.
runtime_status="❔ unknown"
base_status="❔ unknown"
node_status="❔ unknown"
newest_runtime=""
newest_node=""
refs="$tmp/refs"
# Use whichever Flathub installation is configured; a host may only have the
# system remote.
flathub_args=()
if flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub; then
  flathub_args=(--user)
elif flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
  flathub_args=(--system)
fi
if flatpak remote-ls "${flathub_args[@]}" flathub --columns=ref,branch >"$refs" 2>"$tmp/refs.err"; then
  mapfile -t runtime_branches < <(
    awk -F'\t' '$1 ~ /^runtime\/org\.freedesktop\.Platform\/x86_64\// { print $2 }' "$refs" |
      sort -Vu
  )
  if [ "${#runtime_branches[@]}" -eq 0 ]; then
    notes+=("Flathub returned no org.freedesktop.Platform branches.")
  else
    newest_runtime="${runtime_branches[-1]}"
    if ! printf '%s\n' "${runtime_branches[@]}" | grep -qx "$RUNTIME_VERSION"; then
      runtime_status="❌ not on Flathub"
      findings+=("Runtime branch \`$RUNTIME_VERSION\` is not published on Flathub (likely end of life).")
    elif [ "$newest_runtime" != "$RUNTIME_VERSION" ]; then
      runtime_status="⚠️ newer branch available"
      findings+=("Freedesktop runtime \`$newest_runtime\` is available; this build uses \`$RUNTIME_VERSION\`.")
    else
      runtime_status="✅ current"
    fi

    branch_yy="${RUNTIME_VERSION%%.*}"
    branch_mm="${RUNTIME_VERSION##*.}"
    age_months=$(((10#$(date -u +%Y) - (2000 + 10#$branch_yy)) * 12 + (10#$(date -u +%m) - 10#$branch_mm)))
    if [ "$age_months" -gt 20 ]; then
      findings+=("Runtime branch \`$RUNTIME_VERSION\` is about $age_months months old; Freedesktop SDK branches are supported for roughly two years.")
      if [ "$runtime_status" = "✅ current" ]; then
        runtime_status="⚠️ aging"
      fi
    fi
  fi

  if awk -F'\t' -v ref="app/org.electronjs.Electron2.BaseApp/x86_64/$RUNTIME_VERSION" \
    '$1 == ref { found = 1 } END { exit !found }' "$refs"; then
    base_status="✅ current"
  else
    base_status="❌ not on Flathub"
    findings+=("org.electronjs.Electron2.BaseApp is not available for runtime $RUNTIME_VERSION on Flathub.")
  fi

  mapfile -t node_majors < <(
    awk -F'\t' -v suffix="/x86_64/$RUNTIME_VERSION" '
      $1 ~ /Sdk\.Extension\.node[0-9]+\/x86_64\// &&
        substr($1, length($1) - length(suffix) + 1) == suffix { print $1 }
    ' "$refs" | sed -E 's#.*node([0-9]+)/.*#\1#' | sort -nu
  )
  if [ "${#node_majors[@]}" -gt 0 ]; then
    newest_node="${node_majors[-1]}"
  fi
  if awk -F'\t' -v ref="runtime/org.freedesktop.Sdk.Extension.node$NODE_VERSION/x86_64/$RUNTIME_VERSION" \
    '$1 == ref { found = 1 } END { exit !found }' "$refs"; then
    node_status="✅ available"
  else
    node_status="❌ extension missing"
    findings+=("org.freedesktop.Sdk.Extension.node$NODE_VERSION is not available for runtime $RUNTIME_VERSION on Flathub.")
  fi
else
  lookup_failed=true
  notes+=("Could not query Flathub: $(tail -1 "$tmp/refs.err" 2>/dev/null || echo 'flatpak remote-ls failed').")
fi

node_eol=""
eol_json=""
if eol_json="$(curl -fsSL https://endoflife.date/api/nodejs.json 2>/dev/null)"; then
  node_eol="$(jq -r --arg c "$NODE_VERSION" '.[] | select(.cycle == $c) | .eol' <<<"$eol_json" | head -1)"
else
  lookup_failed=true
  notes+=("Could not fetch the Node release schedule from endoflife.date.")
fi

if [ "$node_eol" = "true" ]; then
  findings+=("Node $NODE_VERSION is marked end-of-life by endoflife.date.")
  if [ "$node_status" != "❌ extension missing" ]; then
    node_status="❌ end of life"
  fi
elif [[ "$node_eol" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  days_left=$((($(date -u -d "$node_eol" +%s) - $(date -u +%s)) / 86400))
  if [ "$days_left" -lt 0 ]; then
    findings+=("Node $NODE_VERSION reached end of life on $node_eol.")
    if [ "$node_status" != "❌ extension missing" ]; then
      node_status="❌ end of life"
    fi
  elif [ "$days_left" -lt 180 ]; then
    findings+=("Node $NODE_VERSION reaches end of life on $node_eol ($days_left days).")
    if [ "$node_status" != "❌ extension missing" ]; then
      node_status="⚠️ EOL in $days_left days"
    fi
  fi
elif [ "$node_eol" != "false" ] && [ "$node_eol" != "null" ] && [ -n "$eol_json" ]; then
  lookup_failed=true
  notes+=("Could not determine the Node $NODE_VERSION release schedule.")
fi
if [ -n "$newest_node" ] && [ "$newest_node" -gt "$NODE_VERSION" ]; then
  notes+=("Node SDK extension \`node$newest_node\` is published on Flathub; this build uses \`node$NODE_VERSION\`.")
fi

{
  echo "## Flatpak dependency check"
  echo
  echo "Upstream tag: \`$TAG\`"
  echo
  echo "| Dependency | Flatpak | Available / policy | Status |"
  echo "| --- | --- | --- | --- |"
  echo "| Electron | \`${electron:-unknown}\` (upstream \`${upstream_electron:-unknown}\`) | \`${latest_electron:-unknown}\`; oldest supported: \`${oldest_supported:-unknown}\` | $electron_status |"
  echo "| electron-builder | \`${builder:-unknown}\` (upstream \`${upstream_builder:-unknown}\`) | \`latest\` policy | ℹ️ policy |"
  echo "| Yarn | \`${yarn_pin:-unknown}\` | build-time pin | ℹ️ upstream |"
  echo "| Freedesktop runtime | \`$RUNTIME_VERSION\` | newest on Flathub: \`${newest_runtime:-unknown}\` | $runtime_status |"
  echo "| Electron2 BaseApp | \`$RUNTIME_VERSION\` | branch on Flathub | $base_status |"
  echo "| Node SDK extension | \`node$NODE_VERSION\` | newest on Flathub: \`${newest_node:+node$newest_node}\`${node_eol:+; EOL $node_eol} | $node_status |"
  echo
  if [ "${#findings[@]}" -gt 0 ]; then
    echo "### Findings"
    echo
    for finding in "${findings[@]}"; do
      echo "- $finding"
    done
  else
    echo "No out-of-support dependencies found."
  fi
  if [ "${#notes[@]}" -gt 0 ]; then
    echo
    echo "### Notes"
    echo
    for note in "${notes[@]}"; do
      echo "- $note"
    done
  fi
  echo
  echo "_Generated $(date -u +%FT%TZ) by \`tools/flatpak-dependencies.sh\`._"
} >"$tmp/report.md"

if [ -n "$REPORT" ]; then
  cp "$tmp/report.md" "$REPORT"
  echo "flatpak-dependencies: report written to $REPORT"
else
  cat "$tmp/report.md"
fi

if [ "${#findings[@]}" -gt 0 ]; then
  echo "flatpak-dependencies: ${#findings[@]} finding(s)" >&2
  exit 1
fi
if [ "$lookup_failed" = "true" ]; then
  echo "flatpak-dependencies: one or more lookups failed; result is incomplete" >&2
  exit 2
fi
echo "flatpak-dependencies: all dependencies supported" >&2
