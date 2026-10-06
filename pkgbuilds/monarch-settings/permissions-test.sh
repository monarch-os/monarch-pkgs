#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_tree=${1:?Usage: permissions-test.sh <monarch-source>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src/monarch"
cp -a "$source_tree"/{config,default,applications,etc,LICENSE,logo.txt,icon.txt} \
  "$work/src/monarch/"
chmod -R a+rwX "$work/src/monarch"
source "$root/PKGBUILD"
srcdir=$work/src
pkgdir=$work/pkg
package

unsafe=$(find "$pkgdir" \( -type d -o -type f \) -perm /0022 -print)
if [[ -n $unsafe ]]; then
  printf 'Package contains writable paths, including: %s\n' "${unsafe%%$'\n'*}" >&2
  exit 1
fi

for directory in usr/share/monarch/default/sddm/monarch usr/share/sddm/themes/monarch; do
  [[ $(stat -c %a "$pkgdir/$directory") == "755" ]]
  [[ $(stat -c %a "$pkgdir/$directory/theme.conf") == "644" ]]
done
[[ $(stat -c %a "$pkgdir/usr/lib/systemd/system-sleep/unmount-fuse") == "755" ]]
[[ $(stat -c %a "$pkgdir/etc/sudoers.d") == "750" ]]
for policy in "$pkgdir/etc/sudoers.d"/*; do
  [[ $(stat -c %a "$policy") == "440" ]]
done

echo "monarch-settings normalizes writable sources and preserves executable and sudoers modes"
