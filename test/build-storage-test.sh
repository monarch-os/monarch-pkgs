#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/src" "$tmp/pkgbuilds/fixture" "$tmp/output"
printf 'pkgver=1\npkgrel=1\n' > "$tmp/pkgbuilds/fixture/PKGBUILD"
BUILD_OUTPUT_DIR="$tmp/output"
SUCCESSFUL_PACKAGES="" FAILED_PACKAGES=""
pkgbuild_declared_version() { echo 1-1; }
get_local_version() { :; }
repo-add() { :; }
sudo() { :; }
build_with_makepkg() {
  mkdir -p src pkg
  printf 'downloaded sources' > source.tar
  [[ ${FAIL_BUILD:-0} != 1 ]] || return 1
  printf 'archive' > fixture-1-1-any.pkg.tar.zst
  if [[ ${SPLIT_PACKAGE:-0} == 1 ]]; then
    printf 'split archive' > fixture-extra-1-1-any.pkg.tar.zst
  fi
  stat -c %i fixture-1-1-any.pkg.tar.zst > "$tmp/inode"
}
eval "$(sed -n '/^build_package() {/,/^}/p' "$ROOT/build/build.sh" |
  sed "s|/pkgbuilds/|$tmp/pkgbuilds/|g; s|/src|$tmp/src|g")"

build_package fixture
[[ -f $tmp/src/fixture/source.tar ]]
[[ -f $tmp/src/fixture/fixture-1-1-any.pkg.tar.zst ]]
MONARCH_CLEAN_BUILD=1 build_package fixture
[[ $(stat -c %i "$BUILD_OUTPUT_DIR/fixture-1-1-any.pkg.tar.zst") == "$(cat "$tmp/inode")" ]]
[[ ! -e $tmp/src/fixture ]]
[[ -f $BUILD_OUTPUT_DIR/fixture-1-1-any.pkg.tar.zst ]]
if MONARCH_CLEAN_BUILD=1 FAIL_BUILD=1 build_package fixture; then
  echo "Failed compilation reported success" >&2
  exit 1
fi
[[ -f $tmp/src/fixture/source.tar ]]

mv() {
  [[ $1 != fixture-extra-1-1-any.pkg.tar.zst ]] || return 1
  command mv "$@"
}
cp() {
  [[ $1 != fixture-extra-1-1-any.pkg.tar.zst ]] || return 1
  command cp "$@"
}
for clean in 1 0; do
  SUCCESSFUL_PACKAGES="" FAILED_PACKAGES=""
  if MONARCH_CLEAN_BUILD=$clean SPLIT_PACKAGE=1 build_package fixture; then
    echo "Failed archive transfer reported success (cleanup=$clean)" >&2
    exit 1
  fi
  [[ -z $SUCCESSFUL_PACKAGES ]]
  [[ $FAILED_PACKAGES == " fixture" ]]
  [[ -f $tmp/src/fixture/source.tar ]]
  [[ $(cat "$tmp/src/fixture/fixture-extra-1-1-any.pkg.tar.zst") == "split archive" ]]
  [[ $(cat "$BUILD_OUTPUT_DIR/fixture-1-1-any.pkg.tar.zst") == archive ]]
done
unset -f mv cp

FINAL_OUTPUT_DIR="$tmp/production"
mkdir "$FINAL_OUTPUT_DIR"
touch "$FINAL_OUTPUT_DIR/monarch.db.tar.zst"
sudo() { cat > "$tmp/pacman.conf"; }
configuration=$(sed -n '/^# Add monarch repo/,/^# Sync pacman database/p' "$ROOT/build/build.sh")
unset MONARCH_REPO_SERVER
eval "$configuration"
grep -Fx "Server = file://$FINAL_OUTPUT_DIR" "$tmp/pacman.conf"
MONARCH_REPO_SERVER=https://packages.example/x86_64
eval "$configuration"
grep -Fx "Server = $MONARCH_REPO_SERVER" "$tmp/pacman.conf"
echo "Build storage and on-demand repository tests passed"
