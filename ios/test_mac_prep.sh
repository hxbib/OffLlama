#!/usr/bin/env bash
# Selftest for ios/mac_prep.sh. Runs on Linux or macOS and touches only a
# throwaway temp directory. It does not build Xcode code or touch a device.
# The macOS-specific cases below use fake uname/file/lipo/otool/nm/xcodebuild
# to prove shell control flow only; they are not Xcode or framework proof.
set -euo pipefail

REPO=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PREP="$REPO/ios/mac_prep.sh"
# shellcheck source=ios/artifacts.env
. "$REPO/ios/artifacts.env"
MODEL="$REPO/$SHIPPING_MODEL_REL"
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

expect_status_with() {
  local desc=$1 want=$2 pattern=$3
  shift 3
  set +e
  "$@" >"$TMP/out" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -ne "$want" ]; then
    cat "$TMP/out" >&2
    bad "$desc: expected exit $want, got $rc"
  elif ! grep -q "$pattern" "$TMP/out"; then
    cat "$TMP/out" >&2
    bad "$desc: output did not contain '$pattern'"
  else
    pass "$desc (exit $rc)"
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

# A tiny valid-enough Mach-O (or a real host dylib on macOS) for structural checks.
make_macho() {
  local path=$1 cpu=${2:-arm64} src
  mkdir -p "$(dirname "$path")"
  if [ -f "$TMP/macho-$cpu" ]; then
    cp "$TMP/macho-$cpu" "$path"
    return 0
  fi
  if [ "$(uname -s)" = Darwin ] && command -v clang >/dev/null 2>&1; then
    src="$TMP/macho-src.c"
    printf 'void llama_model_load_from_file(void) {}\nvoid llama_memory_seq_cp(void) {}\n' > "$src"
    if clang -dynamiclib -arch "$cpu" -install_name '@rpath/llama.framework/llama' \
        -o "$TMP/macho-$cpu.raw" "$src" 2>/dev/null; then
      if command -v vtool >/dev/null 2>&1 &&
          vtool -set-build-version ios 18.0 18.0 -replace \
            -output "$TMP/macho-$cpu" "$TMP/macho-$cpu.raw" 2>/dev/null; then
        cp "$TMP/macho-$cpu" "$path"
        return 0
      fi
      if command -v xcrun >/dev/null 2>&1 &&
          xcrun -f vtool >/dev/null 2>&1 &&
          xcrun vtool -set-build-version ios 18.0 18.0 -replace \
            -output "$TMP/macho-$cpu" "$TMP/macho-$cpu.raw" 2>/dev/null; then
        cp "$TMP/macho-$cpu" "$path"
        return 0
      fi
      cp "$TMP/macho-$cpu.raw" "$TMP/macho-$cpu"
      cp "$TMP/macho-$cpu" "$path"
      return 0
    fi
  fi
  python3 - "$TMP/macho-$cpu" "$cpu" <<'PY'
import struct, sys
path, cpu = sys.argv[1], sys.argv[2]
cputype = 0x0100000C if cpu == "arm64" else 0x01000007
with open(path, "wb") as fh:
    fh.write(struct.pack("<IIIIIIII", 0xFEEDFACF, cputype, 0, 6, 0, 0, 0, 0))
PY
  cp "$TMP/macho-$cpu" "$path"
}

# arm64 Mach-O header fixture; this suite mocks file(1).
make_app_executable() {
  local path=$1
  mkdir -p "$(dirname "$path")"
  python3 - "$path" <<'PY'
import os, struct, sys
path = sys.argv[1]
with open(path, "wb") as fh:
    fh.write(struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 0, 0, 0, 0))
os.chmod(path, 0o755)
PY
}

# Build a realistic source xcframework fixture (without a provenance marker).
make_xcframework() {
  local fw=$1 cpu=${2:-arm64} slice h
  slice="$fw/ios-arm64/llama.framework"
  mkdir -p "$slice/Headers" "$slice/Modules"
  cat > "$fw/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>AvailableLibraries</key><array><dict>
<key>LibraryIdentifier</key><string>ios-arm64</string>
<key>LibraryPath</key><string>llama.framework</string>
<key>SupportedArchitectures</key><array><string>arm64</string></array>
<key>SupportedPlatform</key><string>ios</string>
</dict></array>
<key>CFBundlePackageType</key><string>XFWK</string>
</dict></plist>
PLIST
  cat > "$slice/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>llama</string>
<key>CFBundleIdentifier</key><string>org.ggml.llama</string>
<key>CFBundleName</key><string>llama</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
  make_macho "$slice/llama" "$cpu"
  for h in llama.h ggml.h ggml-opt.h ggml-alloc.h ggml-backend.h ggml-metal.h \
           ggml-cpu.h ggml-blas.h gguf.h mtmd.h mtmd-helper.h; do
    printf '/* pinned %s */\n' "$h" > "$slice/Headers/$h"
  done
  cat > "$slice/Headers/llama.h" <<'H'
struct llama_context_params { bool kv_unified; };
bool llama_memory_seq_cp(void);
H
  cat > "$slice/Modules/module.modulemap" <<'M'
framework module llama {
    umbrella "Headers"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
M
  make_provenance "$fw"
}

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi
}

