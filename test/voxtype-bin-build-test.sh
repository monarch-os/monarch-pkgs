#!/usr/bin/env bash
set -euo pipefail

ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/voxtype-build-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/pkgbuilds/voxtype-bin" "$tmp/pkgbuilds/other" "$tmp/src" "$tmp/output" "$tmp/home"
cp "$ROOT/pkgbuilds/voxtype-bin/PKGBUILD" "$tmp/pkgbuilds/voxtype-bin/PKGBUILD"
printf 'pkgname=other\npkgver=1\npkgrel=1\n' > "$tmp/pkgbuilds/other/PKGBUILD"

eval "$(sed -n '/^build_package() {/,/^}/p' "$ROOT/build/build.sh" |
  sed -e "s|/pkgbuilds/|$tmp/pkgbuilds/|g" -e "s|/src|$tmp/src|g")"
pkgbuild_declared_version() { echo 1-1; }
get_local_version() { :; }
sudo() { :; }
gpg() { :; }
BUILD_OUTPUT_DIR="$tmp/output"
FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""

build_with_makepkg() {
  local target=${ARCH:-x86_64}
  if [[ $pkg == voxtype-bin ]]; then
    [[ ${VOXTYPE_VARIANTS:-} == all ]] || return 1
    env | grep -qx 'VOXTYPE_VARIANTS=all' || return 1
    (
      export CARCH="$target" HOME="$tmp/home"
      source PKGBUILD || exit 1
      export srcdir="$tmp/src-assets" pkgdir="$tmp/package-$target"
      mkdir -p "$srcdir" "$pkgdir"
      [[ ${_vt_selected[*]} == "${!variant_list}" ]] || exit 1
      local -n sources="source_$target"
      local -n assets="_vt_assets_$target"
      (( ${#sources[@]} == 2 * ${#assets[@]} )) || exit 1
      local entry asset variant
      for entry in "${assets[@]}"; do
        IFS='|' read -r variant asset _ <<<"$entry"
        touch "$srcdir/voxtype-$pkgver-$asset"
      done
      mkdir -p "$srcdir/voxtype-$_vt_ver"/{quickshell,examples/osd-packages,examples/osd-recipes,packaging/completions,scripts,omarchy-plugin}
      printf 'mkdir -p "$2/io.voxtype.settings/%s"\nprintf '\''{"version":"%s"}'\'' > "$2/io.voxtype.settings/manifest.json"\ntouch "$2/io.voxtype.settings/%s/Panel.qml"\n' \
        "$_vt_ver" "$_vt_ver" "$_vt_ver" > "$srcdir/voxtype-$_vt_ver/scripts/stage-omarchy-plugin.sh"
      touch "$srcdir/voxtype-$_vt_ver/THIRD_PARTY.md"
      for asset in "config-$pkgver.toml" "voxtype-$pkgver.service" "voxtype-$pkgver.bash" "voxtype-$pkgver.zsh" "voxtype-$pkgver.fish" \
        "LICENSE-$pkgver" "README-$pkgver.md" "voxtype-configure-$pkgver.desktop" "voxtype-configure-launcher-$pkgver"; do
        touch "$srcdir/$asset"
      done
      package || exit 1
      for variant in ${!variant_list}; do
        [[ -e $pkgdir/usr/lib/voxtype/voxtype-$variant ]] || exit 1
      done
      grep -Fx "included=${!variant_list}" "$pkgdir/usr/lib/voxtype/package-variants" || exit 1
    ) || return 1
  else
    [[ -z ${VOXTYPE_VARIANTS:-} ]]
  fi
}

export VOXTYPE_VARIANTS=baseline
for ARCH in x86_64 aarch64; do
  case "$ARCH" in
    x86_64) variant_list=expected_x86_64 ;;
    aarch64) variant_list=expected_aarch64 ;;
  esac
  expected_x86_64='baseline avx2 avx512 vulkan onnx-avx2 onnx-avx512 onnx-cuda-12 onnx-cuda-13 onnx-migraphx'
  expected_aarch64='cpu onnx'
  build_package voxtype-bin
  [[ $VOXTYPE_VARIANTS == baseline ]]
  echo "PASS: repository build selects and exports all $ARCH variants"
done
build_package other
[[ $VOXTYPE_VARIANTS == baseline ]]
echo 'PASS: selection does not leak to other packages or the caller'
