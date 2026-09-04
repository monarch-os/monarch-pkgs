#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

make_device() {
  local name=$1 vendor=$2 product=$3
  local device="$test_root/sys/devices/usb/$name/$name:1.0/usbmisc/$name"

  mkdir -p "$device" "$test_root/sys/class/usbmisc" "$test_root/dev/usb"
  printf '%s\n' "$vendor" >"$test_root/sys/devices/usb/$name/idVendor"
  printf '%s\n' "$product" >"$test_root/sys/devices/usb/$name/idProduct"
  ln -s "$device" "$test_root/sys/class/usbmisc/$name"
  install -m 0666 /dev/null "$test_root/dev/usb/$name"
}

make_device hiddev0 05ac 1114
make_device hiddev1 06c4 c411

cat >"$test_root/udevadm" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_UDEVADM_CALLS"
if [[ $1 == info ]]; then
  path=${3#--path=}
  printf 'usb/%s\n' "${path##*/}"
fi
STUB
chmod +x "$test_root/udevadm"

source "$root/asdcontrol.install"
ASDCONTROL_SYS_CLASS="$test_root/sys/class/usbmisc"
ASDCONTROL_SYS_DEVICES="$test_root/sys/devices"
ASDCONTROL_DEV_ROOT="$test_root/dev"
ASDCONTROL_UDEVADM="$test_root/udevadm"
ASDCONTROL_READLINK=/usr/bin/readlink
ASDCONTROL_CHMOD=/usr/bin/chmod
ASDCONTROL_SHA256SUM=/usr/bin/sha256sum
ASDCONTROL_RM=/usr/bin/rm
ASDCONTROL_FACTORY_RULE="$test_root/70-monarch-asdcontrol.rules"
TEST_UDEVADM_CALLS="$test_root/udevadm.calls"
export TEST_UDEVADM_CALLS

cp "$root/70-asdcontrol.rules" "$ASDCONTROL_FACTORY_RULE"
post_remove

[[ ! -e $ASDCONTROL_FACTORY_RULE ]]
[[ $(stat -c %a "$test_root/dev/usb/hiddev0") == 600 ]]
[[ $(stat -c %a "$test_root/dev/usb/hiddev1") == 666 ]]
grep -qF -- "--action=change --settle" "$TEST_UDEVADM_CALLS"

printf '%s\n' '# local policy' >"$ASDCONTROL_FACTORY_RULE"
chmod 0666 "$test_root/dev/usb/hiddev0"
post_remove
[[ $(<"$ASDCONTROL_FACTORY_RULE") == '# local policy' ]]
[[ $(stat -c %a "$test_root/dev/usb/hiddev0") == 600 ]]

cp "$root/70-asdcontrol.rules" "$ASDCONTROL_FACTORY_RULE"
post_upgrade
[[ ! -e $ASDCONTROL_FACTORY_RULE ]]

udevadm verify "$root/70-asdcontrol.rules"
echo "asdcontrol device access lifecycle checks pass"