make_provenance() {
  local fw=$1 hash srchash
  hash=$(hash_of "$fw/ios-arm64/llama.framework/llama")
  srchash=$(python3 "$REPO/ios/validate_artifacts.py" framework-digest "$fw")
  printf '{\n  "commit": "%s",\n  "clean": true,\n  "device_binary_sha256": "%s",\n  "headers_sha256": "%s"\n}\n' \
    "$LLAMA_COMMIT" "$hash" "$srchash" > "$fw/.pocketglimmer-provenance.json"
}

make_app() {
  local app=$1
  mkdir -p "$app/Models" "$app/Frameworks/llama.framework"
  cp "$REPO/app/PocketGlimmer/Resources/Models/calibration.json" "$app/Models/"
  cp "$REPO/app/PocketGlimmer/Resources/Skills/builtin.json" "$app/"
  make_app_executable "$app/PocketGlimmer"
  make_macho "$app/Frameworks/llama.framework/llama"
  cat > "$app/Frameworks/llama.framework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>llama</string>
<key>CFBundleIdentifier</key><string>org.ggml.llama</string>
<key>CFBundleName</key><string>llama</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
  cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PocketGlimmer</string>
<key>UIFileSharingEnabled</key><true/>
</dict></plist>
PLIST
}

make_root() {
  local root=$1
  mkdir -p "$root/app/PocketGlimmer/Resources/Models" \
           "$root/app/PocketGlimmer/Resources/Skills" \
           "$root/app/PocketGlimmer/Support" "$root/models"
  cp "$REPO/app/project.yml" "$root/app/project.yml"
  cp "$REPO/app/PocketGlimmer/Resources/Models/calibration.json" "$root/app/PocketGlimmer/Resources/Models/"
  cp "$REPO/app/PocketGlimmer/Resources/Skills/builtin.json" "$root/app/PocketGlimmer/Resources/Skills/"
  cp "$REPO/app/PocketGlimmer/Support/PocketGlimmer.entitlements" "$root/app/PocketGlimmer/Support/"
}

mutate_cal() {
  local app=$1 code=$2
  cp -R "$BASE_APP" "$app"
  python3 - "$app/Models/calibration.json" "$code" <<'PY'
import json, sys
path, code = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
exec(code, {"d": data})
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY
}

# --- fixtures -----------------------------------------------------------------

ROOT="$TMP/root"
make_root "$ROOT"
BASE_APP="$TMP/Base.app"
make_app "$BASE_APP"
BASE_APP_MODEL="$TMP/BaseWithModel.app"
cp -R "$BASE_APP" "$BASE_APP_MODEL"
if ! ln "$MODEL" "$BASE_APP_MODEL/shipped.gguf" 2>/dev/null; then
  cp "$MODEL" "$BASE_APP_MODEL/shipped.gguf"
fi
make_xcframework "$TMP/fw-template"

MOCKBIN="$TMP/mockbin"
mkdir -p "$MOCKBIN"
cat > "$MOCKBIN/uname" <<'SH'
#!/bin/sh
case "${1:-}" in
  -s|"") printf 'Darwin\n' ;;
  *) exec /usr/bin/uname "$@" ;;
esac
SH
cat > "$MOCKBIN/file" <<'SH'
#!/bin/sh
path=${2:-}
case "${path##*/}" in
  llama) printf 'Mach-O 64-bit dynamically linked shared library arm64\n' ;;
  *) printf '%s\n' "${FAKE_APP_FILE_OUTPUT:-Mach-O 64-bit executable arm64}" ;;
esac
SH
cat > "$MOCKBIN/lipo" <<'SH'
#!/bin/sh
printf 'Non-fat file: %s is architecture: arm64\n' "$2"
SH
cat > "$MOCKBIN/otool" <<'SH'
#!/bin/sh
printf '@rpath/llama.framework/llama\n'
SH
cat > "$MOCKBIN/vtool" <<'SH'
#!/bin/sh
printf 'platform %s\n' "${FAKE_VTOOL_PLATFORM:-IOS}"
SH
cat > "$MOCKBIN/nm" <<'SH'
#!/bin/sh
printf '0000000000000000 T _llama_model_load_from_file\n'
SH
cat > "$MOCKBIN/cmake" <<'SH'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then printf 'cmake version 3.28.1\n'; fi
SH
cat > "$MOCKBIN/xcodegen" <<'SH'
#!/bin/sh
mkdir -p PocketGlimmer.xcodeproj
SH
cat > "$MOCKBIN/git" <<'SH'
#!/bin/sh
if [ "${1:-}" = "-C" ]; then shift 2; fi
case "${1:-} ${2:-}" in
  "rev-parse HEAD") printf '%s\n' "${FAKE_GIT_SHA:-}" ;;
  "status --porcelain")
    if [ -n "${FAKE_GIT_STATUS:-}" ]; then printf '%s\n' "$FAKE_GIT_STATUS"; fi
    ;;
  *) exit 0 ;;
