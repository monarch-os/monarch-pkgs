#!/bin/bash

# The point of the hook is that it returns whether or not anyone is reading, so
# both cases are timed against fabricated FIFOs.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOOK="$ROOT/monarch-displaylink-sleep"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export MONARCH_DISPLAYLINK_FIFO_IN="$TMP/in" MONARCH_DISPLAYLINK_FIFO_OUT="$TMP/out"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"

  if [[ $actual != "$expected" ]]; then
    fail "$description" "Expected: $expected" "Actual:   $actual"
  fi

  pass "$description"
}

# Seconds the hook took, floored: the assertions only care that the wait is
# bounded well under systemd's 90s batch deadline.
timed() {
  local start=$SECONDS
  bash "$HOOK" "$@" || true
  echo $((SECONDS - start))
}

assert_equals "returns at once when there is no FIFO at all" "$(timed pre suspend)" "0"

mkfifo "$MONARCH_DISPLAYLINK_FIFO_IN" "$MONARCH_DISPLAYLINK_FIFO_OUT"

# The failure this exists to prevent: nobody reading, and the vendor hook would
# sit here until systemd killed the batch.
elapsed=$(timed pre suspend)
((elapsed <= 10)) || fail "gives up on an unread FIFO" "took ${elapsed}s"
pass "gives up on an unread FIFO in ${elapsed}s"

elapsed=$(timed post suspend)
((elapsed <= 5)) || fail "gives up on resume too" "took ${elapsed}s"
pass "gives up on resume too, in ${elapsed}s"

: >"$TMP/received"
(head -c 1 "$MONARCH_DISPLAYLINK_FIFO_IN" >"$TMP/received"; printf 'A' >"$MONARCH_DISPLAYLINK_FIFO_OUT") &
reader=$!
elapsed=$(timed pre suspend)
wait "$reader" 2>/dev/null || true
assert_equals "hands the suspend message to a listening driver" "$(<"$TMP/received")" "S"
((elapsed <= 5)) || fail "does not dawdle when the driver answers" "took ${elapsed}s"
pass "does not dawdle when the driver answers (${elapsed}s)"

: >"$TMP/received"
(head -c 1 "$MONARCH_DISPLAYLINK_FIFO_IN" >"$TMP/received") &
reader=$!
timed post suspend >/dev/null
wait "$reader" 2>/dev/null || true
assert_equals "hands the resume message over" "$(<"$TMP/received")" "R"

printf '\nAll DisplayLink sleep hook tests passed.\n'
