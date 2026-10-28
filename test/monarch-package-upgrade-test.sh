#!/bin/bash

set -euo pipefail
export LC_ALL=C

if (( $# != 4 )); then
  echo "Usage: $0 <old-monarch> <old-settings> <unified-monarch> <empty-settings> (package archives)" >&2
  exit 2
fi
if (( EUID != 0 )); then
  exec unshare --user --map-root-user bash "$0" "$@"
fi

old_runtime=$(realpath "$1")
old_settings=$(realpath "$2")
unified=$(realpath "$3")
bridge=$(realpath "$4")
files() {
  bsdtar -tf "$1" | grep -vE '^\.|/$' | sort -u
}
missing=$(comm -23 <({ files "$old_runtime"; files "$old_settings"; } | sort -u) <(files "$unified") |
  grep -vx 'usr/share/licenses/monarch-settings/LICENSE' || true)
[[ -z $missing ]] || { printf 'Missing former package files:\n%s\n' "$missing" >&2; exit 1; }
[[ -z $(bsdtar -tf "$bridge" | grep -vE '^\.(PKGINFO|BUILDINFO|MTREE)$' || true) ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root=$work/root
create_root() {
  mkdir -p "$root"/{usr/bin,usr/lib,etc,dev,tmp,var/lib/pacman}
  ln -s usr/bin "$root/bin"
  ln -s usr/lib "$root/lib"
  ln -s usr/lib "$root/lib64"
  ln -s bash "$root/usr/bin/sh"
  for tool in bash install cp chmod rm pacman env; do
    cp "/usr/bin/$tool" "$root/usr/bin/"
    while read -r library; do
      cp -L --parents "$library" "$root/"
    done < <(ldd "/usr/bin/$tool" | awk '/=> \// {print $3} /^\s*\// {print $1}')
  done
  touch "$root/dev/null"
  printf '[options]\nArchitecture = auto\n' >"$root/etc/pacman.conf"
}
create_root
mkdir -p "$work"/{repo,cache,hooks}
cat >"$work/pacman.conf" <<EOF
[options]
Architecture = auto
SigLevel = Never
LocalFileSigLevel = Never
[fixture]
Server = file://$work/repo
EOF
export MONARCH_UPDATE_PACMAN=1
pm() {
  pacman --config "$work/pacman.conf" --root "$root" \
    --dbpath "$root/var/lib/pacman" --logfile "$work/pacman.log" \
    --cachedir "$work/cache" --hookdir "$work/hooks" "$@"
}

mkdir "$work/dependencies"
{
  printf 'pkgname = test-dependencies\npkgver = 1-1\narch = any\npkgdesc = External dependency providers for the isolated root\nsize = 0\n'
  for archive in "$old_runtime" "$old_settings" "$unified"; do
    bsdtar -xOf "$archive" .PKGINFO | sed -n 's/^depend = /provides = /p'
  done | sort -u | grep -vE '^provides = monarch(-settings)?([<>=].*)?$'
} >"$work/dependencies/.PKGINFO"
bsdtar -cf "$work/test-dependencies.pkg.tar" -C "$work/dependencies" .PKGINFO
pm -U --noconfirm "$work/test-dependencies.pkg.tar" "$old_runtime" "$old_settings"
bsdtar -xOf "$unified" usr/share/monarch/install/reconcile/package-layout.sh >"$root/tmp/package-layout.sh"
chroot "$root" /bin/bash /tmp/package-layout.sh
pm -Q monarch-settings
mapfile -t backups < <(bsdtar -xOf "$old_settings" .PKGINFO | sed -n 's/^backup = //p')
(( ${#backups[@]} > 0 ))
mkdir "$work/expected"
bsdtar -xf "$unified" -C "$work/expected" "${backups[@]}"
untouched=${backups[0]}
printf 'stale backup must not become active\n' >"$root/$untouched.pacsave"
for path in "${backups[@]}"; do
  [[ $path != "$untouched" ]] || continue
  printf '\n# local edit retained across the package merge\n' >>"$root/$path"
done
mkdir -p "$root/home/test/.config/noctalia"
printf 'user overlay\n' >"$root/home/test/.config/noctalia/user.toml"
cp -a "$root/etc" "$work/edited-etc"
cp "$unified" "$bridge" "$work/repo/"
repo-add "$work/repo/fixture.db.tar.gz" "$work/repo/${unified##*/}" "$work/repo/${bridge##*/}" >/dev/null
pm -Syyu --noconfirm

[[ -z $(pm -Qql monarch-settings) ]]
chroot "$root" /bin/bash /usr/share/monarch/install/reconcile/package-layout.sh
chroot "$root" /bin/bash /usr/share/monarch/install/reconcile/package-layout.sh
! pm -Q monarch-settings
pm -T monarch-settings
pm -Qk monarch
for path in "${backups[@]}"; do
  cmp "$root/$path" "$work/edited-etc/${path#etc/}"
  [[ $(pm -Qqo "$root/$path") == monarch ]]
  if [[ $path == "$untouched" ]]; then
    cmp "$root/$path.pacsave" "$work/edited-etc/${path#etc/}.pacsave"
  else
    [[ ! -e $root/$path.pacsave ]]
    cmp "$root/$path.pacnew" "$work/expected/$path"
  fi
done
[[ $(pm -Qqo "$root/usr/share/monarch/default/i18n/i18n.py") == monarch ]]
[[ $(pm -Qqo "$root/usr/bin/monarch") == monarch ]]
[[ $(<"$root/home/test/.config/noctalia/user.toml") == 'user overlay' ]]
cmp "$root/etc/os-release" "$root/usr/share/monarch/etc-overrides/os-release"
echo 'ok - a repository upgrade retires settings, transfers ownership and retains every edited backup and user overlay'

pm -S --noconfirm monarch
for path in "${backups[@]}"; do
  cmp "$root/$path" "$work/edited-etc/${path#etc/}"
done
echo 'ok - reinstalling the unified package preserves edited configuration'

pm -U --noconfirm "$old_runtime" "$old_settings"
for path in "${backups[@]}"; do
  cmp "$root/$path" "$work/edited-etc/${path#etc/}"
  [[ $(pm -Qqo "$root/$path") == monarch-settings ]]
done
echo 'ok - downgrading to the former package pair retains edited configuration'

root=$work/fresh
create_root
pm -U --noconfirm "$work/test-dependencies.pkg.tar" "$unified"
! pm -Q monarch-settings
pm -Qk monarch
chroot "$root" /bin/bash /usr/share/monarch/install/reconcile/package-layout.sh
for path in "${backups[@]}"; do
  cmp "$root/$path" "$work/expected/$path"
done
cmp "$root/etc/os-release" "$root/usr/share/monarch/etc-overrides/os-release"
echo 'ok - fresh installation needs only monarch and applies its defaults and scriptlet'

root=$work/mismatch
create_root
# Deliberately bypass dependency checks to model an incomplete installation.
pm -Udd --noconfirm "$bridge"
bsdtar -xOf "$unified" usr/share/monarch/install/reconcile/package-layout.sh >"$root/tmp/package-layout.sh"
if chroot "$root" /bin/bash /tmp/package-layout.sh; then
  echo 'Cleanup accepted a missing Monarch runtime' >&2
  exit 1
fi
pm -Q monarch-settings
pm -Udd --noconfirm "$old_runtime"
if chroot "$root" /bin/bash /tmp/package-layout.sh; then
  echo 'Cleanup accepted a mismatched Monarch runtime' >&2
  exit 1
fi
pm -Q monarch-settings
echo 'ok - missing and mismatched runtimes retain the bridge and fail cleanup'