esac
SH
cat > "$MOCKBIN/xcodebuild" <<'SH'
#!/bin/sh
dd=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -derivedDataPath) dd=$2; shift ;;
  esac
  shift
done
if [ -n "${FAKE_XCODEBUILD_RC:-}" ]; then exit "$FAKE_XCODEBUILD_RC"; fi
if [ "${FAKE_XCODEBUILD_NO_APP:-}" = 1 ]; then exit 0; fi
if [ -n "${FAKE_APP_TEMPLATE:-}" ]; then
  app="$dd/Build/Products/Release-iphoneos/PocketGlimmer.app"
  mkdir -p "$(dirname "$app")"
  cp -R "$FAKE_APP_TEMPLATE" "$app"
fi
if [ -n "${FAKE_APP_MODEL_PATH:-}" ]; then
  app="$dd/Build/Products/Release-iphoneos/PocketGlimmer.app"
  if ! ln "$FAKE_APP_MODEL_PATH" "$app/shipped.gguf" 2>/dev/null; then
    cp "$FAKE_APP_MODEL_PATH" "$app/shipped.gguf"
  fi
fi
exit 0
SH
chmod +x "$MOCKBIN"/*

# --- baseline ----------------------------------------------------------------

bash -n "$PREP" && pass "mac_prep.sh syntax"
python3 -m py_compile "$REPO/ios/validate_artifacts.py" && pass "validator syntax"
expect_ok "--help exits 0" "$PREP" --help
if grep -q 'build-unsigned' "$TMP/out"; then pass "--help lists build-unsigned"; else bad "--help is missing build-unsigned"; fi
if grep -q -- '--no-generate' "$TMP/out"; then bad "--help still advertises unsafe --no-generate"; else pass "--help has no --no-generate"; fi
expect_ok "real repo resources verify" "$PREP" verify-resources --root "$REPO"
if [ "$(uname -s)" != Darwin ]; then
  expect_fail_with "preflight refuses a non-macOS host" "macOS" "$PREP" preflight --root "$REPO"
  expect_fail_with "build-unsigned refuses a non-macOS host" "macOS" "$PREP" build-unsigned --root "$REPO"
else
  pass "macOS host: the non-macOS refusal tests do not apply"
fi
expect_status "compile-only resource check is incomplete" 2 "$PREP" verify-resources --root "$ROOT" --allow-no-model
BADROOT="$TMP/badroot"
cp -R "$ROOT" "$BADROOT"
python3 - "$BADROOT/app/PocketGlimmer/Resources/Models/calibration.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    data = json.load(fh)
data["defaultTau"] = "0.9"
with open(p, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY
expect_fail_with "verify-resources rejects a schema-invalid source calibration" "finite JSON number" \
  "$PREP" verify-resources --root "$BADROOT" --allow-no-model
expect_status_with "check-app reports a model-less app incomplete by default" 2 "must bundle the verified model" \
  "$PREP" check-app --root "$ROOT" --app "$BASE_APP"
expect_status_with "check-app --allow-no-model is compile-only and incomplete" 2 "compile-only request" \
  "$PREP" check-app --root "$ROOT" --app "$BASE_APP" --allow-no-model
expect_fail_with "check-app --require-model fails a model-less app" "no .gguf in the built app" \
  "$PREP" check-app --root "$ROOT" --app "$BASE_APP" --require-model
expect_ok "check-app accepts a complete model-bearing unsigned fixture" \
  "$PREP" check-app --root "$ROOT" --app "$BASE_APP_MODEL" --require-model

cp -R "$BASE_APP" "$TMP/empty-exe.app"
: > "$TMP/empty-exe.app/PocketGlimmer"
expect_fail_with "check-app rejects a zero-byte executable" "executable is empty" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/empty-exe.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/non-macho-exe.app"
printf '#!/bin/sh\nexit 0\n' > "$TMP/non-macho-exe.app/PocketGlimmer"
chmod +x "$TMP/non-macho-exe.app/PocketGlimmer"
expect_fail_with "check-app on macOS rejects a non-Mach-O executable" "Mach-O arm64 executable" \
  env PATH="$MOCKBIN:$PATH" FAKE_APP_FILE_OUTPUT='ASCII text executable' \
  "$PREP" check-app --root "$ROOT" --app "$TMP/non-macho-exe.app" --allow-no-model

ln -s "$MODEL" "$ROOT/app/PocketGlimmer/Resources/Models/source-symlink.gguf"
expect_fail_with "verify-resources rejects a symlinked source model" "symlink" \
  "$PREP" verify-resources --root "$ROOT" --allow-no-model
rm -f "$ROOT/app/PocketGlimmer/Resources/Models/source-symlink.gguf"

mkdir -p "$ROOT/app/PocketGlimmer/Resources/Models/backup"
cp "$REPO/app/PocketGlimmer/Resources/Models/calibration.json" \
  "$ROOT/app/PocketGlimmer/Resources/Models/backup/calibration.json"
expect_fail_with "verify-resources rejects a duplicate source calibration" "duplicate source calibration.json" \
  "$PREP" verify-resources --root "$ROOT" --allow-no-model
rm -rf "$ROOT/app/PocketGlimmer/Resources/Models/backup"

# --- calibration schema and identity -----------------------------------------

mutate_cal "$TMP/c-string-tau.app" 'd["defaultTau"] = "0.9"'
expect_fail_with "check-app rejects string defaultTau" "finite JSON number" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-string-tau.app" --allow-no-model

mutate_cal "$TMP/c-style.app" 'd["promptStyle"] = "fewshot"'
expect_fail_with "check-app rejects an invalid promptStyle" "fewShot" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-style.app" --allow-no-model

mutate_cal "$TMP/c-prior-type.app" 'd["prior"]["route"][0] = "not-a-number"'
expect_fail_with "check-app rejects non-numeric prior values" "finite JSON number" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-prior-type.app" --allow-no-model

mutate_cal "$TMP/c-missing-prior.app" 'del d["prior"]["route"]'
expect_fail_with "check-app rejects a missing prior set" "missing prior set" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-missing-prior.app" --allow-no-model

mutate_cal "$TMP/c-short-prior.app" 'd["prior"]["eventPick#5"] = d["prior"]["eventPick#5"][:-1]'
expect_fail_with "check-app rejects a wrong prior length" "expected 5" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-short-prior.app" --allow-no-model

mutate_cal "$TMP/c-prior-object.app" 'd["prior"] = []'
expect_fail_with "check-app rejects a non-object prior" "prior must be a JSON object" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-prior-object.app" --allow-no-model

mutate_cal "$TMP/c-temperature.app" 'd["temperature"]["route"] = 0.8'
expect_fail_with "check-app rejects a temperature other than 1" "every value must be 1.0" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-temperature.app" --allow-no-model

mutate_cal "$TMP/c-tau.app" 'd["tau"]["route"] = 0.8'
expect_fail_with "check-app rejects per-type tau other than 0.90" "every value must be 0.9" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-tau.app" --allow-no-model

mutate_cal "$TMP/c-extra-prior.app" 'd["prior"]["bogus"] = [1.0]'
expect_fail_with "check-app rejects an unknown prior set" "unexpected prior set" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-extra-prior.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/c-duplicate-key.app"
python3 - "$TMP/c-duplicate-key.app/Models/calibration.json" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = '"defaultTau" : 0.9,'
assert needle in s
open(p, "w", encoding="utf-8").write(s.replace(needle, needle + '\n  "defaultTau" : 0.9,', 1))
PY
expect_fail_with "check-app rejects a duplicate JSON key" "duplicate JSON key" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-duplicate-key.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/c-nan.app"
sed -i.bak 's/"defaultTau" : 0.9,/"defaultTau" : NaN,/' "$TMP/c-nan.app/Models/calibration.json"
rm -f "$TMP/c-nan.app/Models/calibration.json.bak"
expect_fail_with "check-app rejects a non-finite JSON value" "non-finite" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-nan.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/c-reformatted.app"
python3 - "$TMP/c-reformatted.app/Models/calibration.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p, encoding="utf-8"))
json.dump(data, open(p, "w", encoding="utf-8"), indent=4)
PY
expect_fail_with "check-app rejects a byte-different calibration" "must stay byte-identical" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/c-reformatted.app" --allow-no-model

# --- bundle lookup order and duplicates --------------------------------------

cp -R "$BASE_APP" "$TMP/lookup-conflict.app"
cp "$BASE_APP/Models/calibration.json" "$TMP/lookup-conflict.app/calibration.json"
python3 - "$TMP/lookup-conflict.app/calibration.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p, encoding="utf-8"))
data["defaultTau"] = 0.8
json.dump(data, open(p, "w"), indent=2)
PY
expect_fail_with "check-app rejects conflicting root/Models calibration copies" "conflicting duplicate" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/lookup-conflict.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/lookup-nested.app"
mkdir -p "$TMP/lookup-nested.app/Resources/Models"
mv "$TMP/lookup-nested.app/Models/calibration.json" "$TMP/lookup-nested.app/Resources/Models/"
expect_fail_with "check-app rejects calibration only at an unsupported path" "unsupported path" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/lookup-nested.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/lookup-nested-skills.app"
mkdir -p "$TMP/lookup-nested-skills.app/Resources/Skills"
mv "$TMP/lookup-nested-skills.app/builtin.json" "$TMP/lookup-nested-skills.app/Resources/Skills/"
expect_fail_with "check-app rejects skills only at an unsupported path" "unsupported path" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/lookup-nested-skills.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/lookup-nested-model.app"
mkdir -p "$TMP/lookup-nested-model.app/Resources/Models"
head -c 16 /dev/zero > "$TMP/lookup-nested-model.app/Resources/Models/nested.gguf"
expect_fail_with "check-app rejects a model only at an unsupported path" "unusable nested copy" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/lookup-nested-model.app" --require-model

cp -R "$BASE_APP" "$TMP/lookup-model-symlink.app"
ln -s "$MODEL" "$TMP/lookup-model-symlink.app/Models/embedded.gguf"
expect_fail_with "check-app rejects a bundled model symlink" "symlink" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/lookup-model-symlink.app" --require-model

cp -R "$BASE_APP" "$TMP/embedded-empty.app"
: > "$TMP/embedded-empty.app/Frameworks/llama.framework/llama"
expect_fail_with "check-app rejects an empty embedded framework binary" "empty" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/embedded-empty.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/embedded-fw-symlink.app"
mv "$TMP/embedded-fw-symlink.app/Frameworks/llama.framework" "$TMP/external-embedded-fw"
ln -s "$TMP/external-embedded-fw" "$TMP/embedded-fw-symlink.app/Frameworks/llama.framework"
expect_fail_with "check-app rejects a symlinked embedded llama.framework directory" "symlink" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/embedded-fw-symlink.app" --allow-no-model

cp -R "$BASE_APP" "$TMP/embedded-frameworks-symlink.app"
mv "$TMP/embedded-frameworks-symlink.app/Frameworks" "$TMP/external-frameworks"
ln -s "$TMP/external-frameworks" "$TMP/embedded-frameworks-symlink.app/Frameworks"
expect_fail_with "check-app rejects a symlinked Frameworks directory" "Frameworks directory is a symlink" \
  "$PREP" check-app --root "$ROOT" --app "$TMP/embedded-frameworks-symlink.app" --allow-no-model

# --- model bundling ----------------------------------------------------------

DEST="$ROOT/app/PocketGlimmer/Resources/Models/$(basename "$SHIPPING_MODEL_REL")"
head -c 2048 /dev/zero > "$ROOT/models/wrong.gguf"
expect_fail_with "bundle-model rejects a wrong file" "LFS pointer" "$PREP" bundle-model --root "$ROOT" --model "$ROOT/models/wrong.gguf"
if [ -e "$DEST" ]; then
  bad "bundle-model left a destination file after rejecting the source"
else
  pass "bundle-model does not create or overwrite a destination on failure"
fi

ln -s "$MODEL" "$DEST"
expect_fail_with "bundle-model rejects a symlinked destination" "symlink" "$PREP" bundle-model --root "$ROOT" --model "$MODEL"
rm -f "$DEST"

DANGLING_TARGET="$TMP/outside-model.gguf"
ln -s "$DANGLING_TARGET" "$DEST"
expect_fail_with "bundle-model rejects a dangling destination symlink" "symlink" "$PREP" bundle-model --root "$ROOT" --model "$MODEL"
if [ -e "$DANGLING_TARGET" ]; then
  bad "bundle-model wrote through a dangling symlink"
else
  pass "bundle-model never writes through a dangling symlink"
fi
rm -f "$DEST"

printf 'user file\n' > "$DEST"
expect_fail_with "bundle-model refuses to overwrite a different file" "refusing to overwrite" "$PREP" bundle-model --root "$ROOT" --model "$MODEL"
if [ "$(cat "$DEST")" = "user file" ]; then
  pass "bundle-model leaves a different existing file untouched"
else
  bad "bundle-model changed a different existing file"
fi
rm -f "$DEST"

SYMROOT="$TMP/symroot"
make_root "$SYMROOT"
rm -rf "$SYMROOT/app/PocketGlimmer/Resources/Models"
mkdir -p "$TMP/outside-models"
ln -s "$TMP/outside-models" "$SYMROOT/app/PocketGlimmer/Resources/Models"
expect_fail_with "bundle-model rejects a symlinked model directory" "symlinked model directory" \
  "$PREP" bundle-model --root "$SYMROOT" --model "$MODEL"
if [ -z "$(find "$TMP/outside-models" -type f 2>/dev/null)" ]; then
  pass "bundle-model never writes through a symlinked destination directory"
else
  bad "bundle-model wrote outside the repo through a directory symlink"
fi

# --- framework ---------------------------------------------------------------

FWROOT="$TMP/fwroot"
make_root "$FWROOT"
mkdir -p "$FWROOT/app/Frameworks"
cp -R "$TMP/fw-template" "$FWROOT/app/Frameworks/llama.xcframework"
expect_ok "framework verifies a complete device xcframework with pinned provenance" "$PREP" framework --root "$FWROOT"
expect_fail_with "framework rejects a simulator-platform device binary" "platform IOS" \
  env PATH="$MOCKBIN:$PATH" FAKE_VTOOL_PLATFORM=IOSSIMULATOR \
  "$PREP" framework --root "$FWROOT"

cp -R "$FWROOT" "$TMP/fw-symlink"
mv "$TMP/fw-symlink/app/Frameworks/llama.xcframework" "$TMP/fw-symlink-external"
ln -s "$TMP/fw-symlink-external" "$TMP/fw-symlink/app/Frameworks/llama.xcframework"
expect_fail_with "framework rejects a symlinked xcframework directory" "xcframework is a symlink" \
  "$PREP" framework --root "$TMP/fw-symlink"

cp -R "$FWROOT" "$TMP/fw-parent-symlink"
mv "$TMP/fw-parent-symlink/app/Frameworks" "$TMP/fw-parent-external"
ln -s "$TMP/fw-parent-external" "$TMP/fw-parent-symlink/app/Frameworks"
expect_fail_with "framework rejects a symlinked app/Frameworks directory" "app/Frameworks is a symlink" \
  "$PREP" framework --root "$TMP/fw-parent-symlink"

cp -R "$FWROOT" "$TMP/fw-slice-symlink"
mv "$TMP/fw-slice-symlink/app/Frameworks/llama.xcframework/ios-arm64/llama.framework" \
  "$TMP/fw-slice-external"
ln -s "$TMP/fw-slice-external" \
  "$TMP/fw-slice-symlink/app/Frameworks/llama.xcframework/ios-arm64/llama.framework"
expect_fail_with "framework rejects a symlinked device-slice llama.framework" "device slice is a symlink" \
  "$PREP" framework --root "$TMP/fw-slice-symlink"

cp -R "$FWROOT" "$TMP/fw-nomarker"
rm -f "$TMP/fw-nomarker/app/Frameworks/llama.xcframework/.pocketglimmer-provenance.json"
expect_status_with "framework reports unmarked provenance as incomplete" 2 "no build provenance marker" \
  "$PREP" framework --root "$TMP/fw-nomarker"

cp -R "$FWROOT" "$TMP/fw-headertamper"
printf '/* edited after the build */\n' >> "$TMP/fw-headertamper/app/Frameworks/llama.xcframework/ios-arm64/llama.framework/Headers/ggml.h"
expect_status_with "framework reports modified headers as incomplete provenance" 2 "headers/module map sha256" \
  "$PREP" framework --root "$TMP/fw-headertamper"

