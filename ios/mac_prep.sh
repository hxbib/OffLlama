#!/usr/bin/env bash
# Pocket Glimmer macOS build preparation and verification.
#
# This script never downloads a runtime, installs a tool, changes the active
# Xcode, touches signing, or installs an app. It only reads the repo and writes
# generated build output under ios/.build (plus the optional model/framework
# copies named on the command line).
set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
SHIPPING_MODEL_REL="models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf"
SHIPPING_MODEL_BYTES=807694080
SHIPPING_MODEL_SHA256=a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2
LLAMA_COMMIT=ddf48f8
CALIBRATION_REL="app/PocketGlimmer/Resources/Models/calibration.json"
SKILLS_REL="app/PocketGlimmer/Resources/Skills/builtin.json"
ENTITLEMENTS_REL="app/PocketGlimmer/Support/PocketGlimmer.entitlements"
FRAMEWORK_REL="app/Frameworks/llama.xcframework"

CMD=""
MODEL_OPT=""
LLAMA_SRC=""
APP_OPT=""
DERIVED_DATA=""
BUNDLE_MODEL=0
ALLOW_NO_MODEL=0
WITH_SIMULATOR=0
NO_GENERATE=0
REQUIRE_MODEL=0
FAILS=0
SKIPS=0

usage() {
  cat <<'EOF'
Pocket Glimmer macOS prep and verification.

Usage: ios/mac_prep.sh <command> [options]

Commands:
  preflight          Check macOS, Xcode, iOS SDK, XcodeGen, framework,
                     model, calibration, skills, and entitlements.
  verify-resources   Check the shipped model, calibration, skills, and
                     entitlements without requiring macOS.
  prepare            Verify resources, optionally bundle the model, check the
                     llama framework, and generate PocketGlimmer.xcodeproj.
  framework          Verify app/Frameworks/llama.xcframework, or build it from
                     an existing llama.cpp checkout at ddf48f8 if absent.
  bundle-model       Verify the shipping GGUF and copy it into the app bundle.
  build-unsigned     Compile a generic iOS Release build with signing disabled,
                     then validate the .app bundle. Does not sign or install.
  check-app          Validate an already built PocketGlimmer.app:
                       ios/mac_prep.sh check-app --app PATH [--allow-no-model]

Options:
  --root PATH          Repo root (default: parent of this script).
  --model PATH         Model to verify/bundle (default: models/SHIPPING-...gguf).
  --llama-src PATH     Existing llama.cpp checkout (required by framework when
                       app/Frameworks/llama.xcframework is absent).
  --app PATH           Built .app path for check-app.
  --derived-data PATH  DerivedData path for build-unsigned.
  --bundle-model       In prepare, copy the verified model into app resources.
  --allow-no-model     Permit a missing model for compile-only checks. The
                       result is reported as incomplete, not ready.
  --with-simulator     Build the simulator slice too (non-device work only).
  --no-generate        Skip xcodegen generate in build-unsigned.
  --require-model      Fail check-app/build-unsigned if no model is bundled.
  -h, --help           Show this help.

Examples:
  ios/mac_prep.sh preflight
  ios/mac_prep.sh bundle-model
  ios/mac_prep.sh framework --llama-src ~/src/llama.cpp
  ios/mac_prep.sh prepare --bundle-model
  ios/mac_prep.sh build-unsigned
  ios/mac_prep.sh check-app --app ios/.build/DerivedData/Build/Products/Release-iphoneos/PocketGlimmer.app

The script never runs brew, xcode-select, xcodebuild -downloadPlatform,
codesign, or a device install. Missing tools and runtimes are reported with
their Apple or project documentation path; the person running it decides.
EOF
}

ok()   { printf 'ok   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
skip() { printf 'SKIP %s\n' "$*"; SKIPS=$((SKIPS + 1)); }
section() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 2; }

abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s/%s\n' "$(pwd)" "$1" ;;
  esac
}

file_size() { wc -c < "$1" | tr -d '[:space:]'; }

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    return 127
  fi
}

