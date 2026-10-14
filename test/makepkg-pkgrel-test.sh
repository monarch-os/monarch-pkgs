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
cp PKGBUILD "$tmp/template"

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
    if [[ $1 == --printsrcinfo ]]; then
      printf 'pkgbase = fixture\n\tpkgver = 0.1.0\n\tpkgrel = 2\n'
      return 0
    fi
    return 42
  }
  status=0
  build_with_makepkg --nodeps --noconfirm || status=$?
  ((status == 42))
  [[ $(wc -l <"$calls") == 2 ]]
)
echo "PASS: source-resolution failures preserve their status and stop before packaging"

(
  calls="$tmp/failed-metadata-calls"
  makepkg() {
    printf '%s\n' "$*" >>"$calls"
    return 43
  }
  status=0
  build_with_makepkg --nodeps --noconfirm || status=$?
  ((status == 43))
  [[ $(wc -l <"$calls") == 1 ]]
)
echo "PASS: makepkg metadata failures preserve their status and stop before resolving sources"

unset RESOLVED_PKGVER
for declaration in 'function pkgver {' 'function pkgver() {' '  pkgver() {' '  function pkgver() {'; do
  mkdir -p "$tmp/alternate"
  cd "$tmp/alternate"
  sed "s/^pkgver() {/$declaration/" "$tmp/template" >PKGBUILD
  previous_prepares=$(wc -l <"$PREPARE_RECORD")
  build_with_makepkg "${flags[@]}" >"$tmp/output" 2>&1
  package="$tmp/packages/monarch-settings-fixture-1.0.0.r39.g8833f38-2-any.pkg.tar.zst"
  version=$(bsdtar -xOqf "$package" .PKGINFO | sed -n 's/^pkgver = //p')
  if [[ $(bash -c 'source PKGBUILD; printf "%s" "$pkgrel"') != 2 || $version != '1.0.0.r39.g8833f38-2' ]]; then
    cat "$tmp/output"
    printf 'FAIL: alternate declaration bypassed pkgrel preservation: %s\n' "$declaration" >&2
    exit 1
  fi
  (( $(wc -l <"$PREPARE_RECORD") == previous_prepares + 1 ))

  sed "s/^pkgver() {/$declaration/" "$tmp/template" >"$tmp/fixture/PKGBUILD"
  PUBLISHED_VERSION=$version
  if check_needs_build fixture; then
    printf 'FAIL: alternate declaration bypassed unchanged-build detection: %s\n' "$declaration" >&2
    exit 1
  fi
done
echo "PASS: function-keyword and indented declarations preserve pkgrel and skip unchanged nightly builds"

(
  pkgver() { :; }
  export -f pkgver
  if pkgbuild_has_pkgver "$tmp/static/PKGBUILD"; then
    echo "FAIL: a static recipe inherited the caller's pkgver function" >&2
    exit 1
  fi
  pkgrel=unchanged
  pkgbuild_has_pkgver "$tmp/fixture/PKGBUILD"
  [[ $pkgrel == 'unchanged' ]]
)
echo "PASS: declaration detection is isolated from inherited functions and caller variables"

for target in x86_64 aarch64; do
  (
    unset CARCH
    target_root="$tmp/target-$target"
    mkdir -p "$target_root/packages" "$target_root/home"
    export HOME="$target_root/home" XDG_CONFIG_HOME="$target_root/home/.config"
    export MAKEPKG_CONF="$target_root/makepkg.conf"
    cp "$tmp/makepkg.conf" "$MAKEPKG_CONF"
    printf '\nCARCH=%q\nPKGDEST=%q\n' "$target" "$target_root/packages" >>"$MAKEPKG_CONF"
    cd "$target_root"
    cat >PKGBUILD <<'TARGET'
fixture_pkgrel() {
  case "${CARCH:-}" in
    x86_64) echo 2 ;;
    aarch64) echo 7 ;;
    *) echo 99 ;;
  esac
}
TARGET
    sed -e 's/^pkgrel=.*/pkgrel=$(fixture_pkgrel)/' \
      -e "/^pkgver() {/i if [[ \${CARCH:-} == $target ]]; then" \
      -e '/^package() {/i fi' "$tmp/template" >>PKGBUILD
    cp PKGBUILD "$target_root/declared.PKGBUILD"
    selected_config=$MAKEPKG_CONF
    cp "$MAKEPKG_CONF" "$target_root/default.conf"
    printf '\nCARCH=unsupported\n' >>"$target_root/default.conf"
    export MAKEPKG_CONF="$target_root/default.conf"
    if ! build_with_makepkg --config "$selected_config" --nodeps --nosign --noconfirm --force --clean \
      >"$tmp/output" 2>&1; then
      cat "$tmp/output"
      exit 1
    fi
    expected_release=2
    [[ $target != aarch64 ]] || expected_release=7
    package=$(find "$target_root/packages" -type f -name '*.pkg.tar.*' -print -quit)
    version=$(bsdtar -xOqf "$package" .PKGINFO | sed -n 's/^pkgver = //p')
    if [[ $version != "1.0.0.r39.g8833f38-$expected_release" ]]; then
      cat "$tmp/output"
      printf 'FAIL: %s configuration requires pkgrel=%s, produced %s\n' \
        "$target" "$expected_release" "$version" >&2
      exit 1
    fi

    export MAKEPKG_CONF="$selected_config"
    cp "$target_root/declared.PKGBUILD" "$tmp/fixture/PKGBUILD"
    sed -i 's/^pkgver=.*/pkgver=0.1.0/' "$tmp/fixture/PKGBUILD"
    PUBLISHED_VERSION=$version
    if check_needs_build fixture; then
      printf 'FAIL: unchanged %s package was rebuilt under a different target context\n' "$target" >&2
      exit 1
    fi
  )
done
echo "PASS: selected x86_64 and aarch64 configurations retain their releases and skip unchanged builds"