cp -R "$FWROOT" "$TMP/fw-empty"
: > "$TMP/fw-empty/app/Frameworks/llama.xcframework/ios-arm64/llama.framework/llama"
expect_fail_with "framework rejects an empty device binary" "empty" "$PREP" framework --root "$TMP/fw-empty"

cp -R "$FWROOT" "$TMP/fw-nomodule"
rm -f "$TMP/fw-nomodule/app/Frameworks/llama.xcframework/ios-arm64/llama.framework/Modules/module.modulemap"
expect_fail_with "framework rejects a missing module map" "module.modulemap" "$PREP" framework --root "$TMP/fw-nomodule"

cp -R "$FWROOT" "$TMP/fw-empty-module"
: > "$TMP/fw-empty-module/app/Frameworks/llama.xcframework/ios-arm64/llama.framework/Modules/module.modulemap"
expect_fail_with "framework rejects an empty module map" "module.modulemap" "$PREP" framework --root "$TMP/fw-empty-module"

cp -R "$FWROOT" "$TMP/fw-noheader"
rm -f "$TMP/fw-noheader/app/Frameworks/llama.xcframework/ios-arm64/llama.framework/Headers/llama.h"
expect_fail_with "framework rejects a missing llama.h" "Headers/llama.h" "$PREP" framework --root "$TMP/fw-noheader"

