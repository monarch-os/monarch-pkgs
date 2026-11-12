#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/voxtype-install-test.XXXXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/usr/bin" "$TEST_ROOT/usr/lib/voxtype" "$TEST_ROOT/run"
chmod 700 "$TEST_ROOT/run"

# Relocate literal filesystem paths, not hook logic: no scriptlet touches host /usr or /run.
sed -e "s|/usr/bin/voxtype|$TEST_ROOT/usr/bin/voxtype|g" \
    -e "s|/usr/lib/voxtype|$TEST_ROOT/usr/lib/voxtype|g" \
    -e "s|/run/voxtype-backend-upgrade|$TEST_ROOT/run/voxtype-backend-upgrade|g" \
    "$REPO_ROOT/pkgbuilds/voxtype-bin/voxtype-bin.install" > "$TEST_ROOT/install.sh"
source "$TEST_ROOT/install.sh"
[[ $_backend_state == "$TEST_ROOT/run/voxtype-backend-upgrade" ]]
[[ $_backend_root == "$TEST_ROOT/usr/lib/voxtype" ]]
launcher="$TEST_ROOT/usr/bin/voxtype"
detected_cuda=13
architecture=x86_64
uname() { echo "$architecture"; }
cpu_avx2=1
cpu_avx512=1
_cpu_has() {
    case "$1" in
        avx2) (( cpu_avx2 )) ;;
        avx512f) (( cpu_avx512 )) ;;
    esac
}
_detect_cuda_major() { echo "$detected_cuda"; }
_detect_gpu() { :; }

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
assert_active() {
    [[ $(_resolve_active_binary) == "$1" ]] || fail "unexpected backend: $(_resolve_active_binary) (expected $1)"
    [[ ! -e $_backend_state && ! -L $_backend_state ]] || fail 'state was not consumed'
}
restore() {
    printf '%s\n' "$1" > "$_backend_state"
    _preserve_or_set_backend > /dev/null
    assert_active "$2"
    pass "$3"
}

for name in voxtype-baseline voxtype-avx2 voxtype-avx512 voxtype-cpu voxtype-vulkan voxtype-onnx-avx2 voxtype-onnx-avx512; do
    touch "$_backend_root/$name"
done
for name in cuda-12 cuda-13 migraphx; do
    mkdir "$_backend_root/$name"
    touch "$_backend_root/$name/voxtype-onnx-$name"
done
default="$_backend_root/voxtype-avx512"
touch "$TEST_ROOT/payload"
ln -s "$TEST_ROOT/payload" "$_backend_root/escape"
ln -s "$TEST_ROOT" "$_backend_root/outside"
ln -s voxtype-avx2 "$_backend_root/internal"
ln -s absent "$_backend_root/dangling"
ln -s loop "$_backend_root/loop"

restore "$TEST_ROOT/payload" "$default" 'foreign path rejected'
restore "$_backend_root/../../../payload" "$default" 'traversal rejected'
restore "$_backend_root/escape" "$default" 'escaping file symlink rejected'
restore "$_backend_root/outside/payload" "$default" 'escaping directory symlink rejected'
restore "${_backend_root}-other/payload" "$default" 'prefix sibling rejected'
restore "$_backend_root/missing" "$default" 'missing file rejected'
restore "$_backend_root/dangling" "$default" 'dangling symlink rejected'
restore "$_backend_root/loop" "$default" 'symlink loop rejected'
restore "$_backend_root/cuda-13" "$default" 'directory rejected'
restore "$TEST_ROOT/voxtype-parakeet-avx512" "$default" 'foreign legacy name rejected'
restore "$_backend_root/internal" "$_backend_root/voxtype-avx2" 'internal symlink canonicalized'
restore "$_backend_root/voxtype-vulkan" "$_backend_root/voxtype-vulkan" 'existing GPU backend preserved'
restore "$_backend_root/voxtype-avx512" "$_backend_root/voxtype-avx512" 'existing CPU backend preserved'
cpu_avx512=0
restore "$_backend_root/voxtype-avx512" "$_backend_root/voxtype-avx2" 'unsupported AVX512 falls back to AVX2'
cpu_avx2=0
restore "$_backend_root/voxtype-avx2" "$_backend_root/voxtype-baseline" 'unsupported AVX2 falls back to baseline'
cpu_avx2=1
cpu_avx512=1
restore "$_backend_root/voxtype-parakeet-avx2" "$_backend_root/voxtype-onnx-avx2" 'legacy Parakeet AVX2 mapped'
restore "$_backend_root/voxtype-parakeet-avx512" "$_backend_root/voxtype-onnx-avx512" 'legacy Parakeet AVX512 mapped'
restore "$_backend_root/voxtype-onnx-rocm" "$_backend_root/migraphx/voxtype-onnx-migraphx" 'legacy ROCm mapped to GPU wrapper'
for detected_cuda in 12 13 ''; do
    restore "$_backend_root/voxtype-onnx-cuda" "$_backend_root/cuda-${detected_cuda:-13}/voxtype-onnx-cuda-${detected_cuda:-13}" "legacy CUDA mapped (${detected_cuda:-fallback})"
