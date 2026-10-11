#!/usr/bin/env bash
# Offline tests for scripts/bump.sh: a fake release API + download tree served
# over file:// URLs. Needs curl, jq, sha256sum.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bump="$here/../scripts/bump.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

setup() {
  work="$(mktemp -d)"
  mkdir -p "$work/dl/v1.2.0"
  printf 'fake tarball' >"$work/dl/v1.2.0/collie-1.2.0-linux-x64.tar.gz"
  (cd "$work/dl/v1.2.0" && sha256sum collie-1.2.0-linux-x64.tar.gz >collie-1.2.0-linux-x64.tar.gz.sha256)
  echo '{"tag_name":"v1.2.0"}' >"$work/api.json"
  echo '{"version":"1.1.0","sha256":"old"}' >"$work/sources.json"
  : >"$work/out"
}

run_bump() {
  COLLIE_API_URL="file://$work/api.json" \
  COLLIE_DOWNLOAD_BASE="file://$work/dl" \
  SOURCES="$work/sources.json" \
  GITHUB_OUTPUT="$work/out" \
    "$bump"
}

# 1. A new release rewrites sources.json and reports it.
setup
run_bump >/dev/null
expected="$(sha256sum "$work/dl/v1.2.0/collie-1.2.0-linux-x64.tar.gz" | cut -d' ' -f1)"
[ "$(jq -r .version "$work/sources.json")" = 1.2.0 ] || fail "version not bumped"
[ "$(jq -r .sha256 "$work/sources.json")" = "$expected" ] || fail "sha256 not rewritten"
grep -qx 'changed=true' "$work/out" || fail "changed=true not emitted"
grep -qx 'version=1.2.0' "$work/out" || fail "version not emitted"
echo "ok 1 - bumps to a new release"

# 2. Already at latest: no rewrite, changed=false.
: >"$work/out"
before="$(cat "$work/sources.json")"
run_bump >/dev/null
[ "$(cat "$work/sources.json")" = "$before" ] || fail "sources.json changed while already latest"
grep -qx 'changed=false' "$work/out" || fail "changed=false not emitted"
echo "ok 2 - no-op when already latest"

# 3. Published .sha256 disagrees: fail, sources.json untouched.
setup
echo "0000000000000000000000000000000000000000000000000000000000000000  collie-1.2.0-linux-x64.tar.gz" \
  >"$work/dl/v1.2.0/collie-1.2.0-linux-x64.tar.gz.sha256"
if run_bump >/dev/null 2>&1; then fail "accepted a tarball whose sha256 mismatches the release"; fi
[ "$(jq -r .version "$work/sources.json")" = 1.1.0 ] || fail "sources.json touched on mismatch"
echo "ok 3 - rejects a hash mismatch"

# 4. API answers without tag_name (rate limit, error body): fail loudly.
setup
echo '{"message":"API rate limit exceeded"}' >"$work/api.json"
if run_bump >/dev/null 2>&1; then fail "succeeded without a tag_name"; fi
[ "$(jq -r .version "$work/sources.json")" = 1.1.0 ] || fail "sources.json touched on API error"
echo "ok 4 - fails on an API response without tag_name"

# 5. Tarball missing from the release: fail, sources.json untouched.
setup
rm "$work/dl/v1.2.0/collie-1.2.0-linux-x64.tar.gz"
if run_bump >/dev/null 2>&1; then fail "succeeded without the tarball"; fi
[ "$(jq -r .version "$work/sources.json")" = 1.1.0 ] || fail "sources.json touched on missing tarball"
echo "ok 5 - fails when the tarball is missing"
