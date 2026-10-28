#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_tree=${1:?Usage: permissions-test.sh <monarch-source>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src/monarch"
cp "$root/build-noctalia-templates.py" "$work/src/"
cp -a "$source_tree"/{assets,bin,install,themes,config,default,applications,etc,LICENSE,README.md,boot.sh,install.sh,icon.png,icon.txt,logo.svg,logo.txt} \
  "$work/src/monarch/"
printf '%s\n' fixture >"$work/src/monarch/assets/permissions-test.conf"
chmod 0777 "$work/src/monarch/assets"
chmod 0666 "$work/src/monarch/assets/permissions-test.conf"
for mode in 0600 0660 0646 0757; do
  touch "$work/src/monarch/assets/permissions-$mode.conf"
  chmod "$mode" "$work/src/monarch/assets/permissions-$mode.conf"
done
mkdir "$work/src/monarch/assets/private" "$work/src/monarch/assets/group-writable" "$work/external"
chmod 0700 "$work/src/monarch/assets/private"
chmod 0775 "$work/src/monarch/assets/group-writable"
touch "$work/external/config"
chmod 0777 "$work/external"
chmod 0666 "$work/external/config"
ln -s "$work/external" "$work/src/monarch/assets/external"
source "$root/PKGBUILD"
srcdir=$work/src
pkgdir=$work/pkg
(umask 0000; package_monarch)

invalid=$(find "$pkgdir" \( -type d -o -type f \) -perm /0022 -print -quit)
if [[ -n $invalid ]]; then
  printf 'Group/world-writable package entry: %s (%s)\n' "$invalid" "$(stat -c %a "$invalid")" >&2
  exit 1
fi
for mapping in 0600:600 0660:640 0646:644 0757:755; do
  [[ $(stat -c %a "$pkgdir/usr/share/monarch/assets/permissions-${mapping%:*}.conf") == "${mapping#*:}" ]]
done
[[ $(stat -c %a "$pkgdir/usr/share/monarch/assets/private") == "700" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/assets/group-writable") == "755" ]]
[[ -L $pkgdir/usr/share/monarch/assets/external ]]
[[ $(stat -c %a "$work/external") == "777" ]]
[[ $(stat -c %a "$work/external/config") == "666" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/assets") == "755" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/assets/permissions-test.conf") == "644" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/version") == "644" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/bin/monarch") == "755" ]]
[[ -L $pkgdir/usr/bin/monarch ]]
echo "monarch packaging removes group/world write while retaining private modes, executables and symlinks"