cmake_new_enough() {
  command -v cmake >/dev/null 2>&1 || return 1
  local v major minor
  v=$(cmake --version 2>/dev/null | awk 'NR == 1 { print $3; exit }')
  major=${v%%.*}
  minor=${v#*.}
  minor=${minor%%.*}
  [ "${major:-0}" -gt 3 ] 2>/dev/null && return 0
  [ "${major:-0}" -eq 3 ] 2>/dev/null && [ "${minor:-0}" -ge 28 ] 2>/dev/null
}

json_lint() {
  local f=$1
  if command -v plutil >/dev/null 2>&1 && plutil -lint "$f" >/dev/null 2>&1; then
    return 0
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -m json.tool "$f" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

plist_value() {
  local f=$1 key=$2
  if command -v plutil >/dev/null 2>&1; then
    plutil -extract "$key" raw -o - "$f" 2>/dev/null
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$f" "$key" <<'PY'
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as fh:
        value = plistlib.load(fh).get(sys.argv[2], "")
    if isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
except Exception:
    sys.exit(1)
PY
    return
  fi
  return 1
}

plist_true() {
  local value
  value=$(plist_value "$1" "$2") || return 1
  case "$value" in
    true|True|YES|1) return 0 ;;
    *) return 1 ;;
  esac
}

require_darwin() {
  local os
  os=$(uname -s)
  if [ "$os" != Darwin ]; then
    fail "unsupported host $os: this command needs macOS with full Xcode"
    printf '     On Linux use: %s verify-resources\n' "$0"
    return 1
  fi
  ok "host macOS"
}

check_framework() {
  local fw=$1
  local device="$fw/ios-arm64/llama.framework/llama"
  local header="$fw/ios-arm64/llama.framework/Headers/llama.h"
  local modulemap="$fw/ios-arm64/llama.framework/Modules/module.modulemap"

  if [ ! -d "$fw" ]; then
    fail "missing $FRAMEWORK_REL"
    printf '     Build it from a ddf48f8 checkout: %s framework --llama-src ~/src/llama.cpp\n' "$0"
    printf '     Or follow ios/MAC_DAY_RUNBOOK.md section 4.\n'
    return 1
  fi
  if [ ! -f "$fw/Info.plist" ]; then
    fail "$FRAMEWORK_REL has no Info.plist; the copy is incomplete"
    return 1
  fi
  if [ ! -f "$device" ]; then
    fail "$FRAMEWORK_REL has no device slice (ios-arm64/llama.framework/llama)"
    printf '     Rebuild with: cd ~/src/llama.cpp && ./build-xcframework.sh ios-device\n'
    return 1
  fi
  if [ ! -f "$modulemap" ]; then
    warn "$FRAMEWORK_REL has no Modules/module.modulemap; import llama may fail"
  fi
  if [ -f "$header" ]; then
    if ! grep -q 'llama_memory_seq_cp' "$header" || ! grep -q 'kv_unified' "$header"; then
      fail "$FRAMEWORK_REL headers do not match the pinned ddf48f8 API used by LlamaCppEngine"
      return 1
    fi
  else
    warn "$FRAMEWORK_REL has no llama.h; the pinned API cannot be checked"
  fi
  ok "llama.xcframework with device slice"
}

check_model_file() {
  local f=$1 label=${2:-model}
  local size hash

  if [ ! -f "$f" ]; then
    fail "$label missing: $f"
    return 1
  fi
  size=$(file_size "$f")
  if [ "$size" -lt 1000000 ]; then
    fail "$label is only $size bytes; this is a Git LFS pointer"
    printf '     Run: git lfs install && git lfs pull\n'
    return 1
  fi
  if [ "$size" -ne "$SHIPPING_MODEL_BYTES" ]; then
    fail "$label size is $size bytes; expected $SHIPPING_MODEL_BYTES"
    return 1
  fi
  hash=$(hash_file "$f") || {
    fail "$label cannot be hashed: need shasum or sha256sum"
    return 1
  }
  if [ "$hash" != "$SHIPPING_MODEL_SHA256" ]; then
    fail "$label sha256 is $hash; expected $SHIPPING_MODEL_SHA256"
    return 1
  fi
  ok "$label: $(basename "$f") ($size bytes, sha256 ${hash:0:12}...${hash: -4})"
}

model_path() {
  local p=${MODEL_OPT:-"$ROOT/$SHIPPING_MODEL_REL"}
  abs_path "$p"
}

