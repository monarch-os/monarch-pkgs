#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/pkgbuilds/monarch-todo/PKGBUILD"
[[ $pkgver == "0.2.0" && $pkgrel == "1" ]]
[[ ${source[0]} == *'#tag=v0.2.0' ]]
srcdir="$TMP/src"
pkgdir="$TMP/pkg"
tree="$srcdir/$pkgname-$pkgver"
mkdir -p "$tree/target/release" "$pkgdir"
printf '%s\n' '#!/bin/bash' 'exit 0' >"$tree/target/release/monarch-todo"
printf 'license\n' >"$tree/LICENSE"
printf 'readme\n' >"$tree/README.md"
if (package) >/dev/null 2>&1; then
  echo 'incomplete source incorrectly produced a binary-only package' >&2
  exit 1
fi
[[ ! -e $pkgdir/usr/bin/monarch-todo ]]
echo 'ok - 0.2.0 rejects an incomplete desktop source instead of falling back to a legacy package'

mkdir -p "$tree/noctalia/monarch-todo"
printf 'id = "monarch/todo"\n' >"$tree/noctalia/monarch-todo/plugin.toml"
cat >"$tree/Makefile" <<'EOF'
install:
	mkdir -p "$(DESTDIR)$(PREFIX)/share/monarch-todo"
	printf 'owned by package\n' >"$(DESTDIR)$(PREFIX)/share/monarch-todo/payload"
EOF
(package)
[[ $(<"$pkgdir/usr/share/monarch-todo/payload") == "owned by package" ]]
echo 'ok - new source delegates the complete system payload to make install'
! grep -qi 'launch the tui\|in the tui' "$ROOT/pkgbuilds/monarch-todo/monarch-todo.install"
