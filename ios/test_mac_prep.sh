#!/usr/bin/env bash
# Selftest for ios/mac_prep.sh. Runs on Linux or macOS and touches only a
# throwaway temp directory. It does not build Xcode code or touch a device.
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PREP="$REPO/ios/mac_prep.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/pg-macprep-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*" >&2; }

expect_ok() {
  local desc=$1
  shift
  if "$@" >"$TMP/out" 2>&1; then
    pass "$desc"
  else
    cat "$TMP/out" >&2
    bad "$desc"
  fi
}

expect_status() {
  local desc=$1 want=$2
  shift 2
  set +e
  "$@" >"$TMP/out" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq "$want" ]; then
    pass "$desc (exit $rc)"
  else
    cat "$TMP/out" >&2
    bad "$desc: expected exit $want, got $rc"
  fi
}

expect_fail_with() {
  local desc=$1 pattern=$2
  shift 2
  set +e
  "$@" >"$TMP/out" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    bad "$desc: command unexpectedly succeeded"
  elif grep -q "$pattern" "$TMP/out"; then
    pass "$desc (exit $rc)"
  else
    cat "$TMP/out" >&2
    bad "$desc: output did not contain '$pattern'"
  fi
}

ROOT="$TMP/root"
APP="$TMP/PocketGlimmer.app"
mkdir -p "$ROOT/app/PocketGlimmer/Resources/Models" \
         "$ROOT/app/PocketGlimmer/Resources/Skills" \
         "$ROOT/app/PocketGlimmer/Support" "$ROOT/models" \
         "$APP/Models" "$APP/Frameworks/llama.framework"
cp "$REPO/app/project.yml" "$ROOT/app/project.yml"
cp "$REPO/app/PocketGlimmer/Resources/Models/calibration.json" "$ROOT/app/PocketGlimmer/Resources/Models/"
cp "$REPO/app/PocketGlimmer/Resources/Skills/builtin.json" "$ROOT/app/PocketGlimmer/Resources/Skills/"
cp "$REPO/app/PocketGlimmer/Support/PocketGlimmer.entitlements" "$ROOT/app/PocketGlimmer/Support/"

mkdir -p "$APP/Models" "$APP/Frameworks/llama.framework"
cp "$REPO/app/PocketGlimmer/Resources/Models/calibration.json" "$APP/Models/"
cp "$REPO/app/PocketGlimmer/Resources/Skills/builtin.json" "$APP/"
printf '#!/bin/sh\nexit 0\n' > "$APP/PocketGlimmer"
chmod +x "$APP/PocketGlimmer"
: > "$APP/Frameworks/llama.framework/llama"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PocketGlimmer</string>
<key>UIFileSharingEnabled</key><true/>
</dict></plist>
PLIST

bash -n "$PREP" && pass "mac_prep.sh syntax"
expect_ok "--help exits 0" "$PREP" --help
if grep -q 'build-unsigned' "$TMP/out"; then pass "--help lists build-unsigned"; else bad "--help is missing build-unsigned"; fi
expect_ok "real repo resources verify" "$PREP" verify-resources --root "$REPO"
if [ "$(uname -s)" != Darwin ]; then
  expect_fail_with "preflight refuses a non-macOS host" "macOS" "$PREP" preflight --root "$REPO"
  expect_fail_with "build-unsigned refuses a non-macOS host" "macOS" "$PREP" build-unsigned --root "$REPO"
else
  pass "macOS host: the non-macOS refusal tests do not apply"
fi
expect_status "compile-only resource check is incomplete" 2 "$PREP" verify-resources --root "$ROOT" --allow-no-model
expect_ok "check-app accepts a complete unsigned fixture" "$PREP" check-app --root "$ROOT" --app "$APP" --allow-no-model

BAD_APP="$TMP/Bad.app"
cp -R "$APP" "$BAD_APP"
sed -i.bak 's/"defaultTau" : 0.9,/"defaultTau" : 0.8,/' "$BAD_APP/Models/calibration.json"
rm -f "$BAD_APP/Models/calibration.json.bak"
expect_fail_with "check-app rejects tau 0.80" "0.90" "$PREP" check-app --root "$ROOT" --app "$BAD_APP" --allow-no-model

NO_CAL_APP="$TMP/NoCal.app"
cp -R "$APP" "$NO_CAL_APP"
rm -f "$NO_CAL_APP/Models/calibration.json"
expect_fail_with "check-app rejects a missing calibration" "no calibration.json" "$PREP" check-app --root "$ROOT" --app "$NO_CAL_APP" --allow-no-model

DEST="$ROOT/app/PocketGlimmer/Resources/Models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf"
head -c 2048 /dev/zero > "$ROOT/models/wrong.gguf"
expect_fail_with "bundle-model rejects a wrong file" "LFS pointer" "$PREP" bundle-model --root "$ROOT" --model "$ROOT/models/wrong.gguf"
if [ -e "$DEST" ]; then
  bad "bundle-model left a destination file after rejecting the source"
else
  pass "bundle-model does not create or overwrite a destination on failure"
fi

ln -s "$REPO/models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf" "$DEST"
expect_ok "bundle-model accepts an identical existing file" "$PREP" bundle-model --root "$ROOT" --model "$REPO/models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf"
rm -f "$DEST"
printf 'user file\n' > "$DEST"
expect_fail_with "bundle-model refuses to overwrite a different file" "refusing to overwrite" "$PREP" bundle-model --root "$ROOT" --model "$REPO/models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf"
if [ "$(cat "$DEST")" = "user file" ]; then
  pass "bundle-model leaves a different existing file untouched"
else
  bad "bundle-model changed a different existing file"
fi

LLAMA="$TMP/llama"
mkdir -p "$LLAMA"
git -C "$LLAMA" init -q
git -C "$LLAMA" config user.email selftest@example.invalid
git -C "$LLAMA" config user.name selftest
printf 'x\n' > "$LLAMA/x"
git -C "$LLAMA" add x
git -C "$LLAMA" commit -qm init
expect_fail_with "framework rejects a non-pinned llama.cpp checkout" "pinned to ddf48f8" "$PREP" framework --root "$ROOT" --llama-src "$LLAMA"

FWROOT="$TMP/fwroot"
FW="$FWROOT/app/Frameworks/llama.xcframework"
mkdir -p "$FWROOT/app" "$FW/ios-arm64/llama.framework/Headers" \
         "$FW/ios-arm64/llama.framework/Modules"
cp "$REPO/app/project.yml" "$FWROOT/app/project.yml"
: > "$FW/ios-arm64/llama.framework/llama"
cat > "$FW/ios-arm64/llama.framework/Headers/llama.h" <<'H'
struct llama_context_params { bool kv_unified; };
bool llama_memory_seq_cp(void);
H
: > "$FW/ios-arm64/llama.framework/Modules/module.modulemap"
cat > "$FW/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
expect_ok "framework verifies an existing device slice" "$PREP" framework --root "$FWROOT"

printf '\nSELFTEST: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
