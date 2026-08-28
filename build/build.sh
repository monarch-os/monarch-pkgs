#!/bin/bash
# Simplified build script - builds all packages in /pkgbuilds/

# Import GPG keys
/build/import-gpg-keys.sh || exit 1

# Setup directories
ARCH=${ARCH:-x86_64}
BUILD_OUTPUT_DIR="/build-output/$ARCH"
FINAL_OUTPUT_DIR="/pkgs.monarchlinux.com/$ARCH"

mkdir -p "$BUILD_OUTPUT_DIR" "$FINAL_OUTPUT_DIR"

# makepkg -s installs missing deps with a stock pacman that defaults conflict
# replacement prompts to 'N' and aborts. build_package runs makepkg with
# PACMAN pointed at an --ask 4 wrapper. The Dockerfile bakes that wrapper in for
# bin/build; create it here too so build.sh also works when run directly in a
# bare container (e.g. the nightly CI), where the Dockerfile isn't used.
if [[ ! -x /usr/local/bin/pacman-for-makepkg ]]; then
  printf '#!/bin/bash\nexec /usr/bin/pacman --ask 4 "$@"\n' | sudo tee /usr/local/bin/pacman-for-makepkg >/dev/null
  sudo chmod +x /usr/local/bin/pacman-for-makepkg
fi

# Source the package-metadata helper (used by the VCS rebuild-skip). Resolve it
# from this script's location so it works both in bin/build's container
# (/build/build.sh -> /helpers, mounted by bin/build) and when build.sh is run
# directly from the repo (build/build.sh -> ../helpers, e.g. the nightly CI).
HELPERS_DIR="${HELPERS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers" 2>/dev/null && pwd)}"
if [[ -n "$HELPERS_DIR" && -f "$HELPERS_DIR/package-metadata.sh" ]]; then
  source "$HELPERS_DIR/package-metadata.sh"
  METADATA_HELPERS=true
else
  METADATA_HELPERS=false
  echo "==> WARNING: package-metadata.sh not found; VCS rebuild-skip disabled"
fi

# Configure Monarch repositories for dependency resolution
echo "==> Configuring Monarch repositories for dependency resolution..."

# Always add monarch-build repo (for incremental builds)
# Packages in build-output are unsigned, so use SigLevel = Never
sudo tee -a /etc/pacman.conf > /dev/null <<EOF

[monarch-build]
SigLevel = Never
Server = file://$BUILD_OUTPUT_DIR
EOF
echo "  -> monarch-build (priority 1): $BUILD_OUTPUT_DIR"

# Initialize empty build database if it doesn't exist
cd "$BUILD_OUTPUT_DIR"
if [[ ! -f "monarch-build.db.tar.zst" ]]; then
  # Create an empty database
  repo-add monarch-build.db.tar.zst >/dev/null 2>&1
  ln -sf monarch-build.db.tar.zst monarch-build.db
else
  # Database exists, check if we need to rebuild it from packages
  if ls *.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | grep -v 'monarch-build\.db' | grep -q .; then
    echo "==> Rebuilding build database from existing packages..."
    ls *.pkg.tar.* | grep -v '\.sig$' | grep -v 'monarch-build\.db' | xargs -r repo-add monarch-build.db.tar.zst >/dev/null 2>&1
    ln -sf monarch-build.db.tar.zst monarch-build.db
  fi
fi

# Add monarch repo if it has a database (stable packages)
if [[ -f "$FINAL_OUTPUT_DIR/monarch.db.tar.zst" ]] || [[ -f "$FINAL_OUTPUT_DIR/monarch.db" ]]; then
  sudo tee -a /etc/pacman.conf > /dev/null <<EOF

[monarch]
SigLevel = Optional TrustAll
Server = file://$FINAL_OUTPUT_DIR
EOF
  echo "  -> monarch (priority 2): $FINAL_OUTPUT_DIR"
fi

# Sync pacman database
sudo pacman -Sy

echo "==> Package Builder"
echo "==> Target architecture: $ARCH"
echo "==> Build workspace: $BUILD_OUTPUT_DIR"
echo "==> Final output: $FINAL_OUTPUT_DIR"

FAILED_PACKAGES=""
SUCCESSFUL_PACKAGES=""
SKIPPED_PACKAGES=""

