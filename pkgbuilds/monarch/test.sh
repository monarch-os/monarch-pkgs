#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if rg -n 'cups-browsed|cups-cups-browsed' \
  "$root/PKGBUILD" "$root/monarch.install"; then
  echo "monarch still owns cups-browsed configuration" >&2
  exit 1
fi

echo "monarch leaves cups-browsed configuration unowned"

if [[ -n ${MONARCH_SOURCE_PATH:-} ]]; then
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT
  export MONARCH_SRC="$MONARCH_SOURCE_PATH"
  source "$root/PKGBUILD"
  srcdir="$temporary/src"
  pkgdir="$temporary/pkg"
  mkdir -p "$srcdir" "$pkgdir"
  ln -s "$MONARCH_SOURCE_PATH" "$srcdir/monarch"
  cp "$root/build-noctalia-templates.py" "$srcdir/"
  pkgver=$(pkgver)
  package_monarch
  [[ $(<"$pkgdir/usr/share/monarch/version") == "$pkgver" ]]
  [[ $(<"$pkgdir/usr/share/monarch/revision") == "$(git -C "$MONARCH_SOURCE_PATH" rev-parse HEAD)" ]]
  [[ -L $pkgdir/usr/bin/monarch ]]
  SETTINGS_TEST_ROOT="$pkgdir" python3 <<'PY'
import hashlib
import json
import os
from pathlib import Path
import tomllib

root = Path(os.environ['SETTINGS_TEST_ROOT'])
home = root / 'etc/skel'
assert not (home / '.local/state/noctalia/settings.toml').exists()
cache = home / '.local/state/noctalia/community-templates'
bundle = root / 'usr/share/monarch/default/noctalia/community-templates'
sources = Path(os.environ['MONARCH_SOURCE_PATH']) / 'default/noctalia/community-templates'
assert (bundle / 'upstream.json').read_bytes() == (sources / 'upstream.json').read_bytes()
catalog = json.loads((cache / 'catalog.json').read_text())['templates']
assert {entry['name'] for entry in catalog} == {'neovim', 'obsidian', 'zed', 'vscode'}
assert (cache / 'catalog.json').read_bytes() == (bundle / 'catalog.json').read_bytes()
for entry in catalog:
  name = entry['name']
  metadata = json.loads((cache / name / '.noctalia-cache.json').read_text())
  assert metadata['version'] == 1
  assert set(metadata['files']) == {path.name for path in (cache / name).iterdir() if path.name != '.noctalia-cache.json'}
  assert set(metadata['files']) == {file['name'] for file in entry['files']}
  manifest = tomllib.loads((cache / name / 'template.toml').read_text())
  assert entry['display_name'] == manifest['catalog'][name]['name']
  assert entry['category'] == manifest['catalog'][name]['category']
  for template in manifest['templates'].values():
    assert (cache / name / template['input_path']).is_file()
  for file in entry['files']:
    filename = file['name']
    path = cache / name / filename
    assert hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest() == metadata['files'][filename] == file['md5']
    assert f'{path.stat().st_mode & 0o777:04o}' == file['mode']
    assert path.read_bytes() == (bundle / name / filename).read_bytes()
    assert path.read_bytes() == (sources / name / filename).read_bytes()
  assert (cache / name / '.noctalia-cache.json').read_bytes() == (bundle / name / '.noctalia-cache.json').read_bytes()
PY
  echo "monarch provides tracked templates before first login"
fi
