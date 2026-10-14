pkgbuild_has_pkgver() {
  local pkgbuild="$1"
  (
    cd -- "$(dirname -- "$pkgbuild")" || exit 1
    bash -c 'unset -f pkgver; source "$1" && declare -F pkgver >/dev/null' \
      _ "./$(basename -- "$pkgbuild")"
  ) >/dev/null
}

pkgbuild_declared_version() {
  local pkgbuild="$1" srcinfo
  shift
  srcinfo=$(
    cd -- "$(dirname -- "$pkgbuild")" || exit 1
    makepkg --printsrcinfo -p "./$(basename -- "$pkgbuild")" "$@"
  ) || return
  awk '
    $1 == "epoch" && $2 == "=" { epoch=$3 }
    $1 == "pkgver" && $2 == "=" { version=$3 }
    $1 == "pkgrel" && $2 == "=" { release=$3 }
    END {
      if (version == "" || release == "") exit 1
      if (epoch != "") printf "%s:", epoch
      printf "%s-%s\n", version, release
    }
  ' <<<"$srcinfo"
}

build_with_makepkg() {
  if ! pkgbuild_has_pkgver PKGBUILD; then
    makepkg "$@"
    return
  fi

  local declared_version declared_pkgrel
  declared_version=$(pkgbuild_declared_version PKGBUILD "$@") || return
  declared_pkgrel="${declared_version##*-}"
  if [[ ! $declared_pkgrel =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    printf 'Invalid declared pkgrel: %s\n' "$declared_pkgrel" >&2
    return 1
  fi

  # makepkg resets pkgrel to 1 when pkgver() changes the static version.
  # Resolve it first, then build the same prepared sources with the intended release.
  makepkg --nobuild "$@" || return
  sed -i "s/^pkgrel=.*/pkgrel=$declared_pkgrel/" PKGBUILD || return 1
  makepkg --noextract "$@"
}