# Source package directories are named after the PKGBUILD pkgbase, but split
# packages are stored in the repo DB under their individual pkgname entries.
# Cache versions by both %NAME% and %BASE% so a pkgbase like `yaru` is found
# even though the DB only contains packages like `yaru-icon-theme`.
declare -A LOCAL_VERSION_BY_NAME=()
declare -A LOCAL_VERSION_BY_BASE=()
LOCAL_VERSION_CACHE_LOADED=false
LOCAL_VERSION_CACHE_DB=""

load_local_versions() {
  local db="$FINAL_OUTPUT_DIR/monarch.db.tar.zst"

  if [[ ! -f "$db" ]]; then
    db="$FINAL_OUTPUT_DIR/monarch.db"
  fi

  [[ -f "$db" ]] || return 0
  [[ "$LOCAL_VERSION_CACHE_LOADED" == true && "$LOCAL_VERSION_CACHE_DB" == "$db" ]] && return 0

  LOCAL_VERSION_BY_NAME=()
  LOCAL_VERSION_BY_BASE=()

  local name base version
  while IFS=$'\t' read -r name base version; do
    [[ -n "$name" && -n "$version" ]] && LOCAL_VERSION_BY_NAME["$name"]="$version"
    [[ -n "$base" && -n "$version" ]] && LOCAL_VERSION_BY_BASE["$base"]="$version"
  done < <(
    tar -xOf "$db" --wildcards '*/desc' 2>/dev/null | awk '
      function emit() {
        if (name != "" && version != "") print name "\t" base "\t" version
        name=""; base=""; version=""
      }
      $0 == "%FILENAME%" { emit(); next }
      $0 == "%NAME%" { if (name != "" && version != "") emit(); getline; name=$0; next }
      $0 == "%BASE%" { getline; base=$0; next }
      $0 == "%VERSION%" { getline; version=$0; next }
      END { emit() }
    '
  )

  LOCAL_VERSION_CACHE_LOADED=true
  LOCAL_VERSION_CACHE_DB="$db"
}

# Get version from final output (production packages), by pkgname or pkgbase.
get_local_version() {
  local pkg="$1"

  load_local_versions

  if [[ -n "${LOCAL_VERSION_BY_NAME[$pkg]:-}" ]]; then
    echo "${LOCAL_VERSION_BY_NAME[$pkg]}"
  elif [[ -n "${LOCAL_VERSION_BY_BASE[$pkg]:-}" ]]; then
    echo "${LOCAL_VERSION_BY_BASE[$pkg]}"
  fi
}

