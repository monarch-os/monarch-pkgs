#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
config=${MONARCH_NVIM_TEST_CONFIG:-/etc/skel/.config/nvim}
data=${MONARCH_NVIM_TEST_DATA:-/etc/skel/.local/share/nvim}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/config" "$tmp/data"
cp -a "$config" "$tmp/config/nvim"
cp -a "$data" "$tmp/data/nvim"
cp "$ROOT/lua/plugins/base16.lua" "$tmp/config/nvim/lua/plugins/base16.lua"
export XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data"
export XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"

cat >"$tmp/config/nvim/lua/matugen.lua" <<'EOF'
return {
  setup = function()
    require("base16-colorscheme").setup({
      base00 = "#101112", base01 = "#202122", base02 = "#303132", base03 = "#404142",
      base04 = "#505152", base05 = "#abcdef", base06 = "#707172", base07 = "#808182",
      base08 = "#909192", base09 = "#a0a1a2", base0A = "#b0b1b2", base0B = "#c0c1c2",
      base0C = "#d0d1d2", base0D = "#e0e1e2", base0E = "#f0f1f2", base0F = "#010203",
    })
  end,
}
EOF

# Reapply LazyVim's choice so the result cannot depend on plugin load order.
timeout 30 nvim --headless \
  '+lua vim.defer_fn(function() require("lazyvim.config").colorscheme(); if vim.api.nvim_get_hl(0, {name="Normal"}).fg ~= 0xabcdef or not package.loaded["base16-colorscheme"] then vim.cmd("cquit 1") end; vim.cmd("qa!") end, 500)'

rm "$tmp/config/nvim/lua/matugen.lua"
timeout 30 nvim --headless \
  '+lua vim.defer_fn(function() if not tostring(vim.g.colors_name):match("^tokyonight") or package.loaded["base16-colorscheme"] then vim.cmd("cquit 1") end; vim.cmd("qa!") end, 500)'

echo "Noctalia theme selection and pre-generation fallback passed."
