build_with_makepkg() {
  if ! grep -qE '^pkgver[[:space:]]*\(\)' PKGBUILD; then
    makepkg "$@"
    return
  fi

  local declared_pkgrel
  declared_pkgrel=$(bash -c 'source PKGBUILD; printf "%s" "$pkgrel"') || return 1
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
