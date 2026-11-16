# Monarch systemd-stub

Build only the x86_64 EFI stub from systemd 262, with the partition-selection
patch from [systemd #43818](https://github.com/systemd/systemd/pull/43818), commit
`c578c1a66eff9a4c95642edfd2b7aca790b56e26`. Both downloads are SHA-256 pinned.

The upstream PR was closed without merging. This is a downstream patch, not
an upstream release feature. Recheck its applicability and the partition
selection tests whenever updating the source version.

The stub is installed at `/usr/lib/monarch/boot/linuxx64.efi.stub`, independently
of the files owned by systemd. A vendor Limine configuration selects this stub
through mkinitcpio's objcopy path (`--no-ukify --uefistub`): mkinitcpio otherwise
ignores `--uefistub` when ukify is installed. Administrator Limine configuration
can override the vendor defaults. Direct ukify callers must explicitly select
the stub themselves.

Package upgrades rebuild installed UKIs through Limine. Initial installation
leaves UKI generation to the installer, once the target root and ESP are ready.

The patch prefers the loaded partition when its GPT type matches the requested
type. It retains the first matching partition fallback, including ESP discovery
when loading from XBOOTLDR. It does not disable random-seed processing.