check_model_source() {
  local f
  f=$(model_path)
  if [ ! -f "$f" ]; then
    if [ "$ALLOW_NO_MODEL" = 1 ]; then
      skip "shipping model missing; compile-only request (run git lfs pull for a usable install)"
      return 0
    fi
    fail "shipping model missing: $f"
    printf '     Run: git lfs install && git lfs pull\n'
    printf '     Or pass --model PATH to a verified copy.\n'
    return 1
  fi
  check_model_file "$f" "shipping model"
}

check_bundled_models() {
  local found=0 f
  while IFS= read -r -d '' f; do
    found=1
    check_model_file "$f" "bundled model" || true
  done < <(find "$ROOT/app/PocketGlimmer/Resources/Models" -type f -name '*.gguf' -print0 2>/dev/null)

  if [ "$found" = 0 ]; then
    if [ "$REQUIRE_MODEL" = 1 ]; then
      fail "no .gguf is bundled in app/PocketGlimmer/Resources/Models"
      printf '     Run: %s bundle-model\n' "$0"
      return 1
    fi
    warn "no bundled model; the app can still compile and receive a .gguf through Files"
  fi
}

validate_calibration() {
  local f=$1
  local tau prompt

  if [ ! -f "$f" ]; then
    fail "calibration.json missing: $f"
    return 1
  fi
  if ! json_lint "$f"; then
    fail "calibration.json is not valid JSON: $f"
    return 1
  fi
  tau=$(plist_value "$f" defaultTau 2>/dev/null || true)
  if [ -z "$tau" ]; then
    tau=$(python3 - "$f" <<'PY' 2>/dev/null || true
import json, sys
print(json.load(open(sys.argv[1])).get("defaultTau", ""))
PY
)
  fi
  if ! awk -v t="$tau" 'BEGIN { exit !(t + 0 == 0.9) }'; then
    fail "calibration.json defaultTau is '$tau'; the certified operating point is 0.90"
    return 1
  fi
  prompt=$(plist_value "$f" promptStyle 2>/dev/null || true)
  if [ -z "$prompt" ]; then
    prompt=$(python3 - "$f" <<'PY' 2>/dev/null || true
import json, sys
print(json.load(open(sys.argv[1])).get("promptStyle", ""))
PY
)
  fi
  if [ -z "$prompt" ]; then
    fail "calibration.json has no promptStyle"
    return 1
  fi

  local keys=(answerability confirmBeforeAct memoryConflict notificationTriage nudgeNow
    rememberOrNot route sensitivity timing toolChoice)
  local n
  for n in 2 3 4 5 6 7 8; do
    keys+=("contactPick#$n" "eventPick#$n" "skillPick#$n")
  done

  if [ "$(uname -s)" = Darwin ] && command -v plutil >/dev/null 2>&1; then
    local out key
    out=$(plutil -p "$f") || { fail "calibration.json cannot be read"; return 1; }
    for key in "${keys[@]}"; do
      printf '%s\n' "$out" | grep -q "\"$key\" =>" || { fail "calibration.json missing prior key $key"; return 1; }
    done
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$f" <<'PY'
import json, sys
required = [
    "answerability", "confirmBeforeAct", "memoryConflict", "notificationTriage",
    "nudgeNow", "rememberOrNot", "route", "sensitivity", "timing", "toolChoice",
]
required += [f"contactPick#{n}" for n in range(2, 9)]
required += [f"eventPick#{n}" for n in range(2, 9)]
required += [f"skillPick#{n}" for n in range(2, 9)]
prior = json.load(open(sys.argv[1])).get("prior")
if not isinstance(prior, dict):
    print("calibration.json has no prior object")
    sys.exit(1)
missing = [k for k in required if k not in prior]
if missing:
    print("calibration.json is missing prior keys: " + ", ".join(missing))
    sys.exit(1)
if len(prior) < 24:
    print(f"calibration.json has only {len(prior)} prior keys; expected at least 24")
    sys.exit(1)
PY
    then
      fail "calibration.json does not carry the certified prior set"
      return 1
    fi
  else
    fail "cannot inspect calibration.json: need plutil or python3"
    return 1
  fi
  ok "calibration.json: promptStyle=$prompt, defaultTau=0.90, certified priors present"
}

