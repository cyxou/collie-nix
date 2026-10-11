#!/usr/bin/env bash
# Bump sources.json to the newest AltanS/collie GitHub release.
#
# Downloads the linux-x64 tarball, hashes it (hex sha256), and refuses to
# proceed unless that matches the release's own published .sha256 asset.
# Fails loudly on any API/download error — never a silent no-op — and leaves
# sources.json untouched on failure.
#
# Env overrides (used by tests/bump.test.sh): COLLIE_API_URL,
# COLLIE_DOWNLOAD_BASE, SOURCES. In GitHub Actions it appends changed= and
# version= to $GITHUB_OUTPUT; GITHUB_TOKEN, when set, authenticates the API
# call (shared runners hit the anonymous rate limit).
#
# Edge: if upstream re-publishes a DIFFERENT tarball under the same tag, only
# the hash moves and this reports "already at latest". To force a re-hash, set
# "version" to "" in sources.json and rerun.
set -euo pipefail

repo="AltanS/collie"
api="${COLLIE_API_URL:-https://api.github.com/repos/${repo}/releases/latest}"
dl="${COLLIE_DOWNLOAD_BASE:-https://github.com/${repo}/releases/download}"
sources="${SOURCES:-$(dirname "$0")/../sources.json}"
out="${GITHUB_OUTPUT:-/dev/null}"

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

body="$(curl -fsSL "${auth[@]}" "$api")" \
  || { echo "bump: release API request failed: $api" >&2; exit 1; }
tag="$(jq -r '.tag_name // empty' <<<"$body")"
if [ -z "$tag" ]; then
  echo "bump: no tag_name in the API response (rate-limited?): $body" >&2
  exit 1
fi
latest="${tag#v}"

current="$(jq -r '.version' "$sources")"
if [ "$current" = "$latest" ]; then
  echo "collie already at latest v${latest}"
  echo "changed=false" >>"$out"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM HUP

tarball="collie-${latest}-linux-x64.tar.gz"
curl -fsSL "${dl}/v${latest}/${tarball}" -o "$tmp/$tarball" \
  || { echo "bump: download failed: ${dl}/v${latest}/${tarball}" >&2; exit 1; }
curl -fsSL "${dl}/v${latest}/${tarball}.sha256" -o "$tmp/$tarball.sha256" \
  || { echo "bump: no published checksum: ${dl}/v${latest}/${tarball}.sha256" >&2; exit 1; }

sha="$(sha256sum "$tmp/$tarball" | cut -d' ' -f1)"
published="$(cut -d' ' -f1 "$tmp/$tarball.sha256" | tr 'A-F' 'a-f')"
if [ "$sha" != "$published" ]; then
  echo "bump: sha256 mismatch for $tarball: got $sha, release says $published" >&2
  exit 1
fi

jq --arg v "$latest" --arg s "$sha" '.version = $v | .sha256 = $s' "$sources" >"$tmp/sources.json"
cat "$tmp/sources.json" >"$sources"

echo "collie v${current} -> v${latest}"
{
  echo "changed=true"
  echo "version=${latest}"
} >>"$out"
