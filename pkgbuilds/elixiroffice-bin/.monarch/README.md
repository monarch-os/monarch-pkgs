# ElixirOffice

Repackages the upstream Linux x86_64 Debian release with its bundled Electron
runtime, editor assets, fonts, dictionaries and third-party licence notices.
No FUSE dependency or document server is required. The Chromium sandbox stays
enabled; do not work around launch failures with `--no-sandbox`.

The packaging is maintained on the AUR:
<https://aur.archlinux.org/packages/elixiroffice-bin>.
Monarch syncs that recipe through the normal AUR package workflow.

Build from the repository root:

```bash
bin/repo build --package elixiroffice-bin
```

The installed command is `elixiroffice`. The upstream desktop entry advertises
supported Office and PDF formats without changing the user's default apps.

This is beta software: keep backups and check saved documents and exported PDFs.
Linux aarch64 binaries are not currently supplied upstream.

For updates, select a **desktop** release (server releases have separate versions),
update `pkgver` and the Debian asset's SHA-256 from that release's `SHA256SUMS`,
and reset `pkgrel` to 1. Verify the downloaded checksum before building. Publish
the updated PKGBUILD and regenerated `.SRCINFO` to the AUR, then sync it here with
`bin/sync-aur elixiroffice-bin`.

The corresponding AGPL source is published alongside each desktop release as
`elixiroffice-desktop-source.tar.gz`:
<https://github.com/leag1234/elixiroffice/releases/tag/v0.3.3>.