validate_skills() {
  local f=$1
  if [ ! -f "$f" ]; then
    fail "skills registry missing: $f"
    return 1
  fi
  if ! json_lint "$f"; then
    fail "skills registry is not valid JSON: $f"
    return 1
  fi
  if [ "$(uname -s)" = Darwin ] && command -v plutil >/dev/null 2>&1; then
    local out
    out=$(plutil -p "$f") || { fail "skills registry cannot be read"; return 1; }
    printf '%s\n' "$out" | grep -q '"skills" =>' || { fail "skills registry has no skills array"; return 1; }
    printf '%s\n' "$out" | grep -q '"id" =>' || { fail "skills registry has no id fields"; return 1; }
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$f" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
skills = data.get("skills")
if not isinstance(skills, list) or not skills:
    print("skills registry has no non-empty 'skills' array")
    sys.exit(1)
if not all(isinstance(s, dict) and s.get("id") for s in skills):
    print("skills registry has an entry without an id")
    sys.exit(1)
PY
    then
      fail "skills registry structure is wrong"
      return 1
    fi
  else
    fail "cannot inspect builtin.json: need plutil or python3"
    return 1
  fi
  ok "skills registry: bundled builtin.json is valid"
}

validate_entitlements() {
  local f=$1
  if [ ! -f "$f" ]; then
    fail "entitlements file missing: $f"
    return 1
  fi
  if command -v plutil >/dev/null 2>&1; then
    if ! plutil -lint "$f" >/dev/null 2>&1; then
      fail "entitlements file is not a valid plist: $f"
      return 1
    fi
    if plutil -p "$f" 2>/dev/null | grep -q '=>'; then
      fail "free-team entitlements must stay empty; found a key in $f"
      return 1
    fi
  elif grep -q '<key>' "$f"; then
    fail "free-team entitlements must stay empty; found a key in $f"
    return 1
  fi
  ok "entitlements: empty (free personal team compatible)"
}

validate_resources() {
  validate_calibration "$ROOT/$CALIBRATION_REL" || true
  validate_skills "$ROOT/$SKILLS_REL" || true
  validate_entitlements "$ROOT/$ENTITLEMENTS_REL" || true
}

cmd_verify_resources() {
  section "Model"
  check_model_source || true
  check_bundled_models || true
  section "Bundle resources"
  validate_resources

  if [ "$FAILS" -ne 0 ]; then
    printf '\nRESOURCES FAILED: %d required check(s) failed. Nothing was changed.\n' "$FAILS"
    return 1
  fi
  if [ "$SKIPS" -ne 0 ]; then
    printf '\nRESOURCES INCOMPLETE: compile-only skips were requested.\n'
    return 2
  fi
  printf '\nRESOURCES PASSED: model, calibration, skills, and entitlements match the shipping set.\n'
}

