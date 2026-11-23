#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/voxtype-failure-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

source "$ROOT/pkgbuilds/voxtype-bin/voxtype-bin.install"
_backend_root="$tmp/backends"
_backend_state="$tmp/state"
mkdir "$_backend_root"
touch "$_backend_root"/voxtype-{baseline,avx2,avx512,cpu,vulkan}
_install_active_binary() { return 1; }
_detect_gpu() { :; }
_set_onnx_cuda_symlink() { :; }
uname() { echo "$architecture"; }
_cpu_has() { [[ $1 == "$cpu_feature" ]]; }

expect_failure() {
  local output
  if output=$("$@"); then
    echo "FAIL: $* masked backend installation failure" >&2
    exit 1
  fi
  if [[ $output == *"backend:"* || $output == *"Backend:"* ||
        $output == *"using voxtype-"* || $output == baseline ||
        $output == avx2 || $output == avx512 || $output == cpu ||
        $output == vulkan ]]; then
    echo "FAIL: $* announced a backend after installation failure" >&2
    exit 1
  fi
}

for architecture in x86_64 aarch64; do
  for cpu_feature in none avx2 avx512f; do
    expect_failure _set_default_backend
    expect_failure _preserve_or_set_backend
    expect_failure post_install
    expect_failure post_upgrade 1.3.1-1.1
    echo "PASS: backend installation failures propagate ($architecture, $cpu_feature)"
  done
done

architecture=x86_64
for backend in voxtype-vulkan voxtype-avx2 voxtype-avx512; do
  case "$backend" in
    voxtype-avx2) cpu_feature=avx2 ;;
    voxtype-avx512) cpu_feature=avx512f ;;
    *) cpu_feature=none ;;
  esac
  for caller in _preserve_or_set_backend post_upgrade; do
    printf '%s\n' "$_backend_root/$backend" > "$_backend_state"
    expect_failure "$caller" 1.3.1-1.1
    echo "PASS: restored backend failure propagates through $caller ($backend)"
  done
done
