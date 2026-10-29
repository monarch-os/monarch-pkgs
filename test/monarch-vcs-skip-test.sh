#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PKGBUILDS_DIR="$tmp/pkgbuilds"
unset MONARCH_SRC
mkdir -p "$PKGBUILDS_DIR/monarch" "$tmp/upstream"
git -C "$tmp/upstream" init --quiet -b dev
git -C "$tmp/upstream" config user.name Test
git -C "$tmp/upstream" config user.email test@example.invalid
git -C "$tmp/upstream" commit --quiet --allow-empty -m Initial
git -C "$tmp/upstream" tag v2026.10.0
sed "s|https://github.com/monarch-os/monarch.git|file://$tmp/upstream|" \
  "$ROOT/pkgbuilds/monarch/PKGBUILD" | sed 's/^pkgrel=.*/pkgrel=2/' >"$PKGBUILDS_DIR/monarch/PKGBUILD"
cp "$ROOT/pkgbuilds/monarch/monarch.install" "$PKGBUILDS_DIR/monarch/"

source "$ROOT/helpers/package-metadata.sh"
source "$ROOT/helpers/makepkg-build.sh"
METADATA_HELPERS=true
get_local_version() { printf '%s\n' "$PUBLISHED_VERSION"; }
for function in check_vcs_unchanged check_needs_build; do
  eval "$(sed -n "/^$function() {/,/^}/p" "$ROOT/build/build.sh" |
    sed "s|/pkgbuilds/|$PKGBUILDS_DIR/|g")"
done

expect_skip() {
  if check_needs_build monarch; then
    echo "Unchanged monarch was scheduled for rebuilding: $PUBLISHED_VERSION" >&2
    exit 1
  fi
}

expect_build() {
  if ! check_needs_build monarch; then
    echo "Changed or unverifiable monarch was skipped: $PUBLISHED_VERSION" >&2
    exit 1
  fi
}

PUBLISHED_VERSION=2026.10.0-2
expect_skip
expect_skip
git -C "$tmp/upstream" tag -a v2026.11.0 -m Monthly
expect_build
PUBLISHED_VERSION=2026.11.0-2
expect_skip
echo "Exact lightweight and annotated tags skip unchanged builds but new milestones rebuild"

PUBLISHED_VERSION=2026.11.0-1
expect_build
PUBLISHED_VERSION=1:2026.11.0-2
expect_build
printf '\nepoch=1\n' >>"$PKGBUILDS_DIR/monarch/PKGBUILD"
expect_skip
sed -i '/^epoch=1$/d' "$PKGBUILDS_DIR/monarch/PKGBUILD"
echo "Package release and epoch changes still trigger rebuilding"

git -C "$tmp/upstream" commit --quiet --allow-empty -m Update
PUBLISHED_VERSION=2026.11.0-2
expect_build
hash=$(git -C "$tmp/upstream" rev-parse --short=7 HEAD)
PUBLISHED_VERSION="1.0.0.r39.g$hash-2"
expect_build
PUBLISHED_VERSION="2026.11.0.r1.g$hash-2"
expect_skip
git -C "$tmp/upstream" tag v2026.12.0
expect_build
PUBLISHED_VERSION=2026.12.0-2
expect_skip
git -C "$tmp/upstream" commit --quiet --allow-empty -m Next
expect_build
echo "Branch advancement and tagging previously untagged builds both trigger rebuilding"

PUBLISHED_VERSION=2027.01.0-2
expect_build
PUBLISHED_VERSION=2026.13.0-2
expect_build
PUBLISHED_VERSION=2026.11.01-2
expect_build
PUBLISHED_VERSION=4.0.4-2
expect_build
echo "Missing, malformed and legacy tags do not skip builds"

git -C "$tmp/upstream" tag v2027.01.2 HEAD~1
git -C "$tmp/upstream" tag v2027.01.1
hash=$(git -C "$tmp/upstream" rev-parse --short=7 HEAD)
PUBLISHED_VERSION="2027.01.2.r1.g$hash-2"
expect_skip
expect_skip
echo "A lower HEAD tag does not override the greater reachable ancestor tag"

git -C "$tmp/upstream" tag v2027.01.3 HEAD~1
expect_build
PUBLISHED_VERSION="2027.01.3.r1.g$hash-2"
expect_skip
echo "A new greater ancestor tag changes the source version even without a new commit"

git -C "$tmp/upstream" checkout --quiet --orphan unrelated
git -C "$tmp/upstream" commit --quiet --allow-empty -m Unrelated
git -C "$tmp/upstream" tag v2029.01.0
git -C "$tmp/upstream" checkout --quiet dev
expect_skip
echo "Higher tags on unrelated history do not affect the tracked source version"

PUBLISHED_VERSION=2026.11.0-2
mv "$tmp/upstream" "$tmp/unreachable"
expect_build
echo "An unreachable source fails open to rebuilding rather than skipping"

mkdir -p "$PKGBUILDS_DIR/other"
cp "$PKGBUILDS_DIR/monarch/PKGBUILD" "$PKGBUILDS_DIR/other/PKGBUILD"
cp "$PKGBUILDS_DIR/monarch/monarch.install" "$PKGBUILDS_DIR/other/"
if ! check_needs_build other; then
  echo "Monarch-specific CalVer detection changed another VCS package" >&2
  exit 1
fi
echo "Other hashless VCS packages keep their existing build policy"
