#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
source "$ROOT/pkgbuilds/monarch-todo/PKGBUILD"
[[ $pkgver == "0.1.2" ]] # Keep the published tag until 0.2 is released.
srcdir="$TMP/src"
pkgdir="$TMP/pkg"
tree="$srcdir/$pkgname-$pkgver"
mkdir -p "$tree/target/release" "$pkgdir"
printf '%s\n' '#!/bin/bash' 'exit 0' >"$tree/target/release/monarch-todo"
printf 'license\n' >"$tree/LICENSE"
printf 'readme\n' >"$tree/README.md"
(package)
[[ -x $pkgdir/usr/bin/monarch-todo ]]
[[ -f $pkgdir/usr/share/licenses/monarch-todo/LICENSE ]]
echo 'ok - published legacy tag still packages without a desktop payload'

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
