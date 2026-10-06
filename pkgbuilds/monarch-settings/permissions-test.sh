#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_tree=${1:?Usage: permissions-test.sh <monarch-source>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src/monarch"
cp -a "$source_tree"/{config,default,applications,etc,LICENSE,logo.txt,icon.txt} \
  "$work/src/monarch/"
printf 'preserve this mode\n' >"$work/src/monarch/config/permissions-test.conf"
chmod 0660 "$work/src/monarch/config/permissions-test.conf"
for directory in "$work/src/monarch/default/sddm" "$work/src/monarch/default/plymouth"; do
  chmod -R 0700 "$directory"
done
chmod 0777 "$work/src/monarch/default"
chmod 0777 "$work/src/monarch/default/sddm/monarch/Main.qml"
source "$root/PKGBUILD"
srcdir=$work/src
pkgdir=$work/pkg
package

for directory in \
  usr/share/monarch/default/plymouth \
  usr/share/monarch/default/sddm \
  usr/share/plymouth/themes/monarch \
  usr/share/sddm/themes/monarch; do
  invalid=$(find "$pkgdir/$directory" \( -type d ! -perm 0755 -o -type f ! -perm 0644 \) -print -quit)
  if [[ -n $invalid ]]; then
    printf 'Incorrect unlock-theme mode: %s (%s)\n' "$invalid" "$(stat -c %a "$invalid")" >&2
    exit 1
  fi
done
for directory in usr/share/monarch/default usr/share/monarch/default/sddm; do
  [[ $(stat -c %a "$pkgdir/$directory") == "755" ]]
done
for directory in usr/share/monarch/config etc/skel/.config; do
  [[ $(stat -c %a "$pkgdir/$directory/permissions-test.conf") == "660" ]] || {
    echo "Unlock-theme packaging changed an unrelated config mode" >&2
    exit 1
  }
done
[[ $(stat -c %a "$pkgdir/usr/lib/systemd/system-sleep/unmount-fuse") == "755" ]]
[[ $(stat -c %a "$pkgdir/etc/sudoers.d") == "750" ]]
for policy in "$pkgdir/etc/sudoers.d"/*; do
  [[ $(stat -c %a "$policy") == "440" ]]
done

echo "monarch-settings fixes unlock-theme modes without changing unrelated configs, executables or sudoers"