# Build a package from /pkgbuilds/
build_package() {
  local pkg="$1"
  
  echo ""
  echo "  -> Processing: $pkg"
  
  # Copy to build directory
  cd /src
  rm -rf "$pkg"
  cp -r "/pkgbuilds/$pkg" "$pkg"
  cd "/src/$pkg" || return 1

  # Get PKGBUILD version (including epoch if present)
  local pkgbuild_version=$(bash -c 'source PKGBUILD; if [[ -n "$epoch" ]]; then echo "${epoch}:${pkgver}-${pkgrel}"; else echo "${pkgver}-${pkgrel}"; fi' 2>/dev/null)
  
  if [[ -z "$pkgbuild_version" ]]; then
    echo "    ❌ Failed to read PKGBUILD version"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi
  
  # Show version info (version check already done in first pass)
  local local_version=$(get_local_version "$pkg")
  if [[ -n "$local_version" ]]; then
    echo "    Update available: $local_version -> $pkgbuild_version"
  else
    echo "    New package (version: $pkgbuild_version)"
  fi
  
  # Import PGP keys the PKGBUILD declares in validpgpkeys, so signed sources
  # verify without hand-maintaining each key in build/gpg-keys.txt.
  local pgp_keys=$(bash -c 'source PKGBUILD 2>/dev/null; echo "${validpgpkeys[@]}"')
  if [[ -n "$pgp_keys" ]]; then
    echo "    Importing PGP keys from validpgpkeys..."
    for key in $pgp_keys; do
      gpg --receive-keys "$key" 2>/dev/null && echo "      ✓ Received $key" || echo "      ⚠ Failed to receive $key"
    done
  fi

  # Import package-specific PGP keys if they exist
  if [[ -d "keys/pgp" ]]; then
    echo "    Importing package-specific PGP keys..."
    for keyfile in keys/pgp/*.asc; do
      if [[ -f "$keyfile" ]]; then
        gpg --import "$keyfile" 2>/dev/null && echo "      ✓ Imported $(basename "$keyfile")" || echo "      ⚠ Failed to import $(basename "$keyfile")"
      fi
    done
  fi
  
  # Build package without signing (signing is done separately).
  # PACMAN= points makepkg's dep install at the --ask 4 wrapper so conflict
  # replacement prompts are auto-accepted instead of aborting the build.
  MAKEPKG_FLAGS="-scf --noconfirm"

  if PACMAN=/usr/local/bin/pacman-for-makepkg makepkg $MAKEPKG_FLAGS; then
    local package_files=()
    for pkg_file in *.pkg.tar.*; do
      [[ -f "$pkg_file" && $pkg_file != *.sig ]] && package_files+=("$pkg_file")
    done

    if [[ -x /pkgbuilds/$pkg/package-test.sh ]]; then
      echo "    Running package tests..."
      if ! /pkgbuilds/$pkg/package-test.sh "${package_files[@]}"; then
        echo "    ❌ Package tests failed for $pkg"
        FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
        return 1
      fi
    fi

    cp "${package_files[@]}" "$BUILD_OUTPUT_DIR/"

    cd "$BUILD_OUTPUT_DIR"

    # Find ALL package files (handles split packages)
    local new_pkgs=($(ls -t ${pkg}-*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | grep -v 'monarch-build\.db'))

    if [[ ${#new_pkgs[@]} -gt 0 ]]; then
      repo-add monarch-build.db.tar.zst "${new_pkgs[@]}" >/dev/null 2>&1
      ln -sf monarch-build.db.tar.zst monarch-build.db
      sudo pacman -Sy >/dev/null 2>&1
    fi
    
    cd /src/$pkg
    
    echo "    ✓ Successfully built $pkg"
    SUCCESSFUL_PACKAGES="$SUCCESSFUL_PACKAGES $pkg"
    return 0
  else
    echo "    ❌ Makepkg failed for $pkg"
    echo "    DEBUG: Files in build directory:"
    ls -lah *.pkg.tar.* 2>&1 | head -20 || echo "    No package files found"
    FAILED_PACKAGES="$FAILED_PACKAGES $pkg"
    return 1
  fi
}

# What each pkgbuilds/ directory provides, mapped back to that directory. A
# dependency may name what a package provides rather than the package itself —
# displaylink wants `evdi`, which pkgbuilds/evdi-dkms provides — and without this
# the ordering below never sees the edge.
declare -A PROVIDER_DIR
build_provider_map() {
  local dir name provided
  for dir in /pkgbuilds/*/; do
    [[ -f "$dir/PKGBUILD" ]] || continue
    name=$(basename "$dir")
    while IFS= read -r provided; do
      provided=$(echo "$provided" | sed 's/[<>=].*$//')
      [[ -n "$provided" && "$provided" != "$name" ]] && PROVIDER_DIR[$provided]="$name"
    done < <(source "$dir/PKGBUILD" 2>/dev/null; printf '%s\n' "${provides[@]}")
  done
}

# Get package dependencies from PKGBUILD
get_package_deps() {
  local pkg="$1"
  local pkgbuild="/pkgbuilds/$pkg/PKGBUILD"
  
  if [[ ! -f "$pkgbuild" ]]; then
    return
  fi
  
  # Extract depends and makedepends, filter for packages in our pkgbuilds/
  (
    source "$pkgbuild" 2>/dev/null
    echo "${depends[@]} ${makedepends[@]}"
  ) | tr ' ' '\n' | while read -r dep; do
    # Strip version constraints (e.g., 'hyprshade>=1.0' -> 'hyprshade')
    dep=$(echo "$dep" | sed 's/[<>=].*$//')
    # Check if this dependency exists in our pkgbuilds, by directory name or by
    # what one of them provides.
    if [[ -d "/pkgbuilds/$dep" ]]; then
      echo "$dep"
    elif [[ -n "${PROVIDER_DIR[$dep]:-}" ]]; then
      echo "${PROVIDER_DIR[$dep]}"
    fi
  done
}