cp -R "$FWROOT" "$TMP/fw-noplat"
cat > "$TMP/fw-noplat/app/Frameworks/llama.xcframework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundlePackageType</key><string>XFWK</string>
</dict></plist>
PLIST
expect_fail_with "framework rejects an empty AvailableLibraries plist" "AvailableLibraries" \
  "$PREP" framework --root "$TMP/fw-noplat"

cp -R "$FWROOT" "$TMP/fw-x86"
make_macho "$TMP/fw-x86/app/Frameworks/llama.xcframework/ios-arm64/llama.framework/llama" x86_64
expect_fail_with "framework rejects a non-arm64 binary" "expected arm64" "$PREP" framework --root "$TMP/fw-x86"

# --- framework build: exit code, staging, retry, dirty pin --------------------

LLAMA_BUILD="$TMP/llama-build"
mkdir -p "$LLAMA_BUILD"
printf '#!/bin/sh\necho fake build failure >&2\nexit 7\n' > "$LLAMA_BUILD/build-xcframework.sh"
chmod +x "$LLAMA_BUILD/build-xcframework.sh"
BUILDROOT="$TMP/buildroot"
make_root "$BUILDROOT"
expect_fail_with "framework reports the real build exit code" "exit 7" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" \
  "$PREP" framework --root "$BUILDROOT" --llama-src "$LLAMA_BUILD"