done

printf '%s\n' 'sentinel' > "$TEST_ROOT/sentinel"
ln -s "$TEST_ROOT/sentinel" "$_backend_state"
_preserve_or_set_backend > /dev/null
assert_active "$default"
[[ $(cat "$TEST_ROOT/sentinel") == sentinel ]] || fail 'state symlink target modified'
pass 'state symlink rejected and unlinked without modifying target'

printf '%s\n' "$_backend_root/voxtype-vulkan" > "$_backend_state"
rm "$launcher"
pre_upgrade
[[ ! -e $_backend_state ]] || fail 'stale state survived missing launcher'
pre_upgrade
pass 'stale state cleanup is idempotent'

for backend in voxtype-avx2 cuda-12/voxtype-onnx-cuda-12 migraphx/voxtype-onnx-migraphx; do
    _install_active_binary "$_backend_root/$backend"
    ln -s "$TEST_ROOT/sentinel" "$_backend_state"
    (umask 000; pre_upgrade)
    [[ $(stat -c %a "$_backend_state") == 600 ]] || fail 'state is not private'
    [[ $(cat "$_backend_state") == "$_backend_root/$backend" ]] || fail 'wrong saved backend'
    [[ $(cat "$TEST_ROOT/sentinel") == sentinel ]] || fail 'pre_upgrade followed state symlink'
    post_upgrade 1.1.1-2 > /dev/null
    assert_active "$_backend_root/$backend"
    pass "pre/post upgrade and private state: $backend"
done

ln -sf "$TEST_ROOT/payload" "$launcher"
pre_upgrade
[[ ! -e $_backend_state ]] || fail 'foreign launcher saved'
pass 'foreign launcher ignored by pre_upgrade'

rm "$launcher"
printf 'exec %s "$@"\n' "$TEST_ROOT/payload" > "$launcher"
pre_upgrade
[[ ! -e $_backend_state ]] || fail 'foreign wrapper saved'
pass 'foreign GPU-style wrapper ignored by pre_upgrade'

ln -sf voxtype-onnx-avx2 "$_backend_root/legacy-alias"
ln -sf "$_backend_root/legacy-alias" "$launcher"
pre_upgrade
[[ $(cat "$_backend_state") == "$_backend_root/voxtype-onnx-avx2" ]] || fail 'launcher alias not canonicalized'
_preserve_or_set_backend > /dev/null
assert_active "$_backend_root/voxtype-onnx-avx2"
pass 'launcher with internal symlink chain canonicalized'

mkdir "$_backend_state"
if pre_upgrade 2>/dev/null; then
    fail 'pre_upgrade ignored cleanup failure'
fi
if _preserve_or_set_backend > /dev/null 2>&1; then
    fail 'restore ignored cleanup failure'
fi
[[ $(_resolve_active_binary) == "$_backend_root/voxtype-onnx-avx2" ]] || fail 'cleanup failure changed launcher'
rmdir "$_backend_state"
pass 'cleanup failure is reported without changing launcher'

_install_active_binary "$_backend_root/voxtype-vulkan"
pre_upgrade
rm "$_backend_root/voxtype-vulkan"
post_upgrade 1.1.1-2 > /dev/null
assert_active "$default"
pass 'backend removed by transaction falls back safely'

_install_active_binary "$_backend_root/cuda-13/voxtype-onnx-cuda-13"
pre_upgrade
pre_upgrade
post_upgrade 1.1.1-2 > /dev/null
assert_active "$_backend_root/cuda-13/voxtype-onnx-cuda-13"
pass 'interrupted pre_upgrade can be repeated'
post_upgrade 1.1.1-2 > /dev/null
assert_active "$default"
pass 'repeated post_upgrade consumes no stale state and uses default'

architecture=aarch64
_preserve_or_set_backend > /dev/null
assert_active "$_backend_root/voxtype-cpu"
pass 'aarch64 default preserved'
printf '%s\n' "$default" > "$_backend_state"
post_remove
post_remove
[[ ! -e $_backend_state && ! -e $launcher ]] || fail 'remove left state or launcher'
pass 'removal cleans upgrade state idempotently'
