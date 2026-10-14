#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
cleanup() {
  gpgconf --homedir "$tmp/gnupg" --kill gpg-agent >/dev/null 2>&1 || true
  rm -rf -- "$tmp"
}
trap cleanup EXIT
export GNUPGHOME="$tmp/gnupg"
unset GPG_PRIVATE_KEY
mkdir -m 0700 "$GNUPGHOME"
fixture="$tmp/repo"
mkdir -p "$fixture/bin" "$fixture/helpers" "$fixture/build-output/x86_64" \
  "$fixture/pkgs.monarchlinux.com/x86_64"
cp "$ROOT/bin/promote-build" "$fixture/bin/"
cp "$ROOT/helpers/"{paths,message-helpers}.sh "$fixture/helpers/"
build="$fixture/build-output/x86_64"
published="$fixture/pkgs.monarchlinux.com/x86_64"
package=monarch-settings-1.0.0.r39.g8833f38-1-any.pkg.tar.zst

printf 'package payload\n' >"$published/$package"
printf 'published signature\n' >"$published/$package.sig"
cp "$published/$package" "$build/$package"
cp "$published/$package.sig" "$build/$package.sig"

status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
cat "$tmp/output"
if ((status != 0)); then
  echo "FAIL: replaying an already published identical package must succeed" >&2
  exit 1
fi
[[ $(<"$published/$package") == 'package payload' ]]
[[ $(<"$published/$package.sig") == 'published signature' ]]
[[ ! -e $build/$package && ! -e $build/$package.sig ]]
echo "PASS: identical publication replay preserves production and clears staged duplicates"

cp "$published/$package" "$build/$package"
printf 'new signature for the same bytes\n' >"$build/$package.sig"
other=example-2.0-1-any.pkg.tar.zst
printf 'new package\n' >"$build/$other"
printf 'new signature\n' >"$build/$other.sig"
before=$(stat -c '%i:%Y' "$published/$package")
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
[[ $(stat -c '%i:%Y' "$published/$package") == "$before" ]]
[[ $(<"$published/$package.sig") == 'published signature' ]]
[[ $(<"$published/$other") == 'new package' ]]
[[ $(<"$published/$other.sig") == 'new signature' ]]
[[ ! -e $build/$package && ! -e $build/$other ]]
echo "PASS: resigning identical bytes preserves the published signature and does not block new packages"

printf 'different package payload\n' >"$build/$package"
printf 'replacement signature\n' >"$build/$package.sig"
next=next-1.0-1-any.pkg.tar.zst
printf 'next package\n' >"$build/$next"
printf 'next signature\n' >"$build/$next.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ $(<"$published/$package") == 'package payload' ]]
[[ $(<"$published/$package.sig") == 'published signature' ]]
[[ ! -e $published/$next && ! -e $published/$next.sig ]]
[[ -f $build/$package && -f $build/$next ]]
echo "PASS: differing bytes under an existing name stop the entire batch without overwriting production"

cp "$published/$package" "$build/$package"
rm "$build/$package.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$package && -f $build/$next ]]
[[ ! -e $published/$next ]]
echo "PASS: duplicates cannot bypass the staged-signature requirement"

printf 'staged signature\n' >"$build/$package.sig"
bash "$fixture/bin/promote-build" --dry-run >"$tmp/output" 2>&1
[[ -f $build/$package && -f $build/$package.sig && -f $build/$next ]]
[[ ! -e $published/$next ]]
echo "PASS: dry runs do not move or remove staged files"

rm "$published/$package.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$package && ! -e $published/$next ]]
echo "PASS: an unsigned production artifact is not accepted as an already published pair"

printf 'published signature\n' >"$published/$package.sig"
printf 'orphaned signature\n' >"$published/$next.sig"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ $(<"$published/$next.sig") == 'orphaned signature' ]]
[[ ! -e $published/$next && -f $build/$next && -f $build/$package ]]
echo "PASS: a pre-existing orphaned signature cannot be overwritten"

rm "$published/$next.sig"
(
  exec {lock}<"$build"
  flock -n "$lock"
  status=0
  bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
  ((status != 0))
  [[ -f $build/$package && -f $build/$next && ! -e $published/$next ]]
)
echo "PASS: overlapping local promotions fail before mutating the batch"

bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
[[ $(<"$published/$next") == 'next package' ]]
echo "PASS: a completed batch and its empty retry both succeed"

gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Promotion regression <promotion@example.invalid>' ed25519 sign 0 \
  >"$tmp/gpg-output" 2>&1
recovery=recovery-1.0-1-any.pkg.tar.zst
printf 'recovery package\n' >"$build/$recovery"
gpg --batch --yes --pinentry-mode loopback --passphrase '' \
  --detach-sign --output "$build/$recovery.sig" "$build/$recovery"
