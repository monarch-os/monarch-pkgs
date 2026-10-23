#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

for architecture in x86_64 aarch64; do
  directory="$temporary/$architecture"
  mkdir -p "$directory"
  cp "$ROOT/pkgbuilds/disktree-bin/PKGBUILD" "$directory/PKGBUILD"
  printf 'source /etc/makepkg.conf\nCARCH=%s\nCHOST=%s-unknown-linux-gnu\n' \
    "$architecture" "$architecture" >"$directory/makepkg.conf"
  (
    cd "$directory"
    makepkg --config "$directory/makepkg.conf" --nodeps --ignorearch
    archive=$(makepkg --config "$directory/makepkg.conf" --packagelist)
    mkdir extracted
    bsdtar -xf "$archive" -C extracted
    desktop-file-validate extracted/usr/share/applications/disktree.desktop
    grep -qxF 'Exec=/usr/bin/disktree %f' extracted/usr/share/applications/disktree.desktop
    grep -qxF 'Terminal=false' extracted/usr/share/applications/disktree.desktop
    ! grep -q '@BINDIR@\|@VERSION@' extracted/usr/share/applications/disktree.desktop
    cmp "src/disktree-0.11.0-$architecture-linux/disktree" extracted/usr/bin/disktree
    [[ -s extracted/usr/share/icons/hicolor/scalable/apps/disktree.svg ]]
    [[ -s extracted/usr/share/licenses/disktree-bin/LICENSE ]]
    if [[ $architecture == "x86_64" ]]; then
      readelf -h extracted/usr/bin/disktree | grep -q 'Advanced Micro Devices X86-64'
      extracted/usr/bin/disktree --help >/dev/null
    else
      readelf -h extracted/usr/bin/disktree | grep -q AArch64
    fi
  )
  echo "PASS: $architecture verified release, package payload, architecture and desktop entry"
done
