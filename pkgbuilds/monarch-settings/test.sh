#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if rg -n 'cups-browsed|cups-cups-browsed' \
  "$root/PKGBUILD" "$root/monarch-settings.install"; then
  echo "monarch-settings still owns cups-browsed configuration" >&2
  exit 1
fi

echo "monarch-settings leaves cups-browsed configuration unowned"
