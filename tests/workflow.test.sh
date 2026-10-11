#!/usr/bin/env bash
# Checks of .github/workflows/bump.yml's publish logic: runs the workflow's own
# step scripts (lifted out with yq) against local fixtures, plus structural
# checks of step order and guards. Needs yq (v4), jq, git:
#   nix shell --inputs-from . nixpkgs#yq-go -c tests/workflow.test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
fail() { echo "FAIL: $*" >&2; exit 1; }

steps="$(yq -o=json '.jobs.bump.steps' "$root/.github/workflows/bump.yml")"
step() { jq -r --arg n "$1" --arg f "$2" '.[] | select(.name == $n) | .[$f] // ""' <<<"$steps"; }
index_of() { jq --arg n "$1" 'map(.name) | index($n)' <<<"$steps"; }
# Run a step's script the way the runner does (bash -eo pipefail).
run_step() { bash --noprofile --norc -eo pipefail -c "$(step "$1" run)"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
gitc() { git -c user.name=t -c user.email=t@t "$@"; }

# 1. The image is pushed before the bump is committed: a failed push then
#    leaves master unbumped, and the next run retries the whole release.
[ "$(index_of 'Push the lead image')" -lt "$(index_of 'Commit and tag the bump')" ] \
  || fail "image is pushed after the bump commit"
echo "ok 1 - image pushed before the bump commit"

# Fixture: a remote whose master holds sources.json, and the run's shallow
# checkout of it (actions/checkout fetches depth 1).
git init -q --bare -b master "$work/remote.git"
git clone -q "$work/remote.git" "$work/seed" 2>/dev/null
(cd "$work/seed" && echo '{"version":"1.0.0"}' >sources.json && git add sources.json \
  && gitc commit -qm seed && git push -q origin HEAD:master)
fresh_run() {
  rm -rf "$work/run"
  git clone -q --depth 1 "file://$work/remote.git" "$work/run"
  echo "{\"version\":\"$1\"}" >"$work/run/sources.json"
}

# 2. The commit step commits sources.json, tags it, and pushes both.
fresh_run 1.1.0
(cd "$work/run" && VERSION=1.1.0 run_step 'Commit and tag the bump') >/dev/null 2>&1 \
  || fail "commit step failed on a clean push"
[ "$(git -C "$work/remote.git" rev-parse master)" = "$(git -C "$work/run" rev-parse HEAD)" ] \
  || fail "master not pushed"
[ -n "$(git -C "$work/remote.git" tag -l v1.1.0)" ] || fail "tag v1.1.0 not pushed"
echo "ok 2 - commits, tags and pushes the bump"

# 3. Master moved on under the run: the push fails and takes the tag with it,
#    so no tag lands on a commit that is not on master.
fresh_run 1.2.0
(cd "$work/seed" && git pull -q origin master && echo x >other && git add other \
  && gitc commit -qm "moved on" && git push -q origin HEAD:master)
if (cd "$work/run" && VERSION=1.2.0 run_step 'Commit and tag the bump') >/dev/null 2>&1; then
  fail "push succeeded although master moved on"
fi
[ -z "$(git -C "$work/remote.git" tag -l v1.2.0)" ] || fail "tag v1.2.0 pushed without its branch"
echo "ok 3 - a rejected branch push takes the tag with it"

# 4. skopeo carries its own policy: nixpkgs' skopeo has no default
#    policy.json, and the source is a local, hash-pinned Nix output.
step 'Push the lead image' run | grep -q 'skopeo --insecure-policy copy' \
  || fail "skopeo copy depends on a host policy.json"
echo "ok 4 - skopeo copy needs no host policy.json"

# 5. Only master publishes; a dispatch from another branch is a dry run
#    (bump + build, no commit, no image).
decide() {  # event ref changed -> "build=… publish=…"
  : >"$work/out"
  (cd "$root" && GITHUB_EVENT_NAME="$1" GITHUB_REF="$2" CHANGED="$3" GITHUB_OUTPUT="$work/out" \
    run_step 'Decide whether to publish') >/dev/null
  echo "$(grep '^build=' "$work/out") $(grep '^publish=' "$work/out")"
}
[ "$(decide schedule refs/heads/master true)" = "build=true publish=true" ] || fail "scheduled bump on master does not publish"
[ "$(decide schedule refs/heads/master false)" = "build=false publish=false" ] || fail "no-op run builds or publishes"
[ "$(decide push refs/heads/master '')" = "build=true publish=true" ] || fail "recipe push on master does not republish"
[ "$(decide workflow_dispatch refs/heads/try true)" = "build=true publish=false" ] || fail "dispatch from a branch publishes"
[ "$(step 'Push the lead image' if)" = "steps.plan.outputs.publish == 'true'" ] || fail "image push not gated on publish"
step 'Commit and tag the bump' if | grep -qF "steps.plan.outputs.publish == 'true'" || fail "commit not gated on publish"
echo "ok 5 - only master commits or publishes"
