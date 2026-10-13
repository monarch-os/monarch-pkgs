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
  "$ROOT/pkgbuilds/monarch/PKGBUILD" >"$PKGBUILDS_DIR/monarch/PKGBUILD"

source "$ROOT/helpers/package-metadata.sh"
METADATA_HELPERS=true
get_local_version() { printf '%s\n' "$PUBLISHED_VERSION"; }
for function in check_vcs_unchanged check_needs_build; do
  eval "$(sed -n "/^$function() {/,/^}/p" "$ROOT/build/build.sh" |
    sed "s|/pkgbuilds/|$PKGBUILDS_DIR/|g")"
done

expect_skip() {
  if check_needs_build monarch; then
    echo "Unchanged Monarch package was scheduled for rebuilding: $PUBLISHED_VERSION" >&2
    exit 1
  fi
}

expect_build() {
  if ! check_needs_build monarch; then
    echo "Changed or unverifiable Monarch package was skipped: $PUBLISHED_VERSION" >&2
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

PUBLISHED_VERSION=2026.11.0-2
mv "$tmp/upstream" "$tmp/unreachable"
expect_build
echo "An unreachable source fails open to rebuilding rather than skipping"

mkdir -p "$PKGBUILDS_DIR/other"
cp "$PKGBUILDS_DIR/monarch/PKGBUILD" "$PKGBUILDS_DIR/other/PKGBUILD"
if ! check_needs_build other; then
  echo "Monarch-specific CalVer detection changed another VCS package" >&2
  exit 1
fi
echo "Other hashless VCS packages keep their existing build policy"
