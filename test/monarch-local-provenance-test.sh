#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
for scenario in worktree git tar missing-revision invalid-revision mismatched-revision; do
  MONARCH_PACKAGE_SOURCE_CASE=$scenario bash "$ROOT/test/monarch-provisioning-package-test.sh"
done
