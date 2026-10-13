#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
source "$ROOT/helpers/makepkg-build.sh"
export PREPARE_RECORD="$tmp/prepare-count"
mkdir -p "$tmp/fixture" "$tmp/packages"
cp /etc/makepkg.conf "$tmp/makepkg.conf"
printf '\nPKGDEST=%q\nSRCDEST=%q\nSRCPKGDEST=%q\nBUILDDIR=%q\n' \
  "$tmp/packages" "$tmp/sources" "$tmp/source-packages" "$tmp/build" >>"$tmp/makepkg.conf"
cd "$tmp/fixture"
cat >PKGBUILD <<'FIXTURE'
pkgname=monarch-settings-fixture
pkgver=0.1.0
pkgrel=2
pkgdesc='Reproduce the nightly package release reset'
arch=('any')
license=('MIT')
options=('!debug' '!strip')
prepare() {
  printf 'prepared\n' >>"$srcdir/prepare-count"
  printf 'prepared\n' >>"$PREPARE_RECORD"
}
pkgver() {
  [[ -f $srcdir/prepare-count ]] || return 1
  printf '%s\n' "${RESOLVED_PKGVER:-1.0.0.r39.g8833f38}"
}
package() {
  install -Dm644 /dev/null "$pkgdir/usr/share/monarch-settings-fixture/payload"
}
FIXTURE

flags=(--config "$tmp/makepkg.conf" --nodeps --nosign --noconfirm --force --clean)
build_with_makepkg "${flags[@]}" \
  >"$tmp/output" 2>&1
package=$(find "$tmp/packages" -type f -name '*.pkg.tar.*' -print -quit)
version=$(bsdtar -xOqf "$package" .PKGINFO | sed -n 's/^pkgver = //p')
if [[ $version != '1.0.0.r39.g8833f38-2' ]]; then
  cat "$tmp/output"
  printf 'FAIL: requested pkgrel=2, but makepkg produced %s\n' "$version" >&2
  exit 1
fi
echo "PASS: actual makepkg retains the declared pkgrel when pkgver() updates the version"
[[ $(wc -l <"$PREPARE_RECORD") == 1 ]]
echo "PASS: the resolved version and final package reuse one prepared source tree"

PUBLISHED_VERSION=$version
sed -i 's/^pkgver=.*/pkgver=0.1.0/' PKGBUILD
source "$ROOT/helpers/package-metadata.sh"
METADATA_HELPERS=true
get_local_version() { printf '%s\n' "$PUBLISHED_VERSION"; }
package_git_upstream_hash() { printf '8833f38\n'; }
for function in check_vcs_unchanged check_needs_build; do
  eval "$(sed -n "/^$function() {/,/^}/p" "$ROOT/build/build.sh" |
    sed "s|/pkgbuilds/|$tmp/|g")"
done
if check_needs_build fixture; then
  echo "FAIL: the following nightly schedules the unchanged VCS package again" >&2
  exit 1
fi
echo "PASS: the unchanged declared recipe is skipped after publishing the intended pkgrel"

export RESOLVED_PKGVER=1.0.0.r40.g123abcd
build_with_makepkg "${flags[@]}" \
  >"$tmp/output" 2>&1
[[ -f $tmp/packages/monarch-settings-fixture-1.0.0.r40.g123abcd-2-any.pkg.tar.zst ]]
[[ $(wc -l <"$PREPARE_RECORD") == 2 ]]
echo "PASS: advancing the VCS version still retains the declared package release"

mkdir "$tmp/static"
cd "$tmp/static"
sed '/^pkgver() {/,/^}/d; s/^pkgrel=.*/pkgrel=3/' "$tmp/fixture/PKGBUILD" >PKGBUILD
build_with_makepkg "${flags[@]}" \
  >"$tmp/output" 2>&1
[[ -f $tmp/packages/monarch-settings-fixture-1.0.0.r40.g123abcd-3-any.pkg.tar.zst ]]
echo "PASS: static recipes retain their existing single-pass makepkg behavior"

cd "$tmp/fixture"
(
  calls="$tmp/failed-source-calls"
  makepkg() {
    printf '%s\n' "$*" >>"$calls"
    return 42
  }
  status=0
  build_with_makepkg --nodeps --noconfirm || status=$?
  ((status == 42))
  [[ $(wc -l <"$calls") == 1 ]]
)
echo "PASS: source-resolution failures preserve their status and stop before packaging"