STALEROOT="$TMP/staleroot"
make_root "$STALEROOT"
mkdir -p "$LLAMA_BUILD/build-apple"
cp -R "$TMP/fw-template" "$LLAMA_BUILD/build-apple/llama.xcframework"
printf '#!/bin/sh\nexit 0\n' > "$LLAMA_BUILD/build-xcframework.sh"
chmod +x "$LLAMA_BUILD/build-xcframework.sh"
expect_fail_with "framework rejects a stale build output after an exit-0 build" "not refreshed" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" \
  "$PREP" framework --root "$STALEROOT" --llama-src "$LLAMA_BUILD"
if [ -e "$STALEROOT/app/Frameworks/llama.xcframework" ]; then
  bad "stale framework output was installed"
else
  pass "stale framework output was not installed"
fi

INVALID_XCFW="$TMP/invalid.xcframework"
cp -R "$TMP/fw-template" "$INVALID_XCFW"
: > "$INVALID_XCFW/ios-arm64/llama.framework/llama"
RUNS="$TMP/build-runs"
: > "$RUNS"
cat > "$LLAMA_BUILD/build-xcframework.sh" <<SH
#!/bin/sh
mkdir -p build-apple
rm -rf build-apple/llama.xcframework
cp -R "$INVALID_XCFW" build-apple/llama.xcframework
echo run >> "$RUNS"
exit 0
SH
chmod +x "$LLAMA_BUILD/build-xcframework.sh"
RCROOT="$TMP/retryroot"
make_root "$RCROOT"
expect_fail_with "framework build validation failure removes the staged copy" "device binary is empty" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" \
  "$PREP" framework --root "$RCROOT" --llama-src "$LLAMA_BUILD"