# For a VCS package (pkgver()), the static pkgver in the PKGBUILD is stale, so a
# plain version compare always says "build" — it then rebuilds and collides with
# the identical version already in production. Instead, compare the commit hash
# baked into the published version against the current upstream git ref, and
# skip when they match (unless pkgrel/epoch changed).
check_vcs_unchanged() {
  local pkg="$1"
  local pkgdir="/pkgbuilds/$pkg"
  local pkgbuild="$pkgdir/PKGBUILD"

  grep -qE '^pkgver[[:space:]]*\(\)' "$pkgbuild" || return 1

  local local_version=$(get_local_version "$pkg")
  [[ -z "$local_version" ]] && return 1

  local pkgbuild_epoch=$(cd "$pkgdir" && bash -c 'source PKGBUILD 2>/dev/null; echo "${epoch:-}"')
  local pkgbuild_pkgrel=$(cd "$pkgdir" && bash -c 'source PKGBUILD 2>/dev/null; echo "${pkgrel}"')

  local prod_pkgrel="${local_version##*-}"
  local prod_no_pkgrel="${local_version%-*}"
  local prod_epoch=""
  if [[ "$prod_no_pkgrel" == *:* ]]; then
    prod_epoch="${prod_no_pkgrel%%:*}"
  fi

  [[ "$pkgbuild_epoch" != "$prod_epoch" ]] && return 1
  [[ "$pkgbuild_pkgrel" != "$prod_pkgrel" ]] && return 1

  local prod_hash=$(package_extract_vcs_hash_from_version "$local_version")
  [[ -z "$prod_hash" ]] && return 1

  local upstream_hash=$(package_git_upstream_hash "$pkgdir")
  [[ -z "$upstream_hash" ]] && return 1

  [[ "$prod_hash" == "$upstream_hash" ]]
}

# Check which packages need building (version check only)
check_needs_build() {
  local pkg="$1"
  local pkgbuild="/pkgbuilds/$pkg/PKGBUILD"

  [[ ! -f "$pkgbuild" ]] && return 1

  # Get PKGBUILD version (including epoch if present)
  local pkgbuild_version=$(cd "/pkgbuilds/$pkg" && bash -c 'source PKGBUILD; if [[ -n "$epoch" ]]; then echo "${epoch}:${pkgver}-${pkgrel}"; else echo "${pkgver}-${pkgrel}"; fi' 2>/dev/null)
  [[ -z "$pkgbuild_version" ]] && return 1

  # Check if already built
  local local_version=$(get_local_version "$pkg")

  # VCS-aware path (only when the metadata helper is available).
  if [[ "$METADATA_HELPERS" == true ]] && grep -qE '^pkgver[[:space:]]*\(\)' "$pkgbuild"; then
    if [[ -n "$local_version" && -n "$(package_extract_vcs_hash_from_version "$local_version")" ]]; then
      if check_vcs_unchanged "$pkg"; then
        return 1  # upstream ref already represented in the repo
      else
        return 0  # new ref, missing repo package, or pkgrel/epoch changed
      fi
    elif [[ "$local_version" == "$pkgbuild_version" ]]; then
      return 1  # VCS package without a hash; fall back to static version
    else
      return 0
    fi
  fi

  if [[ "$local_version" == "$pkgbuild_version" ]]; then
    return 1  # Already up to date
  else
    return 0  # Needs building
  fi
}

# Main execution
cd /src

TOTAL_COUNT=0

echo "==> Checking which packages need building..."

# First pass: determine which packages need building
PACKAGES_TO_BUILD=()

# If PACKAGES is specified, only check those packages
if [[ -n "$PACKAGES" ]]; then
  echo "==> Checking specified packages: $PACKAGES"
  for pkg_name in $PACKAGES; do
    if [[ ! -f "/pkgbuilds/$pkg_name/PKGBUILD" ]]; then
      echo "==> ERROR: Package '$pkg_name' not found in /pkgbuilds/"
      exit 1
    fi
    
    if check_needs_build "$pkg_name"; then
      PACKAGES_TO_BUILD+=("$pkg_name")
    else
      echo "  ✓ $pkg_name - already up to date"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg_name"
    fi
  done
