#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PKGBUILD="$ROOT/pkgbuilds/monarch-settings/PKGBUILD"

grep -qF 'default/noctalia/plugins/. "$pkgdir/etc/skel/.local/share/noctalia/plugins/"' \
  "$PKGBUILD"
grep -qF 'touch "$pkgdir/etc/skel/.local/state/noctalia/.setup-complete"' "$PKGBUILD"
grep -qF 'default/tmpfiles.d/monarch-nopasswd-sudo.conf' "$PKGBUILD"

echo "Monarch settings packages Noctalia defaults and sudo cleanup"
