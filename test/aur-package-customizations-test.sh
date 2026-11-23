#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/aur-customizations-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/repo/bin" "$tmp/repo/pkgbuilds" "$tmp/upstream"
cp "$ROOT/bin/sync-aur" "$tmp/repo/bin/"
cp -a "$ROOT/helpers" "$tmp/repo/"

for package in onlyoffice-bin voxtype-bin; do
  cp -a "$ROOT/pkgbuilds/$package" "$tmp/repo/pkgbuilds/"
  mkdir "$tmp/upstream/$package"
  cp "$ROOT/pkgbuilds/$package/PKGBUILD" "$tmp/upstream/$package/"
  sed -i 's/^pkgrel=.*/pkgrel=1/' "$tmp/upstream/$package/PKGBUILD"
done
cp "$ROOT/pkgbuilds/voxtype-bin/voxtype-bin.install" "$tmp/upstream/voxtype-bin/"
patch -R -p1 --batch --fuzz=0 -d "$tmp/upstream/voxtype-bin" \
  < "$ROOT/pkgbuilds/voxtype-bin/.monarch/patches/0001-propagate-backend-install-failures.patch"

git() {
  if [[ $1 == clone ]]; then
    cp -a "$UPSTREAM_ROOT/${3}" "$3"
  elif [[ $1 == -C && $3 == rev-parse && $4 == HEAD ]]; then
    printf '%040d\n' 1
  else
    echo "Unexpected git invocation: $*" >&2
    return 1
  fi
}
export -f git
export UPSTREAM_ROOT="$tmp/upstream"

version() {
  bash -c 'source "$1"; printf "%s-%s\n" "$pkgver" "$pkgrel"' _ "$1"
}
assert_version() {
  local actual
  actual=$(version "$tmp/repo/pkgbuilds/$1/PKGBUILD")
  [[ $actual == "$2" ]] || { echo "FAIL: $1 version $actual != $2" >&2; exit 1; }
}

for attempt in 1 2; do
  bash "$tmp/repo/bin/sync-aur" onlyoffice-bin voxtype-bin
  assert_version onlyoffice-bin 10.0.0-2.1
  assert_version voxtype-bin 1.3.1-1.1
  cmp "$ROOT/pkgbuilds/voxtype-bin/voxtype-bin.install" \
    "$tmp/repo/pkgbuilds/voxtype-bin/voxtype-bin.install"
  echo "PASS: sync $attempt retains package releases and Voxtype failure guards"
done

[[ $(vercmp "$(version "$ROOT/pkgbuilds/onlyoffice-bin/PKGBUILD")" 10.0.0-2) -gt 0 ]]
echo "PASS: OnlyOffice release is newer than the published collision fix"

sed -i 's/^pkgrel=.*/pkgrel=2/' "$tmp/upstream/onlyoffice-bin/PKGBUILD"
bash "$tmp/repo/bin/sync-aur" onlyoffice-bin
assert_version onlyoffice-bin 10.0.0-3.1
echo "PASS: upstream release increments retain the local offset"

sed -i -e 's/^pkgver=.*/pkgver=10.0.1/' -e 's/^pkgrel=.*/pkgrel=1/' \
  "$tmp/upstream/onlyoffice-bin/PKGBUILD"
bash "$tmp/repo/bin/sync-aur" onlyoffice-bin
assert_version onlyoffice-bin 10.0.1-1
jq -e 'has("pkgrel") | not' "$tmp/repo/pkgbuilds/onlyoffice-bin/.monarch/package.json" > /dev/null
echo "PASS: a new upstream version clears the obsolete OnlyOffice release override"