if [ -e "$RCROOT/app/Frameworks/llama.xcframework" ]; then
  bad "failed framework validation installed a framework"
else
  pass "failed framework validation leaves no destination"
fi
expect_fail_with "framework retry runs the build again after a validation failure" "device binary is empty" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" \
  "$PREP" framework --root "$RCROOT" --llama-src "$LLAMA_BUILD"
if [ "$(wc -l < "$RUNS")" -eq 2 ]; then
  pass "failed framework build is retryable without manual cleanup (2 runs)"
else
  bad "framework build did not run twice"
fi

VALID_XCFW="$TMP/valid.xcframework"
cp -R "$TMP/fw-template" "$VALID_XCFW"
rm -f "$VALID_XCFW/.pocketglimmer-provenance.json"
: > "$RUNS"
cat > "$LLAMA_BUILD/build-xcframework.sh" <<SH
#!/bin/sh
mkdir -p build-apple
rm -rf build-apple/llama.xcframework
cp -R "$VALID_XCFW" build-apple/llama.xcframework
echo run >> "$RUNS"
exit 0
SH
chmod +x "$LLAMA_BUILD/build-xcframework.sh"
OKROOT="$TMP/okroot"
make_root "$OKROOT"
expect_ok "framework build stages, validates, and installs a fresh xcframework" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" \
  "$PREP" framework --root "$OKROOT" --llama-src "$LLAMA_BUILD"
if [ -f "$OKROOT/app/Frameworks/llama.xcframework/.pocketglimmer-provenance.json" ]; then
  pass "framework build writes the pin provenance marker"
else
  bad "framework build did not write the provenance marker"
fi
expect_ok "second framework run verifies the installed xcframework" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" \
  "$PREP" framework --root "$OKROOT" --llama-src "$LLAMA_BUILD"
if [ "$(wc -l < "$RUNS")" -eq 1 ]; then
  pass "second framework run did not rebuild"
else
  bad "second framework run unexpectedly rebuilt"
fi

DIRTYROOT="$TMP/dirtyroot"
make_root "$DIRTYROOT"
expect_fail_with "framework rejects a dirty pinned checkout" "not clean" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" FAKE_GIT_STATUS=' M include/llama.h' \
  "$PREP" framework --root "$DIRTYROOT" --llama-src "$LLAMA_BUILD"