cmd_preflight() {
  local fw="$ROOT/$FRAMEWORK_REL"

  section "Host"
  if ! require_darwin; then
    printf '\nPREFLIGHT FAILED: this command only runs on macOS.\n'
    return 1
  fi

  section "Xcode"
  if command -v xcodebuild >/dev/null 2>&1; then
    local xv
    if xv=$(xcodebuild -version 2>&1); then
      ok "xcodebuild: $(printf '%s' "$xv" | tr '\n' ' ')"
    else
      fail "xcodebuild is present but not usable: $xv"
      printf '     Install full Xcode, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer\n'
    fi
  else
    fail "xcodebuild not found"
    printf '     Install full Xcode (App Store or https://developer.apple.com/xcode/).\n'
    printf '     xcode-select --install installs Command Line Tools only, not the iOS build system.\n'
  fi
  if command -v xcode-select >/dev/null 2>&1; then
    ok "active developer directory: $(xcode-select -p 2>/dev/null || echo unknown)"
  fi
  if command -v xcrun >/dev/null 2>&1; then
    local sdk sdkver major
    if sdk=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null) && [ -n "$sdk" ]; then
      ok "iOS SDK: $sdk"
      sdkver=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 0)
      major=${sdkver%%.*}
      if [ "${major:-0}" -lt 18 ] 2>/dev/null; then
        fail "iOS SDK $sdkver is older than the iOS 18 deployment target"
      fi
    else
      fail "no iOS SDK for iphoneos"
      printf '     In Xcode: Settings > Components > install the iOS platform support.\n'
      printf '     Or from a terminal (a large download, your choice): xcodebuild -downloadPlatform iOS\n'
    fi
  else
    fail "xcrun not found; Xcode is not installed or not selected"
  fi

  section "Project tools"
  if command -v xcodegen >/dev/null 2>&1; then
    ok "xcodegen: $(xcodegen --version 2>&1 | head -1)"
  else
    fail "xcodegen not found"
    printf '     Install it yourself: brew install xcodegen (https://github.com/yonaskolb/XcodeGen)\n'
  fi
  if [ ! -d "$fw" ]; then
    if cmake_new_enough; then
      ok "cmake: $(cmake --version 2>/dev/null | head -1)"
    else
      fail "cmake 3.28 or newer is missing (needed only to build llama.xcframework)"
      printf '     Install it yourself: brew install cmake\n'
    fi
  fi
  if command -v shasum >/dev/null 2>&1; then
    ok "shasum available for the model hash"
  elif command -v sha256sum >/dev/null 2>&1; then
    ok "sha256sum available for the model hash"
  else
    fail "no shasum or sha256sum; cannot verify the model"
  fi
  if command -v git >/dev/null 2>&1; then
    ok "git: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo no-commit)"
  else
    fail "git not found"
  fi

  section "llama.xcframework"
  if [ -d "$fw" ]; then
    check_framework "$fw" || true
  else
    fail "missing $FRAMEWORK_REL"
    printf '     Build it only if absent: %s framework --llama-src ~/src/llama.cpp\n' "$0"
    printf '     Or follow ios/MAC_DAY_RUNBOOK.md section 4.\n'
  fi

  section "Model and bundle resources"
  check_model_source || true
  check_bundled_models || true
  validate_resources

  if [ "$FAILS" -ne 0 ]; then
    printf '\nPREFLIGHT FAILED: %d required check(s) failed. Nothing was changed.\n' "$FAILS"
    return 1
  fi
  if [ "$SKIPS" -ne 0 ]; then
    printf '\nPREFLIGHT INCOMPLETE: compile-only skips were requested; this is not install-ready.\n'
    return 2
  fi
  printf '\nPREFLIGHT PASSED: toolchain, framework, model, calibration, skills, and entitlements are ready.\n'
  printf 'Next: core tests, then %s build-unsigned\n' "$0"
}

bundle_model() {
  local src destdir dest
  src=$(model_path)
  check_model_file "$src" "shipping model" || return 1
  destdir="$ROOT/app/PocketGlimmer/Resources/Models"
  dest="$destdir/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf"
  mkdir -p "$destdir" || { fail "cannot create $destdir"; return 1; }

  if [ -e "$dest" ]; then
    if [ "$src" -ef "$dest" ] 2>/dev/null; then
      ok "model already bundled at $dest"
      return 0
    fi
    local oldhash oldsize
    oldsize=$(file_size "$dest")
    oldhash=$(hash_file "$dest" 2>/dev/null || true)
    if [ "$oldsize" = "$SHIPPING_MODEL_BYTES" ] && [ "$oldhash" = "$SHIPPING_MODEL_SHA256" ]; then
      ok "verified shipping model already bundled; leaving it untouched"
      return 0
    fi
    fail "refusing to overwrite a different file at $dest"
    printf '     Existing: %s bytes, sha256 %s\n' "$oldsize" "${oldhash:-unknown}"
    printf '     Move it aside yourself if you intend to replace it; this script never deletes user files.\n'
    return 1
  fi

  cp "$src" "$dest" || { fail "copy failed: $src -> $dest"; return 1; }
  if ! check_model_file "$dest" "bundled model"; then
    rm -f "$dest"        # only the file this run created
    fail "removed the bad copy created by this run"
    return 1
  fi
  ok "bundled model ready: $dest"
}

cmd_bundle_model() {
  section "Bundled model"
  bundle_model || true
  if [ "$FAILS" -ne 0 ]; then
    printf '\nMODEL BUNDLE FAILED. Nothing else was changed.\n'
    return 1
  fi
  printf '\nMODEL BUNDLE PASSED: the app bundle now carries the verified shipping GGUF.\n'
}

