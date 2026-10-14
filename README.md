# Monarch Package Repository

Build system for the Monarch Package Repository. This repo is a fork of [Omarchy Package repository](https://github.com/omacom-io/omarchy-pkgs/)

**Multi-Architecture**: Supports both x86_64 and aarch64 (ARM64).

## Prerequisites
### aarch64 Builds (Optional)

To build ARM64 packages on x86_64, enable QEMU emulation:

```bash
# Run after each reboot
docker run --privileged --rm tonistiigi/binfmt --install arm64

# Verify
docker run --rm --platform linux/arm64 alpine:latest uname -m
# Should output: aarch64
```

**Note**: aarch64 builds use QEMU and slower than native x86_64 builds.

## Quick Start

### Complete Workflow

```bash
# Build, sign, promote, clean, and sync
bin/repo release

# Single package
bin/repo release --package omarchy-nvim

# ARM64
bin/repo release --arch aarch64 --package omarchy-nvim
```

### Step-by-Step

```bash
bin/repo build                          # Build (unsigned)
bin/repo sign                           # Sign packages
bin/repo promote                        # Copy to production
bin/repo clean                          # Remove old versions
bin/repo sync pkgs.omarchy.org/x86_64   # Sync to remote
```

## Commands

### Build

```bash
bin/repo build                                   # All packages (x86_64)
bin/repo build --package yay cursor-bin          # Specific packages
bin/repo build --arch aarch64                    # ARM64
```

**Output**: Unsigned `.pkg.tar.zst` in `build-output/`

For VCS recipes, the builder resolves `pkgver()` before packaging, restores the
recipe's declared `pkgrel`, and builds the same prepared sources with
`--noextract`. This prevents makepkg's automatic reset to `pkgrel=1` from
rebuilding an already published version indefinitely. Non-VCS recipes keep the
normal single-pass build.
VCS detection loads the PKGBUILD as Bash, so function-keyword and indented
`pkgver` declarations behave the same as `pkgver()` declarations.
Release/version metadata comes from `makepkg --printsrcinfo`, using the same
configuration and target context as the build. Architecture-dependent releases
are therefore preserved and compared consistently during unchanged-build checks.

### Sign

```bash
bin/repo sign
```

Fetches GPG key from 1Password or environment, signs all packages in `build-output/`.

### Promote

```bash
bin/repo promote                    # Copy to production
bin/repo promote --arch aarch64     # ARM64
bin/repo promote --dry-run          # Preview
```

Moves signed packages from `build-output/<arch>/` to
`pkgs.monarchlinux.com/<arch>/` without overwriting published files.

An already published archive is skipped only when its bytes are identical and
its published signature exists. The original archive and signature are retained,
even if the staged archive was re-signed. Different archive contents under the
same filename stop the entire batch before any package is promoted: bump the
recipe's `pkgrel` instead. Local promotions sharing a build directory are locked
against overlap.

Regression checks (run the makepkg test on an Arch host with makepkg, fakeroot
and bsdtar; it does not install dependencies):

```bash
bash test/makepkg-pkgrel-test.sh
bash test/promote-build-test.sh
bash test/monarch-version-test.sh
bash test/monarch-vcs-skip-test.sh
```

### Clean

```bash
bin/repo clean                      # Keep 2 versions
bin/repo clean --keep 3             # Keep 3 versions
bin/repo clean --dry-run            # Preview
```

Removes old versions, updates database.

### Sync

```bash
bin/repo sync pkgs.omarchy.org/x86_64                    # Production
bin/repo sync pkgs.omarchy.org/aarch64                   # ARM64
bin/repo sync pkgs.omarchy.org/x86_64 --skip-prod-check # No confirmation
```

Syncs to remote server using rclone.

### Other

```bash
bin/repo list                       # List packages
bin/repo remove <package>           # Remove package
bin/repo update                     # Update database
```

## Directory Structure

```
omarchy-pkgs/
├── pkgbuilds/              # Source PKGBUILDs
├── build-output/           # Unsigned packages (temporary)
│   ├── x86_64/
│   └── aarch64/
├── pkgs.omarchy.org/       # Signed packages (production)
│   ├── x86_64/
│   └── aarch64/
├── build/                  # Build scripts (in container)
└── bin/                    # CLI tools (on host)
```

## Adding Packages

### From AUR

```bash
# Add to sync list
echo "package-name" >> build/packages/omarchy-aur.packages

# Sync PKGBUILD
bin/sync-aur package-name

# Build and release
bin/repo release --package package-name
```

#### Local Patches for AUR Packages

Create `pkgbuilds/package-name/patches/*.patch` to maintain modifications across AUR syncs:

```bash
cd pkgbuilds/package-name
# Make changes
git diff > patches/my-fix.patch
# Next sync will auto-apply patches
```

### Custom Package

```bash
mkdir pkgbuilds/my-package
# Add PKGBUILD and files
bin/repo release --package my-package
```

## Architecture-Specific Notes

### x86_64
- Native builds (fast)
- Mirrors: mirror.omarchy.org, rackspace, pkgbuild.com

### aarch64
- QEMU emulation required on x86_64 hosts (slower)
- Uses Arch Linux ARM repositories
- Additional repos: `[alarm]`, `[aur]`
- Same workflow, just add `--arch aarch64`

### Building for Both Architectures

```bash
# Build x86_64
bin/repo release --package myapp

# Build aarch64
bin/repo release --arch aarch64 --package myapp

# Sync both
bin/repo sync pkgs.omarchy.org/x86_64
bin/repo sync pkgs.omarchy.org/aarch64
```

## Dependency Resolution

The build system automatically handles inter-package dependencies:

1. Parses `depends=()` and `makedepends=()` from PKGBUILDs
2. Builds in correct order
3. Makes newly-built packages available via temporary `[omarchy-build]` repo

Example: If `aether` depends on `hyprshade`, `hyprshade` is built first.

## Version Management

Packages are only rebuilt if:
- PKGBUILD version is newer than repository version
- Package doesn't exist in production
