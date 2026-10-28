#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_tree=${1:?Usage: permissions-test.sh <monarch-source>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src/monarch"
cp "$root/build-noctalia-templates.py" "$work/src/"
cp -a "$source_tree"/{assets,bin,install,themes,config,default,applications,etc,LICENSE,README.md,boot.sh,install.sh,logo.txt,logo.svg,icon.txt,icon.png} \
  "$work/src/monarch/"
for mode in 0600 0660 0646 0757; do
  touch "$work/src/monarch/config/permissions-$mode.conf"
  chmod "$mode" "$work/src/monarch/config/permissions-$mode.conf"
done
mkdir "$work/src/monarch/config/private" "$work/src/monarch/config/group-writable" "$work/external"
chmod 0700 "$work/src/monarch/config/private"
chmod 0775 "$work/src/monarch/config/group-writable"
touch "$work/external/config"
chmod 0777 "$work/external"
chmod 0666 "$work/external/config"
ln -s "$work/external" "$work/src/monarch/config/external"
chmod 0777 "$work/src/monarch/etc/NetworkManager" "$work/src/monarch/config"
chmod 0666 "$work/src/monarch/etc/docker/daemon.json"
chmod 0777 "$work/src/monarch/default/noctalia/indicators/voxtype.sh"
for directory in "$work/src/monarch/default/sddm" "$work/src/monarch/default/plymouth"; do
  chmod -R 0700 "$directory"
done
chmod 0777 "$work/src/monarch/default"
chmod 0777 "$work/src/monarch/default/sddm/monarch/Main.qml"
source "$root/PKGBUILD"
srcdir=$work/src
pkgdir=$work/pkg
(umask 0000; package_monarch)

invalid=$(find "$pkgdir" \( -type d -o -type f \) -perm /0022 -print -quit)
if [[ -n $invalid ]]; then
  printf 'Group/world-writable package entry: %s (%s)\n' "$invalid" "$(stat -c %a "$invalid")" >&2
  exit 1
fi
[[ $(stat -c %a "$pkgdir/etc/NetworkManager") == "755" ]]
[[ $(stat -c %a "$pkgdir/etc/docker/daemon.json") == "644" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/default/noctalia/indicators/voxtype.sh") == "755" ]]
[[ $(stat -c %a "$pkgdir/usr/share/monarch/config") == "755" ]]

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
  for mapping in 0600:600 0660:640 0646:644 0757:755; do
    [[ $(stat -c %a "$pkgdir/$directory/permissions-${mapping%:*}.conf") == "${mapping#*:}" ]]
  done
  [[ $(stat -c %a "$pkgdir/$directory/private") == "700" ]]
  [[ $(stat -c %a "$pkgdir/$directory/group-writable") == "755" ]]
  [[ -L $pkgdir/$directory/external ]]
done
[[ $(stat -c %a "$work/external") == "777" ]]
[[ $(stat -c %a "$work/external/config") == "666" ]]
[[ $(stat -c %a "$pkgdir/usr/lib/systemd/system-sleep/unmount-fuse") == "755" ]]
[[ $(stat -c %a "$pkgdir/etc/sudoers.d") == "750" ]]
for policy in "$pkgdir/etc/sudoers.d"/*; do
  [[ $(stat -c %a "$policy") == "440" ]]
done

echo "monarch defaults retain private modes, executables and sudoers without group/world write"