cmd_framework() {
  local fw="$ROOT/$FRAMEWORK_REL"
  local src out log rc

  section "llama.xcframework"
  if [ -d "$fw" ]; then
    check_framework "$fw" || true
    if [ "$FAILS" -eq 0 ]; then
      printf '\nFRAMEWORK PRESENT: existing xcframework verified; it was not rebuilt.\n'
    fi
    if [ "$FAILS" -eq 0 ]; then return 0; else return 1; fi
  fi

  if [ -z "$LLAMA_SRC" ]; then
    fail "--llama-src is required when $FRAMEWORK_REL is absent"
    printf '     Example: %s framework --llama-src ~/src/llama.cpp\n' "$0"
    return 1
  fi
  LLAMA_SRC=$(abs_path "$LLAMA_SRC")
  if [ ! -d "$LLAMA_SRC" ]; then
    fail "llama.cpp checkout not found: $LLAMA_SRC"
    return 1
  fi
  if ! src=$(git -C "$LLAMA_SRC" rev-parse HEAD 2>/dev/null); then
    fail "cannot read the git revision of $LLAMA_SRC"
    return 1
  fi
  case "$src" in
    "$LLAMA_COMMIT"*) ;;
    *)
      fail "llama.cpp checkout is at ${src:0:12}; the app is pinned to $LLAMA_COMMIT"
      printf '     Do not build a different API. In your own checkout run: git fetch origin && git checkout %s\n' "$LLAMA_COMMIT"
      return 1
      ;;
  esac
  if [ ! -x "$LLAMA_SRC/build-xcframework.sh" ]; then
    fail "$LLAMA_SRC/build-xcframework.sh is missing or not executable"
    return 1
  fi
  require_darwin || return 1
  if ! cmake_new_enough; then
    fail "cmake 3.28 or newer is required to build llama.xcframework"
    printf '     Install it yourself: brew install cmake\n'
    return 1
  fi

  out="$LLAMA_SRC/build-apple/llama.xcframework"
  printf 'Building at pinned commit %s. The llama.cpp script will rebuild its build-* directories under %s.\n' "$LLAMA_COMMIT" "$LLAMA_SRC"
  if [ "$WITH_SIMULATOR" = 1 ]; then
    set -- ios-device ios-sim
  else
    set -- ios-device
  fi
  log="$ROOT/ios/.build/logs/framework-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$log")"
  if ! ( cd "$LLAMA_SRC" && ./build-xcframework.sh "$@" ) >"$log" 2>&1; then
    rc=$?
    fail "build-xcframework.sh failed (exit $rc)"
    printf '     Full log: %s\n' "$log"
    tail -30 "$log" >&2 || true
    return 1
  fi
  if [ ! -d "$out" ]; then
    fail "build-xcframework.sh finished but $out is missing"
    return 1
  fi
  if [ -e "$fw" ]; then
    fail "$fw appeared while the build was running; refusing to overwrite it"
    return 1
  fi
  mkdir -p "$(dirname "$fw")" || { fail "cannot create app/Frameworks"; return 1; }
  if ! cp -R "$out" "$fw"; then
    rm -rf "$fw" 2>/dev/null || true   # only the copy this run created
    fail "copy failed: $out -> $fw"
    return 1
  fi
  check_framework "$fw" || true
  if [ "$FAILS" -ne 0 ]; then
    printf '\nFRAMEWORK BUILD FAILED validation. Log: %s\n' "$log"
    return 1
  fi
  printf '\nFRAMEWORK READY: %s (log %s)\n' "$fw" "$log"
}

generate_project() {
  local log
  log="$ROOT/ios/.build/logs/xcodegen-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$log")"
  if ! command -v xcodegen >/dev/null 2>&1; then
    fail "xcodegen not found"
    printf '     Install it yourself: brew install xcodegen\n'
    return 1
  fi
  if ! ( cd "$ROOT/app" && xcodegen generate ) >"$log" 2>&1; then
    fail "xcodegen generate failed"
    printf '     Full log: %s\n' "$log"
    tail -30 "$log" >&2 || true
    return 1
  fi
  if [ ! -d "$ROOT/app/PocketGlimmer.xcodeproj" ]; then
    fail "xcodegen finished but app/PocketGlimmer.xcodeproj is missing"
    return 1
  fi
  ok "generated app/PocketGlimmer.xcodeproj"
}