cp "$build/$recovery.sig" "$tmp/expected.sig"
mkdir "$tmp/tools"
cat >"$tmp/tools/mv" <<'STUB'
#!/bin/bash
if [[ ${FAIL_SIGNATURE_MOVE:-0} == 1 && ${!#} == *.sig ]]; then
  exit 73
fi
exec /usr/bin/mv "$@"
STUB
chmod +x "$tmp/tools/mv"
status=0
PATH="$tmp/tools:$PATH" FAIL_SIGNATURE_MOVE=1 bash "$fixture/bin/promote-build" \
  >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $published/$recovery && ! -e $published/$recovery.sig ]]
[[ ! -e $build/$recovery && -f $build/$recovery.sig ]]
before=$(stat -c '%i:%Y' "$published/$recovery")
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
if [[ ! -f $published/$recovery.sig || -e $build/$recovery.sig ]]; then
  cat "$tmp/output"
  echo "FAIL: interrupted archive/signature moves must complete on a signature-only retry" >&2
  exit 1
fi
[[ $(stat -c '%i:%Y' "$published/$recovery") == "$before" ]]
cmp -- "$published/$recovery.sig" "$tmp/expected.sig"
gpg --batch --verify "$published/$recovery.sig" "$published/$recovery" >"$tmp/gpg-output" 2>&1
echo "PASS: a failed signature move is recovered cryptographically without replacing the published archive"

rm "$published/$recovery.sig"
cp "$published/$recovery" "$build/$recovery"
cp "$tmp/expected.sig" "$build/$recovery.sig"
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
[[ $(stat -c '%i:%Y' "$published/$recovery") == "$before" ]]
[[ ! -e $build/$recovery && ! -e $build/$recovery.sig ]]
cmp -- "$published/$recovery.sig" "$tmp/expected.sig"
echo "PASS: an identical staged archive can repair its missing published signature"

rm "$published/$recovery.sig"
printf 'different signed payload\n' >"$tmp/wrong-payload"
gpg --batch --yes --pinentry-mode loopback --passphrase '' \
  --detach-sign --output "$build/$recovery.sig" "$tmp/wrong-payload"
status=0
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$recovery.sig && ! -e $published/$recovery.sig ]]
[[ $(stat -c '%i:%Y' "$published/$recovery") == "$before" ]]
echo "PASS: a signature for different archive bytes cannot repair production"

cp "$tmp/expected.sig" "$build/$recovery.sig"
mkdir -m 0700 "$tmp/empty-keyring"
status=0
GNUPGHOME="$tmp/empty-keyring" bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$recovery.sig && ! -e $published/$recovery.sig ]]
echo "PASS: recovery without the signing public key fails before publication"

bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
signature_before=$(stat -c '%i:%Y' "$published/$recovery.sig")
cp "$tmp/expected.sig" "$build/$recovery.sig"
bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1
[[ $(stat -c '%i:%Y' "$published/$recovery.sig") == "$signature_before" ]]
[[ ! -e $build/$recovery.sig ]]
echo "PASS: a signature-only replay preserves an already completed published pair"

workflow_key=$(gpg --batch --armor --export-secret-keys)
mkdir "$tmp/verification-tmp"
rm "$published/$recovery.sig"
cp "$tmp/expected.sig" "$build/$recovery.sig"
if ! TMPDIR="$tmp/verification-tmp" GNUPGHOME="$tmp/empty-keyring" GPG_PRIVATE_KEY="$workflow_key" \
  bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1; then
  cat "$tmp/output"
  echo "FAIL: workflow signing key must support recovery without a host public key" >&2
  exit 1
fi
[[ $(stat -c '%i:%Y' "$published/$recovery") == "$before" ]]
cmp -- "$published/$recovery.sig" "$tmp/expected.sig"
[[ ! -e $build/$recovery.sig ]]
[[ -z $(find "$tmp/verification-tmp" -mindepth 1 -print -quit) ]]
[[ -z $(GNUPGHOME="$tmp/empty-keyring" gpg --batch --with-colons --list-keys 2>/dev/null | grep '^pub:' || true) ]]
[[ -z $(GNUPGHOME="$tmp/empty-keyring" gpg --batch --with-colons --list-secret-keys 2>/dev/null | grep '^sec:' || true) ]]
echo "PASS: workflow-key recovery leaves the host public and private keyrings untouched"

rm "$published/$recovery.sig"
cp "$tmp/expected.sig" "$build/$recovery.sig"
status=0
TMPDIR="$tmp/verification-tmp" GNUPGHOME="$tmp/empty-keyring" GPG_PRIVATE_KEY='invalid key' \
  bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$recovery.sig && ! -e $published/$recovery.sig ]]
[[ -z $(find "$tmp/verification-tmp" -mindepth 1 -print -quit) ]]
echo "PASS: invalid workflow keys fail before publication and preserve the staged signature"

gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Other signing key <other@example.invalid>' ed25519 sign 0 \
  >"$tmp/gpg-output" 2>&1
other_key=$(gpg --batch --armor --export 'other@example.invalid')
status=0
TMPDIR="$tmp/verification-tmp" GPG_PRIVATE_KEY="$other_key" \
  bash "$fixture/bin/promote-build" >"$tmp/output" 2>&1 || status=$?
((status != 0))
[[ -f $build/$recovery.sig && ! -e $published/$recovery.sig ]]
[[ -z $(find "$tmp/verification-tmp" -mindepth 1 -print -quit) ]]
echo "PASS: a different workflow key cannot fall back to the host signing key"
