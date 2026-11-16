#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Resolve the newest compatible Freedesktop runtime / Electron2 BaseApp branch
# and active LTS Node SDK extension on Flathub.
#
# Usage:
#   tools/flatpak-resolve.sh [--runtime <branch|latest>] [--node <major|latest>]

set -euo pipefail

RUNTIME_ARG="${RUNTIME_VERSION:-}"
NODE_ARG="${NODE_VERSION:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runtime) RUNTIME_ARG="${2:-}"; shift 2 ;;
    --node) NODE_ARG="${2:-}"; shift 2 ;;
    -h | --help)
      sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "flatpak-resolve: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for cmd in curl jq sort comm date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "flatpak-resolve: missing required command: $cmd" >&2
    exit 2
  fi
done

fetch_branches() {
  local app_id="$1"
  curl -fsSL --retry 3 --retry-delay 2 \
    "https://flathub.org/api/v2/summary/${app_id}" \
    | jq -r '.branches // {} | keys[]' \
    | grep -E '^[0-9]{2}\.[0-9]{2}$' \
    | sort -u || true
}

has_node_branch() {
  local major="$1"
  local branch="$2"
  local summary
  summary="$(curl -fsSL --retry 2 --retry-delay 1 \
    "https://flathub.org/api/v2/summary/org.freedesktop.Sdk.Extension.node${major}" 2>/dev/null || true)"
  [ -n "$summary" ] && jq -e --arg b "$branch" '(.branches // {}) | has($b)' <<<"$summary" >/dev/null 2>&1
}

node_candidates() {
  local today lts_json candidates=""
  today="$(date -u +%F)"
  lts_json="$(curl -fsSL --retry 3 --retry-delay 2 https://endoflife.date/api/nodejs.json 2>/dev/null || true)"
  if [ -n "$lts_json" ]; then
    candidates="$(jq -r --arg today "$today" '
      [ .[]
        | select((.lts != false) and ((.lts | tostring) <= $today) and ((.eol == false) or ((.eol | tostring) > $today)))
        | .cycle
        | select(test("^[0-9]+$"))
      ] | sort_by(tonumber) | reverse | .[]
    ' <<<"$lts_json" 2>/dev/null || true)"
  fi
  if [ -z "$candidates" ]; then
    candidates=$'32\n30\n28\n26\n24\n22'
  fi
  printf '%s\n' "$candidates"
}

resolve_node_for_runtime() {
  local branch="$1"
  local major
  while IFS= read -r major; do
    [ -n "$major" ] || continue
    if has_node_branch "$major" "$branch"; then
      printf '%s\n' "$major"
      return 0
    fi
  done < <(node_candidates)
  return 1
}

target_runtime=""
target_node=""

if [ -n "$RUNTIME_ARG" ] && [ "$RUNTIME_ARG" != "latest" ]; then
  target_runtime="$RUNTIME_ARG"
else
  platform_branches="$(fetch_branches org.freedesktop.Platform)"
  sdk_branches="$(fetch_branches org.freedesktop.Sdk)"
  base_branches="$(fetch_branches org.electronjs.Electron2.BaseApp)"
  if [ -z "$platform_branches" ] || [ -z "$sdk_branches" ] || [ -z "$base_branches" ]; then
    echo "flatpak-resolve: could not fetch Flathub summary branches" >&2
    exit 1
  fi
  common_branches="$(comm -12 <(printf '%s\n' "$platform_branches") <(printf '%s\n' "$sdk_branches") \
    | comm -12 - <(printf '%s\n' "$base_branches") \
    | sort -Vr)"
  if [ -z "$common_branches" ]; then
    echo "flatpak-resolve: no common branch across Platform, Sdk and Electron2.BaseApp" >&2
    exit 1
  fi

  if [ -n "$NODE_ARG" ] && [ "$NODE_ARG" != "latest" ]; then
    while IFS= read -r branch; do
      [ -n "$branch" ] || continue
      if has_node_branch "$NODE_ARG" "$branch"; then
        target_runtime="$branch"
        target_node="$NODE_ARG"
        break
      fi
    done <<<"$common_branches"
  else
    while IFS= read -r branch; do
      [ -n "$branch" ] || continue
      if resolved_node="$(resolve_node_for_runtime "$branch")"; then
        target_runtime="$branch"
        target_node="$resolved_node"
        break
      fi
    done <<<"$common_branches"
  fi
fi

if [ -z "$target_runtime" ]; then
  echo "flatpak-resolve: could not resolve a compatible Flatpak runtime branch" >&2
  exit 1
fi

if [ -z "$target_node" ]; then
  if [ -n "$NODE_ARG" ] && [ "$NODE_ARG" != "latest" ]; then
    target_node="$NODE_ARG"
  elif ! target_node="$(resolve_node_for_runtime "$target_runtime")"; then
    echo "flatpak-resolve: could not resolve a supported Node SDK extension for runtime $target_runtime" >&2
    exit 1
  fi
fi

jq -n \
  --arg runtime "$target_runtime" \
  --arg base "$target_runtime" \
  --arg node "$target_node" \
  '{
    runtime: $runtime,
    base: $base,
    node: $node
  }'