check_app() {
  local app=$1
  local name cal skills fw f

  if [ ! -d "$app" ]; then
    fail "app bundle missing: $app"
    return 1
  fi
  if [ ! -f "$app/Info.plist" ]; then
    fail "app bundle has no Info.plist: $app"
    return 1
  fi
  name=$(plist_value "$app/Info.plist" CFBundleExecutable 2>/dev/null || true)
  name=${name:-PocketGlimmer}
  if [ ! -f "$app/$name" ]; then
    fail "app executable missing: $app/$name"
    return 1
  fi
  if ! plist_true "$app/Info.plist" UIFileSharingEnabled; then
    fail "Info.plist does not enable UIFileSharingEnabled; Finder/Files model copy would not work"
    return 1
  fi
  ok "app bundle: $app (executable $name, Files sharing enabled)"

  cal=$(find "$app" -type f -name calibration.json 2>/dev/null | head -1)
  if [ -z "$cal" ]; then
    fail "built app has no calibration.json"
    printf '     Check that app/PocketGlimmer/Resources/Models/calibration.json is in Copy Bundle Resources.\n'
  else
    validate_calibration "$cal" || true
  fi

  skills=$(find "$app" -type f -name builtin.json 2>/dev/null | head -1)
  if [ -z "$skills" ]; then
    fail "built app has no builtin.json skills registry"
  else
    validate_skills "$skills" || true
  fi

  fw=$(find "$app/Frameworks" -type f -path '*/llama.framework/llama' 2>/dev/null | head -1)
  if [ -z "$fw" ]; then
    fail "built app has no embedded llama.framework binary"
  else
    ok "embedded llama.framework"
  fi

  local found=0
  while IFS= read -r -d '' f; do
    found=1
    check_model_file "$f" "bundled model" || true
  done < <(find "$app" -type f -name '*.gguf' -print0 2>/dev/null)
  if [ "$found" = 0 ]; then
    if [ "$REQUIRE_MODEL" = 1 ]; then
      fail "no .gguf in the built app"
    else
      warn "no .gguf in the built app; copy the model through Files after install"
    fi
  fi

  if [ "$FAILS" -ne 0 ]; then
    printf '\nAPP BUNDLE FAILED: %d required check(s) failed.\n' "$FAILS"
    return 1
  fi
  printf '\nAPP BUNDLE PASSED: calibration, skills, and framework are in place.\n'
}

cmd_check_app() {
  if [ -z "$APP_OPT" ]; then
    die "check-app needs --app PATH"
  fi
  section "Built app"
  check_app "$(abs_path "$APP_OPT")" || true
  [ "$FAILS" -eq 0 ] || return 1
}

cmd_prepare() {
  section "Resources"
  if ! require_darwin; then return 1; fi
  check_model_source || true
  check_bundled_models || true
  validate_resources
  check_framework "$ROOT/$FRAMEWORK_REL" || true

  if [ "$BUNDLE_MODEL" = 1 ] && [ "$FAILS" -eq 0 ]; then
    section "Bundle model"
    bundle_model || true
  fi

  if [ "$FAILS" -ne 0 ]; then
    printf '\nPREPARE FAILED: fix the checks above. Nothing was signed or installed.\n'
    return 1
  fi
  if [ "$SKIPS" -ne 0 ]; then
    printf '\nPREPARE INCOMPLETE: compile-only skips were requested.\n'
    return 2
  fi

  section "Xcode project"
  generate_project || return 1
  printf '\nPREPARE PASSED. Next: %s build-unsigned\n' "$0"
}

run_logged() {
  local log=$1
  shift
  local -a ps
  "$@" 2>&1 | tee "$log"
  ps=("${PIPESTATUS[@]}")
  if [ "${ps[1]}" -ne 0 ]; then
    return "${ps[1]}"
  fi
  return "${ps[0]}"
}

