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
cd "$srcdir/monarch"
git init --quiet
git config user.name Test
git config user.email test@example.invalid
git commit --quiet --allow-empty -m Initial

[[ $(pkgver) == 0.r1.* ]] || { echo "Untagged Git fallback failed" >&2; exit 1; }
git tag v4.0.4
git tag v0.12.0
git tag v9999.13.0
git tag v9999.10.01
git tag v9999.10.1-rc1
[[ $(pkgver) == 0.r1.* ]] || { echo "Legacy or malformed tags are treated as CalVer" >&2; exit 1; }
git tag v2026.10.0
[[ $(pkgver) == "2026.10.0" ]] || { echo "Exact CalVer tag failed" >&2; exit 1; }
git commit --quiet --allow-empty -m Update
[[ $(pkgver) == 2026.10.0.r1.g* ]] || { echo "Untagged build suffix failed" >&2; exit 1; }
git tag v2026.10.2 HEAD~1
git tag v2026.10.1
[[ $(pkgver) == 2026.10.2.r1.g* ]] || { echo "Out-of-order tags regressed version" >&2; exit 1; }
printf '0.12.0\n' >version

mv .git "$tmp/git"
[[ $(pkgver) == "0.12.0" ]] || { echo "Source archive fallback failed" >&2; exit 1; }
echo "Monarch package version tests passed"
