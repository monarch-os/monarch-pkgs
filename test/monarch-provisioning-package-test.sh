#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
unset MONARCH_LOCAL_PKGVER MONARCH_LOCAL_REVISION
temporary=$(mktemp -d "${TMPDIR:-/tmp}/monarch-provisioning-package.XXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
export MONARCH_SRC="$temporary/fixture"
srcdir="$temporary/src"
pkgdir="$temporary/pkg"
mkdir -p "$srcdir/monarch"

python3 - "$ROOT/pkgbuilds/monarch/PKGBUILD" "$srcdir/monarch" <<'PY'
from pathlib import Path
import re
import sys

recipe = Path(sys.argv[1]).read_text()
root = Path(sys.argv[2])
for directory in ('assets', 'bin', 'install/helpers', 'themes', 'config/monarch',
                  'applications', 'etc', 'default/noctalia/plugins',
                  'default/sddm/monarch', 'default/plymouth'):
    (root / directory).mkdir(parents=True, exist_ok=True)
paths = re.findall(r'install -Dm\d+ (\S+)', recipe)
paths += ['LICENSE', 'README.md', 'boot.sh', 'install.sh', 'icon.png', 'icon.txt',
          'logo.svg', 'logo.txt', 'bin/monarch', 'install/helpers/provisioning-fixture.sh']
for value in paths:
    value = value.strip('"').removeprefix('$srcdir/monarch/')
    path = root / value
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('fixture\n')
for name in ('neovim', 'obsidian', 'zed', 'vscode'):
    directory = root / 'default/noctalia/community-templates' / name
    directory.mkdir(parents=True)
    (directory / 'template.toml').write_text(
        f'[catalog.{name}]\nname = "{name}"\ncategory = "fixture"\n')
(root / 'install/helpers/provisioning-fixture.sh').chmod(0o755)
PY
cp "$ROOT/pkgbuilds/monarch/build-noctalia-templates.py" "$srcdir/"

if [[ -n ${MONARCH_PACKAGE_SOURCE_CASE:-} ]]; then
  mv "$srcdir/monarch" "$MONARCH_SRC"
  source "$ROOT/pkgbuilds/monarch/PKGBUILD"
  case $MONARCH_PACKAGE_SOURCE_CASE in
    worktree | git | missing-revision | invalid-revision | mismatched-revision)
      git clone --quiet --shared --no-checkout "$ROOT" "$temporary/git-fixture"
      mv "$temporary/git-fixture/.git" "$MONARCH_SRC/.git"
      expected_revision=$(git -C "$MONARCH_SRC" rev-parse HEAD)
      mkdir -p "$srcdir/monarch"
      mkdir -p "$temporary/version-source"
      ln -s "$MONARCH_SRC" "$temporary/version-source/monarch"
      expected_version=$(srcdir="$temporary/version-source"; pkgver)
      if [[ $MONARCH_PACKAGE_SOURCE_CASE != git ]]; then
        export MONARCH_LOCAL_PKGVER="$expected_version"
        export MONARCH_LOCAL_REVISION="$expected_revision"
        if [[ $MONARCH_PACKAGE_SOURCE_CASE == mismatched-revision ]]; then
          MONARCH_LOCAL_REVISION=0000000000000000000000000000000000000000
        else
          mv "$MONARCH_SRC/.git" "$temporary/hidden-git"
          printf 'gitdir: /nonexistent-container-host/worktrees/runtime\n' >"$MONARCH_SRC/.git"
        fi
        [[ $MONARCH_PACKAGE_SOURCE_CASE != missing-revision ]] || unset MONARCH_LOCAL_REVISION
        [[ $MONARCH_PACKAGE_SOURCE_CASE != invalid-revision ]] || MONARCH_LOCAL_REVISION=not-a-revision
      fi
      ;;
    tar)
      expected_version=1.2.3
      printf '%s\n' "$expected_version" >"$MONARCH_SRC/version"
      ;;
    *) exit 2 ;;
  esac
  if [[ $MONARCH_PACKAGE_SOURCE_CASE == *revision ]]; then
    if (set -e; prepare); then
      echo "FAIL: accepted $MONARCH_PACKAGE_SOURCE_CASE provenance" >&2
      exit 1
    fi
    echo "PASS: rejected $MONARCH_PACKAGE_SOURCE_CASE provenance"
    exit 0
  fi
  prepare
  actual_version=$(cd "$srcdir/monarch"; pkgver)
  [[ $actual_version == "$expected_version" ]] || {
    echo "FAIL: $MONARCH_PACKAGE_SOURCE_CASE pkgver=$actual_version expected=$expected_version" >&2
    exit 1
  }
fi

for CARCH in x86_64 aarch64; do
  (
    source "$ROOT/pkgbuilds/monarch/PKGBUILD"
    [[ $pkgrel == 6 && ${pkgname[*]} == 'monarch monarch-settings' ]]
    for dependency in binutils limine-mkinitcpio-hook; do
      printf '%s\n' "${depends[@]}" | grep -qxF "$dependency"
    done
    [[ ${arch[*]} == any ]]
    echo "PASS: $CARCH runtime metadata declares binutils and the existing initramfs provider"
  )
done

source "$ROOT/pkgbuilds/monarch/PKGBUILD"
if [[ -n ${MONARCH_PACKAGE_SOURCE_CASE:-} ]]; then
  pkgver=$actual_version
fi
(package_monarch)
if [[ -n ${MONARCH_PACKAGE_SOURCE_CASE:-} ]]; then
  if [[ $MONARCH_PACKAGE_SOURCE_CASE == tar ]]; then
    [[ ! -e $pkgdir/usr/share/monarch/revision ]]
  else
    [[ $(cat "$pkgdir/usr/share/monarch/revision") == "$expected_revision" ]]
  fi
  [[ $(cat "$pkgdir/usr/share/monarch/version") == "$pkgver" ]]
  echo "PASS: $MONARCH_PACKAGE_SOURCE_CASE prepare/pkgver/package preserve source provenance"
fi
helper=usr/share/monarch/install/helpers/provisioning-fixture.sh
cmp "$srcdir/monarch/install/helpers/provisioning-fixture.sh" "$pkgdir/$helper"
[[ -x $pkgdir/$helper ]]
[[ -L $pkgdir/usr/bin/monarch ]]
[[ $(readlink "$pkgdir/usr/bin/monarch") == /usr/share/monarch/bin/monarch ]]
echo 'PASS: real package function recursively carries a fixture install helper with executable mode and dispatcher link'

pkgdir="$temporary/bridge"
mkdir "$pkgdir"
package_monarch-settings
[[ ${depends[*]} == "monarch=$pkgver-$pkgrel" ]]
[[ ${#backup[@]} == 0 && -z $install ]]
[[ -z $(find "$pkgdir" -mindepth 1 -print -quit) ]]
echo 'PASS: empty monarch-settings bridge retains exact version-release dependency'
