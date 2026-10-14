#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MONARCH_SRC="$tmp/source"
srcdir="$tmp/src"
pkgdir="$tmp/pkg"
mkdir -p "$srcdir/monarch"
source "$ROOT/pkgbuilds/monarch/PKGBUILD"
assert_versions_match() {
  local runtime_version settings_version
  runtime_version=$(pkgver)
  settings_version=$(source "$ROOT/pkgbuilds/monarch-settings/PKGBUILD"; pkgver)
  if [[ $runtime_version != "$settings_version" ]]; then
    printf 'Package versions differ: monarch=%s monarch-settings=%s\n' \
      "$runtime_version" "$settings_version" >&2
    exit 1
  fi
}
cd "$srcdir/monarch"
git init --quiet
git config user.name Test
git config user.email test@example.invalid
git commit --quiet --allow-empty -m Initial

[[ $(pkgver) == 0.r1.* ]] || { echo "Untagged Git fallback failed" >&2; exit 1; }
assert_versions_match
git tag v4.0.4
git tag v0.12.0
git tag v9999.13.0
git tag v9999.10.01
git tag v9999.10.1-rc1
[[ $(pkgver) == 0.r1.* ]] || { echo "Legacy or malformed tags are treated as CalVer" >&2; exit 1; }
assert_versions_match
git tag v2026.10.0
[[ $(pkgver) == "2026.10.0" ]] || { echo "Exact CalVer tag failed" >&2; exit 1; }
assert_versions_match
git commit --quiet --allow-empty -m Update
[[ $(pkgver) == 2026.10.0.r1.g* ]] || { echo "Untagged build suffix failed" >&2; exit 1; }
assert_versions_match
git tag v2026.10.2 HEAD~1
git tag v2026.10.1
[[ $(pkgver) == 2026.10.2.r1.g* ]] || { echo "Out-of-order tags regressed version" >&2; exit 1; }
assert_versions_match

mkdir -p assets bin install themes default/libalpm/hooks
touch LICENSE README.md boot.sh install.sh icon.png icon.txt logo.svg logo.txt
touch bin/monarch default/libalpm/hooks/00-monarch-update-guard.hook
printf '0.12.0\n' >version
revision=$(git rev-parse HEAD)
pkgver=$(pkgver)
package
[[ $(<"$pkgdir/usr/share/monarch/version") == "$pkgver" ]]
[[ $(<"$pkgdir/usr/share/monarch/revision") == "$revision" ]]
[[ -L $pkgdir/usr/bin/monarch ]]

mv .git "$tmp/git"
[[ $(pkgver) == "0.12.0" ]] || { echo "Source archive fallback failed" >&2; exit 1; }
assert_versions_match
echo "Monarch package version tests passed"