cmd_build_unsigned() {
  local fw="$ROOT/$FRAMEWORK_REL"
  local log dd app rc

  section "Unsigned generic iOS Release build"
  if ! require_darwin; then return 1; fi
  if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "xcodebuild not found; install full Xcode and select it with xcode-select"
    return 1
  fi
  if ! command -v xcodegen >/dev/null 2>&1 && [ "$NO_GENERATE" = 0 ]; then
    fail "xcodegen not found; install it or pass --no-generate with an existing project"
    return 1
  fi
  check_framework "$fw" || true
  check_model_source || true
  check_bundled_models || true
  validate_resources
  if [ "$FAILS" -ne 0 ]; then
    printf '\nBUILD NOT STARTED: fix the checks above first.\n'
    return 1
  fi

  if [ "$NO_GENERATE" = 0 ]; then
    section "Xcode project"
    generate_project || return 1
  fi

  dd=${DERIVED_DATA:-"$ROOT/ios/.build/DerivedData"}
  dd=$(abs_path "$dd")
  mkdir -p "$dd"
  log="$ROOT/ios/.build/logs/unsigned-release-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$log")"

  printf 'xcodebuild -project app/PocketGlimmer.xcodeproj -scheme PocketGlimmer -configuration Release\n'
  printf '  -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO\n'
  if run_logged "$log" \
    xcodebuild \
      -project "$ROOT/app/PocketGlimmer.xcodeproj" \
      -scheme PocketGlimmer \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -derivedDataPath "$dd" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY= \
      build
  then
    ok "xcodebuild finished"
  else
    rc=$?
    fail "xcodebuild failed (exit $rc)"
    printf '     Full log: %s\n' "$log"
    tail -40 "$log" >&2 || true
    grep -qiE 'not installed|unable to find a destination|downloadPlatform' "$log" && \
      printf '     If the iOS platform is missing: Xcode > Settings > Components (or xcodebuild -downloadPlatform iOS, your choice).\n'
    return 1
  fi

  app="$dd/Build/Products/Release-iphoneos/PocketGlimmer.app"
  section "Built app"
  check_app "$app" || {
    printf '     Build log: %s\n' "$log"
    return 1
  }
  printf '\nUNSIGNED BUILD PASSED (compile/link and bundle resources only).\n'
  printf 'This is not signed, not installed, and not run on a device.\n'
  printf 'App: %s\nLog: %s\n' "$app" "$log"
  if [ "$SKIPS" -ne 0 ]; then
    printf 'INSTALL-READY INCOMPLETE: a required artifact was skipped; see SKIP lines above.\n'
    return 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    preflight|verify-resources|prepare|framework|bundle-model|build-unsigned|check-app)
      [ -z "$CMD" ] || die "only one command may be given"
      CMD=$1
      ;;
    --root) [ $# -ge 2 ] || die "--root needs a path"; ROOT=$2; shift ;;
    --model) [ $# -ge 2 ] || die "--model needs a path"; MODEL_OPT=$2; shift ;;
    --llama-src) [ $# -ge 2 ] || die "--llama-src needs a path"; LLAMA_SRC=$2; shift ;;
    --app) [ $# -ge 2 ] || die "--app needs a path"; APP_OPT=$2; shift ;;
    --derived-data) [ $# -ge 2 ] || die "--derived-data needs a path"; DERIVED_DATA=$2; shift ;;
    --bundle-model) BUNDLE_MODEL=1 ;;
    --allow-no-model) ALLOW_NO_MODEL=1 ;;
    --with-simulator) WITH_SIMULATOR=1 ;;
    --no-generate) NO_GENERATE=1 ;;
    --require-model) REQUIRE_MODEL=1 ;;
    --) shift; break ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

[ -n "$CMD" ] || { usage; exit 2; }
ROOT=$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd) || die "repo root not found"
[ -f "$ROOT/app/project.yml" ] || die "not a Pocket Glimmer checkout: $ROOT/app/project.yml is missing"

case "$CMD" in
  preflight)        cmd_preflight ;;
  verify-resources) cmd_verify_resources ;;
  prepare)          cmd_prepare ;;
  framework)        cmd_framework ;;
  bundle-model)     cmd_bundle_model ;;
  build-unsigned)   cmd_build_unsigned ;;
  check-app)        cmd_check_app ;;
  *)                die "unknown command: $CMD" ;;
esac
