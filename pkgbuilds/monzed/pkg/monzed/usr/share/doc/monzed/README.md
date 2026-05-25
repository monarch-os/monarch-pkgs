# monzed

Live theme switching for **Zed** driven by **Monarch**.

Adapted from [omazed](https://github.com/APS6/omazed) (MIT, by APS) — same
generator math, repointed at Monarch's theme paths and hook system.

## What it does

1. Reads the current Monarch theme palette from `~/.config/monarch/current/theme/colors.toml`
   (falls back to `alacritty.toml` when needed).
2. Renders a full Zed theme JSON into `~/.config/zed/themes/monzed.json`.
3. Drops a hook into `~/.config/monarch/hooks/theme-set.d/monzed` so the
   theme regenerates on each `monarch theme set …`.

## Install (Arch / Monarch repo)

```sh
sudo pacman -S monzed
monzed setup
```

`monzed setup` installs the hook and runs the first sync. After that, switching
themes in Monarch automatically updates Zed.

## Commands

| Command | Description |
|---|---|
| `monzed setup` | Install the monarch hook + initial sync |
| `monzed sync`  | Regenerate the Zed theme from the current Monarch theme |
| `monzed set <name>` | Same, with the theme name passed by the monarch hook |

The Zed theme is named **Monzed**; on first run, monzed sets `"theme": "Monzed"`
in `~/.config/zed/settings.json`.

## Light vs dark

If the current Monarch theme directory contains a `light.mode` file, monzed
renders the Zed theme with `appearance: light` and a few targeted lightness
corrections; otherwise it renders dark.

## Files installed

```
/usr/bin/monzed
/usr/bin/monzed-generator.sh
/usr/share/monzed/monzed-theme.tpl
/usr/share/monzed/monzed-hook
```

Per user, after `monzed setup`:

```
~/.config/monarch/hooks/theme-set.d/monzed       (hook)
~/.config/zed/themes/monzed.json                 (generated theme)
~/.local/share/monzed/sync.log                   (log)
~/.local/share/monzed/initialized                (one-shot marker)
```

## License

MIT — see `LICENSE`. Original omazed copyright (APS) preserved.
