#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fixture="$tmp/repo"
mkdir -p "$fixture/bin" "$fixture/helpers" "$fixture/build-output/x86_64" \
  "$fixture/pkgs.monarchlinux.com/x86_64"
cp "$ROOT/bin/promote-build" "$fixture/bin/"
cp "$ROOT/helpers/"{paths,message-helpers}.sh "$fixture/helpers/"
build="$fixture/build-output/x86_64"
published="$fixture/pkgs.monarchlinux.com/x86_64"
package=monarch-settings-1.0.0.r39.g8833f38-1-any.pkg.tar.zst

printf 'package payload\n' >"$published/$package"
printf 'published signature\n' >"$published/$package.sig"
cp "$published/$package" "$build/$package"
cp "$published/$package.sig" "$build/$package.sig"

status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
cat "$tmp/output"
if ((status != 0)); then
  echo "FAIL: replaying an already published identical package must succeed" >&2
  exit 1
fi
[[ $(<"$published/$package") == 'package payload' ]]
[[ $(<"$published/$package.sig") == 'published signature' ]]
[[ ! -e $build/$package && ! -e $build/$package.sig ]]
echo "PASS: identical publication replay preserves production and clears staged duplicates"

cp "$published/$package" "$build/$package"
printf 'new signature for the same bytes\n' >"$build/$package.sig"
other=example-2.0-1-any.pkg.tar.zst
printf 'new package\n' >"$build/$other"
printf 'new signature\n' >"$build/$other.sig"
before=$(stat -c '%i:%Y' "$published/$package")
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
[[ $(stat -c '%i:%Y' "$published/$package") == "$before" ]]
[[ $(<"$published/$package.sig") == 'published signature' ]]
[[ $(<"$published/$other") == 'new package' ]]
[[ $(<"$published/$other.sig") == 'new signature' ]]
[[ ! -e $build/$package && ! -e $build/$other ]]
echo "PASS: resigning identical bytes preserves the published signature and does not block new packages"

printf 'different package payload\n' >"$build/$package"
printf 'replacement signature\n' >"$build/$package.sig"
next=next-1.0-1-any.pkg.tar.zst
printf 'next package\n' >"$build/$next"
printf 'next signature\n' >"$build/$next.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ $(<"$published/$package") == 'package payload' ]]
[[ $(<"$published/$package.sig") == 'published signature' ]]
[[ ! -e $published/$next && ! -e $published/$next.sig ]]
[[ -f $build/$package && -f $build/$next ]]
echo "PASS: differing bytes under an existing name stop the entire batch without overwriting production"

cp "$published/$package" "$build/$package"
rm "$build/$package.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$package && -f $build/$next ]]
[[ ! -e $published/$next ]]
echo "PASS: duplicates cannot bypass the staged-signature requirement"

printf 'staged signature\n' >"$build/$package.sig"
bash "$fixture/bin/promote-build" --dry-run >"$tmp/output" 2>&1
[[ -f $build/$package && -f $build/$package.sig && -f $build/$next ]]
[[ ! -e $published/$next ]]
echo "PASS: dry runs do not move or remove staged files"

rm "$published/$package.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$package && ! -e $published/$next ]]
echo "PASS: an unsigned production artifact is not accepted as an already published pair"

printf 'published signature\n' >"$published/$package.sig"
printf 'orphaned signature\n' >"$published/$next.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ $(<"$published/$next.sig") == 'orphaned signature' ]]
[[ ! -e $published/$next && -f $build/$next && -f $build/$package ]]
echo "PASS: a pre-existing orphaned signature cannot be overwritten"

rm "$published/$next.sig"
(
  exec {lock}<"$build"
  flock -n "$lock"
  status=0
  bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
  ((status != 0))
  [[ -f $build/$package && -f $build/$next && ! -e $published/$next ]]
)
echo "PASS: overlapping local promotions fail before mutating the batch"

bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
[[ $(<"$published/$next") == 'next package' ]]
echo "PASS: a completed batch and its empty retry both succeed"
