#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/skel-config/lua/plugins" \
  "$TEST_ROOT/skel-data/lazy" "$TEST_ROOT/home"
printf '%s\n' pristine >"$TEST_ROOT/skel-config/init.lua"
printf '%s\n' cached >"$TEST_ROOT/skel-data/lazy/cache"

cat >"$TEST_ROOT/bin/xdg-mime" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/xdg-mime"

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export MONARCH_NVIM_SKEL_CONFIG_DIR="$TEST_ROOT/skel-config"
export MONARCH_NVIM_SKEL_DATA_DIR="$TEST_ROOT/skel-data"
export PATH="$TEST_ROOT/bin:/usr/bin"

bash "$ROOT/monarch-nvim-setup"
[[ $(<"$XDG_CONFIG_HOME/nvim/init.lua") == "pristine" ]]
[[ $(<"$XDG_DATA_HOME/nvim/lazy/cache") == "cached" ]]

printf '%s\n' customized >"$XDG_CONFIG_HOME/nvim/init.lua"
printf '%s\n' user-data >"$XDG_DATA_HOME/nvim/lazy/cache"
bash "$ROOT/monarch-nvim-setup"
[[ $(<"$XDG_CONFIG_HOME/nvim/init.lua") == "customized" ]]
[[ $(<"$XDG_DATA_HOME/nvim/lazy/cache") == "user-data" ]]

mkdir -p "$XDG_CACHE_HOME/nvim" "$XDG_STATE_HOME/nvim"
touch "$XDG_CACHE_HOME/nvim/stale" "$XDG_STATE_HOME/nvim/stale"
bash "$ROOT/monarch-nvim-setup" --refresh
[[ $(<"$XDG_CONFIG_HOME/nvim/init.lua") == "pristine" ]]
[[ $(<"$XDG_DATA_HOME/nvim/lazy/cache") == "cached" ]]
[[ ! -e $XDG_CACHE_HOME/nvim && ! -e $XDG_STATE_HOME/nvim ]]
compgen -G "$XDG_CONFIG_HOME/nvim.backup.*" >/dev/null

echo "All monarch-nvim tests passed."
