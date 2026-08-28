#!/bin/bash

set -euo pipefail

(($# == 1)) || {
  echo "Expected one monarch-settings package archive" >&2
  exit 2
}

contents=$(bsdtar -tf "$1")

grep -q '^etc/skel/.local/share/noctalia/plugins/.*/' <<<"$contents"
grep -qx 'etc/skel/.local/state/noctalia/.setup-complete' <<<"$contents"
grep -qx 'usr/lib/tmpfiles.d/monarch-nopasswd-sudo.conf' <<<"$contents"

echo "Monarch settings package contains Noctalia defaults and sudo cleanup"