else
  # Build all packages that need updates
  for pkgdir in /pkgbuilds/*/; do
    [[ ! -d "$pkgdir" ]] && continue
    pkg=$(basename "$pkgdir")
    [[ ! -f "$pkgdir/PKGBUILD" ]] && continue
    
    if check_needs_build "$pkg"; then
      PACKAGES_TO_BUILD+=("$pkg")
    else
      echo "  ✓ $pkg - already up to date"
      SKIPPED_PACKAGES="$SKIPPED_PACKAGES $pkg"
    fi
  done
fi

if [[ ${#PACKAGES_TO_BUILD[@]} -eq 0 ]]; then
  echo "==> All packages are up to date!"
else
  echo "==> ${#PACKAGES_TO_BUILD[@]} package(s) need building: ${PACKAGES_TO_BUILD[@]}"
  echo "==> Determining build order based on dependencies..."
  build_provider_map
  
  # Second pass: order only the packages that need building
  # Strategy: build packages with no unmet dependencies first
  declare -A unmet_deps_count  # How many dependencies does this package still need?
  declare -A blocks_packages    # Which packages are waiting for this one?
  
  # Count unmet dependencies for each package
  for pkg in "${PACKAGES_TO_BUILD[@]}"; do
    unmet_deps_count[$pkg]=0
  done
  
  # Build the dependency relationships
  for pkg in "${PACKAGES_TO_BUILD[@]}"; do
    while IFS= read -r dep; do
      # Only care about deps that are being built in this run
      for build_pkg in "${PACKAGES_TO_BUILD[@]}"; do
        if [[ "$dep" == "$build_pkg" ]]; then
          # pkg needs dep, so increment pkg's unmet count
          ((unmet_deps_count[$pkg]++))
          # Track that dep blocks pkg from building
          blocks_packages[$dep]="${blocks_packages[$dep]} $pkg"
        fi
      done
    done < <(get_package_deps "$pkg")
  done
  
  # Start with packages that have all dependencies met (count = 0)
  ready_to_build=()
  for pkg in "${PACKAGES_TO_BUILD[@]}"; do
    if [[ ${unmet_deps_count[$pkg]} -eq 0 ]]; then
      ready_to_build+=("$pkg")
    fi
  done
  
  # Build packages as dependencies become available
  ORDERED_PACKAGES=()
  while [[ ${#ready_to_build[@]} -gt 0 ]]; do
    # Take the first ready package
    current="${ready_to_build[0]}"
    ready_to_build=("${ready_to_build[@]:1}")
    ORDERED_PACKAGES+=("$current")
    
    # This package is now built, so packages waiting for it can proceed
    for blocked_pkg in ${blocks_packages[$current]}; do
      ((unmet_deps_count[$blocked_pkg]--))
      if [[ ${unmet_deps_count[$blocked_pkg]} -eq 0 ]]; then
        ready_to_build+=("$blocked_pkg")
      fi
    done
  done
  
  # Check for circular dependencies
  if [[ ${#ORDERED_PACKAGES[@]} -ne ${#PACKAGES_TO_BUILD[@]} ]]; then
    echo "ERROR: Circular dependency detected!"
    exit 1
  fi
  
  echo "==> Build order: ${ORDERED_PACKAGES[@]}"
  
  # Determine which packages need to be installed for other packages being built
  declare -A INSTALL_PACKAGES
  for pkg in "${ORDERED_PACKAGES[@]}"; do
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      # Only install if it's being built in this run
      for build_pkg in "${ORDERED_PACKAGES[@]}"; do
        [[ "$dep" == "$build_pkg" ]] && INSTALL_PACKAGES["$dep"]=1
      done
    done < <(get_package_deps "$pkg")
  done
  
  if [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]]; then
    echo "==> Packages needed as dependencies: ${!INSTALL_PACKAGES[@]}"
  fi
  
  # Build packages in dependency order
  for pkg in "${ORDERED_PACKAGES[@]}"; do
    ((TOTAL_COUNT++))
    build_package "$pkg"
  done
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "==> Build Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Count results
SUCCESS_COUNT=$(echo $SUCCESSFUL_PACKAGES | wc -w)
SKIPPED_COUNT=$(echo $SKIPPED_PACKAGES | wc -w)
FAILED_COUNT=$(echo $FAILED_PACKAGES | wc -w)

echo "  Total packages: $TOTAL_COUNT"
echo "  ✓ Built:        $SUCCESS_COUNT"
echo "  ⏭  Skipped:      $SKIPPED_COUNT (already up-to-date)"
echo "  ❌ Failed:       $FAILED_COUNT"

# List failures if any
if [[ -n "$FAILED_PACKAGES" ]]; then
  echo ""
  echo "Failed packages:"
  for pkg in $FAILED_PACKAGES; do
    echo "  - $pkg"
  done
  echo ""
  echo "==> Some packages failed to build"
  exit 1
fi

echo ""
echo "==> All packages processed successfully!"