expect_fail_with "framework rejects untracked source in a pinned checkout" "not clean" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA="$LLAMA_COMMIT" FAKE_GIT_STATUS='?? notes.txt' \
  "$PREP" framework --root "$DIRTYROOT" --llama-src "$LLAMA_BUILD"
expect_fail_with "framework rejects a short SHA instead of the exact pinned commit" "pinned to ddf48f85" \
  env PATH="$MOCKBIN:$PATH" FAKE_GIT_SHA=ddf48f8 \
  "$PREP" framework --root "$DIRTYROOT" --llama-src "$LLAMA_BUILD"

LLAMA="$TMP/llama-realgit"
mkdir -p "$LLAMA"
git -C "$LLAMA" init -q
git -C "$LLAMA" config user.email selftest@example.invalid
git -C "$LLAMA" config user.name selftest
printf 'x\n' > "$LLAMA/x"
git -C "$LLAMA" add x
git -C "$LLAMA" commit -qm init
expect_fail_with "framework rejects a non-pinned llama.cpp checkout" "pinned to ddf48f8" \
  "$PREP" framework --root "$BUILDROOT" --llama-src "$LLAMA"

# --- prepare ordering (mock macOS and fake xcodegen) -------------------------

PREP_ROOT="$TMP/preproot"
make_root "$PREP_ROOT"
mkdir -p "$PREP_ROOT/app/Frameworks"
cp -R "$TMP/fw-template" "$PREP_ROOT/app/Frameworks/llama.xcframework"
expect_ok "prepare --bundle-model --require-model bundles before enforcing the model" \
  env PATH="$MOCKBIN:$PATH" "$PREP" prepare --root "$PREP_ROOT" --model "$MODEL" --bundle-model --require-model
PDEST="$PREP_ROOT/app/PocketGlimmer/Resources/Models/$(basename "$SHIPPING_MODEL_REL")"
if [ -f "$PDEST" ] && [ ! -L "$PDEST" ] && [ "$(wc -c < "$PDEST" | tr -d ' ')" = "$SHIPPING_MODEL_BYTES" ]; then
  pass "prepare installed a regular verified model file"
  cp -R "$BASE_APP" "$TMP/app-with-model.app"
  ln "$PDEST" "$TMP/app-with-model.app/shipped.gguf"
  expect_ok "check-app accepts the verified model at the bundle root" \
    "$PREP" check-app --root "$ROOT" --app "$TMP/app-with-model.app" --require-model
else
  bad "prepare did not install the bundled model"
fi

# --- build-unsigned freshness (mock Xcode) -----------------------------------

BUILDROOT2="$TMP/buildunsigned"
make_root "$BUILDROOT2"
mkdir -p "$BUILDROOT2/app/Frameworks"
cp -R "$TMP/fw-template" "$BUILDROOT2/app/Frameworks/llama.xcframework"
DD="$TMP/DerivedData"
STALE="$DD/Build/Products/Release-iphoneos/PocketGlimmer.app"
mkdir -p "$(dirname "$STALE")"
cp -R "$BASE_APP" "$STALE"
expect_fail_with "build-unsigned rejects xcodebuild exit 0 with no fresh app" "did not produce a fresh app bundle" \
  env PATH="$MOCKBIN:$PATH" FAKE_XCODEBUILD_NO_APP=1 \
  "$PREP" build-unsigned --root "$BUILDROOT2" --model "$MODEL" --derived-data "$DD"
if [ -e "$STALE" ]; then
  bad "stale app survived the freshness check"
else
  pass "build-unsigned removed the stale app before the build"
fi

expect_fail_with "build-unsigned reports the real xcodebuild exit code" "exit 7" \
  env PATH="$MOCKBIN:$PATH" FAKE_XCODEBUILD_RC=7 \
  "$PREP" build-unsigned --root "$BUILDROOT2" --model "$MODEL" --derived-data "$DD"

expect_status_with "build-unsigned reports a model-less fresh app as release-incomplete" 2 "RELEASE INCOMPLETE" \
  env PATH="$MOCKBIN:$PATH" FAKE_APP_TEMPLATE="$BASE_APP" \
  "$PREP" build-unsigned --root "$BUILDROOT2" --model "$MODEL" --derived-data "$DD"

expect_ok "build-unsigned accepts a freshly produced valid app with the verified model (mock Xcode)" \
  env PATH="$MOCKBIN:$PATH" FAKE_APP_TEMPLATE="$BASE_APP" FAKE_APP_MODEL_PATH="$MODEL" \
  "$PREP" build-unsigned --root "$BUILDROOT2" --model "$MODEL" --derived-data "$DD"

# --- no unsafe --no-generate -------------------------------------------------

expect_fail_with "build-unsigned rejects removed --no-generate" "unknown argument" \
  "$PREP" build-unsigned --root "$REPO" --no-generate

printf '\nSELFTEST: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
