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
[ -f "$SCRIPT_DIR/artifacts.env" ] || { printf 'error: missing %s\n' "$SCRIPT_DIR/artifacts.env" >&2; exit 2; }
# shellcheck source=ios/artifacts.env
. "$SCRIPT_DIR/artifacts.env"
VALIDATOR="$SCRIPT_DIR/validate_artifacts.py"
FRAMEWORK_REL="app/Frameworks/llama.xcframework"
FRAMEWORK_MARKER=".pocketglimmer-provenance.json"

CMD=""
MODEL_OPT=""
LLAMA_SRC=""
APP_OPT=""
DERIVED_DATA=""
BUNDLE_MODEL=0
ALLOW_NO_MODEL=0
WITH_SIMULATOR=0
REQUIRE_MODEL=0
FAILS=0
SKIPS=0
INCOMPLETE=0
STAGE_PARENT=""

cleanup_stage() {
  if [ -n "$STAGE_PARENT" ]; then
    rm -rf "$STAGE_PARENT"
  fi
}
trap cleanup_stage EXIT

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
                     a clean llama.cpp checkout at the pinned commit if absent.
  bundle-model       Verify the shipping GGUF and copy it into the app bundle.
  build-unsigned     Compile a fresh generic iOS Release build with signing
                     disabled, then validate the .app bundle. Does not sign or
                     install.
  check-app          Validate an already built PocketGlimmer.app, using the
                     app's real lookup paths (bundle root, then Models/Skills):
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
  --require-model      Fail check-app/build-unsigned/prepare if no model is
                       bundled.
  -h, --help           Show this help.

Exit status:
  0  every required check ran and passed (framework provenance verified where
     it is claimed).
  1  a required check failed.
  2  a required check was skipped or an artifact is structurally usable but not
     verified (for example an xcframework without pin provenance).

Examples:
  ios/mac_prep.sh preflight
  ios/mac_prep.sh bundle-model
  ios/mac_prep.sh framework --llama-src ~/src/llama.cpp
  ios/mac_prep.sh prepare --bundle-model --require-model
  ios/mac_prep.sh build-unsigned
  ios/mac_prep.sh check-app --app ios/.build/DerivedData/Build/Products/Release-iphoneos/PocketGlimmer.app

Python 3 is required for the strict calibration, skills, plist, provenance, and
Mach-O structural checks on both Linux and macOS.

The script never runs brew, xcode-select, xcodebuild -downloadPlatform,
codesign, or a device install. Missing tools and runtimes are reported with
their Apple or project documentation path; the person running it decides.
EOF
}

ok()   { printf 'ok   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
skip() { printf 'SKIP %s\n' "$*"; SKIPS=$((SKIPS + 1)); }
incomplete() { printf 'INCOMPLETE %s\n' "$*"; INCOMPLETE=$((INCOMPLETE + 1)); }
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
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 127
  fi
}

run_validator() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required for strict artifact validation\n' >&2
    return 1
  fi
  if [ ! -f "$VALIDATOR" ]; then
    printf 'validator missing: %s\n' "$VALIDATOR" >&2
    return 1
  fi
  python3 "$VALIDATOR" "$@"
}

validate_with() {
  local what=$1
  shift
  local out
  if ! out=$(run_validator "$@" 2>&1); then
    fail "$what: $out"
    return 1
  fi
  ok "$what: $out"
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

verify_macho_native() {
  local bin=$1 label=$2 out
  if ! command -v file >/dev/null 2>&1; then
    fail "$label: file(1) is required to prove a Mach-O binary"
    return 1
  fi
  if ! out=$(file -b "$bin" 2>&1); then
    fail "$label: file(1) could not read the binary: $out"
    return 1
  fi
  case "$out" in
    *Mach-O*arm64*) ;;
    *)
      fail "$label: file reports '$out' (need a Mach-O arm64 binary)"
      return 1
      ;;
  esac
  if ! command -v lipo >/dev/null 2>&1; then
    fail "$label: lipo(1) is required to prove an arm64 slice"
    return 1
  fi
  if ! out=$(lipo -info "$bin" 2>&1); then
    fail "$label: lipo -info failed: $out"
    return 1
  fi
  case "$out" in
    *arm64*) ;;
    *)
      fail "$label: lipo reports '$out' (need arm64)"
      return 1
      ;;
  esac
  if ! command -v otool >/dev/null 2>&1; then
    fail "$label: otool(1) is required to verify the framework install name"
    return 1
  fi
  if ! out=$(otool -D "$bin" 2>&1); then
    fail "$label: otool -D failed: $out"
    return 1
  fi
  case "$out" in
    *'@rpath/llama.framework/llama'*) ;;
    *)
      fail "$label: install name is not @rpath/llama.framework/llama: $out"
      return 1
      ;;
  esac
  if command -v vtool >/dev/null 2>&1; then
    if ! out=$(vtool -show-build "$bin" 2>&1); then
      fail "$label: vtool -show-build failed: $out"
      return 1
    fi
  elif command -v xcrun >/dev/null 2>&1 && xcrun -f vtool >/dev/null 2>&1; then
    if ! out=$(xcrun vtool -show-build "$bin" 2>&1); then
      fail "$label: xcrun vtool -show-build failed: $out"
      return 1
    fi
  else
    fail "$label: vtool(1) is required to prove an iOS device build"
    return 1
  fi
  if ! printf '%s\n' "$out" | grep -iE 'platform[[:space:]]+IOS([[:space:]]|$)' >/dev/null; then
    fail "$label: vtool does not report platform IOS (not a device build): $out"
    return 1
  fi
  if ! command -v nm >/dev/null 2>&1; then
    fail "$label: nm(1) is required to verify the pinned llama symbols"
    return 1
  fi
  if ! out=$(nm -g "$bin" 2>&1); then
    fail "$label: nm -g failed; could not verify exported symbols: $out"
    return 1
  fi
  if ! printf '%s\n' "$out" | grep -E '[[:xdigit:]]+[[:space:]]+T[[:space:]]+_llama_model_load_from_file$' >/dev/null; then
    fail "$label: exported llama_model_load_from_file symbol is missing"
    return 1
  fi
  ok "$label: native arm64 iOS Mach-O, install name and pinned symbol verified"
}

verify_app_executable() {
  local bin=$1 label=$2 out
  if [ ! -s "$bin" ]; then
    fail "$label is empty: $bin"
    return 1
  fi
  if [ "$(uname -s)" != Darwin ]; then
    ok "$label: non-empty (Mach-O executable proof needs macOS)"
    return 0
  fi
  if ! command -v file >/dev/null 2>&1; then
    fail "$label: file(1) is required to prove a Mach-O executable"
    return 1
  fi
  if ! out=$(file -b "$bin" 2>&1); then
    fail "$label: file(1) could not read the executable: $out"
    return 1
  fi
  case "$out" in
    *Mach-O*executable*arm64*|*Mach-O*arm64*executable*) ;;
    *)
      fail "$label: file reports '$out' (need a Mach-O arm64 executable)"
      return 1
      ;;
  esac
  ok "$label: Mach-O arm64 executable"
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
  local dir="$ROOT/app/PocketGlimmer/Resources/Models"
  local parent="$ROOT/app/PocketGlimmer/Resources"
  local found=0 f

  if [ -L "$parent" ]; then
    fail "app Resources directory is a symlink: $parent"
    return 1
  fi
  if [ -L "$dir" ]; then
    fail "app model resource directory is a symlink: $dir"
    return 1
  fi
  for f in "$dir"/*.gguf; do
    if [ ! -e "$f" ] && [ ! -L "$f" ]; then
      continue
    fi
    if [ -L "$f" ]; then
      found=1
      fail "bundled model is a symlink: $f"
      printf '     Replace it with a regular file; the app bundle must carry the model itself.\n'
      continue
    fi
    found=1
    check_model_file "$f" "bundled model" || true
  done

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
  local f=$1 label=${2:-calibration.json}
  if [ -L "$f" ]; then
    fail "$label is a symlink: $f"
    return 1
  fi
  if [ ! -f "$f" ]; then
    fail "$label missing: $f"
    return 1
  fi
  validate_with "$label" calibration "$f" "$CALIBRATION_SHA256"
}

validate_skills() {
  local f=$1 label=${2:-skills registry}
  if [ -L "$f" ]; then
    fail "$label is a symlink: $f"
    return 1
  fi
  if [ ! -f "$f" ]; then
    fail "$label missing: $f"
    return 1
  fi
  validate_with "$label" skills "$f"
}

validate_entitlements() {
  local f=$1
  if [ -L "$f" ]; then
    fail "entitlements file is a symlink: $f"
    return 1
  fi
  if [ ! -f "$f" ]; then
    fail "entitlements file missing: $f"
    return 1
  fi
  validate_with "entitlements" entitlements "$f"
}

check_source_resource_uniqueness() {
  local name expected extra
  name=calibration.json
  expected="$ROOT/$CALIBRATION_REL"
  extra=$(first_named_file "$ROOT/app/PocketGlimmer" "$name" "$expected")
  if [ -n "$extra" ]; then
    fail "duplicate source $name at $extra; remove the copy that is not $expected"
  fi
  name=builtin.json
  expected="$ROOT/app/PocketGlimmer/Resources/Skills/builtin.json"
  extra=$(first_named_file "$ROOT/app/PocketGlimmer" "$name" "$expected")
  if [ -n "$extra" ]; then
    fail "duplicate source $name at $extra; remove the copy that is not $expected"
  fi
}

validate_resources() {
  check_source_resource_uniqueness
  validate_calibration "$ROOT/$CALIBRATION_REL" || true
  validate_skills "$ROOT/app/PocketGlimmer/Resources/Skills/builtin.json" || true
  validate_entitlements "$ROOT/app/PocketGlimmer/Support/PocketGlimmer.entitlements" || true
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

check_framework_source() {
  local fw=$1
  local slice="$fw/ios-arm64/llama.framework"
  local binary="$slice/llama"
  local header="$slice/Headers/llama.h"
  local modulemap="$slice/Modules/module.modulemap"
  local h out
  local -a headers=(llama.h ggml.h ggml-opt.h ggml-alloc.h ggml-backend.h
                   ggml-metal.h ggml-cpu.h ggml-blas.h gguf.h mtmd.h mtmd-helper.h)

  if [ -L "$fw" ]; then
    fail "$FRAMEWORK_REL is a symlink; keep the built framework inside app/Frameworks"
    return 1
  fi
  if [ -L "$(dirname "$fw")" ]; then
    fail "app/Frameworks is a symlink; refusing to follow it"
    return 1
  fi
  if [ ! -d "$fw" ]; then
    fail "missing $FRAMEWORK_REL"
    printf '     Build it from a clean checkout at %s: %s framework --llama-src ~/src/llama.cpp\n' "$LLAMA_COMMIT" "$0"
    printf '     Or follow ios/MAC_DAY_RUNBOOK.md section 4.\n'
    return 1
  fi
  if [ ! -f "$fw/Info.plist" ]; then
    fail "$FRAMEWORK_REL has no Info.plist; the copy is incomplete"
    return 1
  fi
  validate_with "xcframework Info.plist" xcframework-plist "$fw/Info.plist" || return 1
  if [ ! -d "$slice" ]; then
    fail "$FRAMEWORK_REL has no ios-arm64/llama.framework device slice"
    printf '     Rebuild with: cd ~/src/llama.cpp && ./build-xcframework.sh ios-device\n'
    return 1
  fi
  if [ -L "$fw/ios-arm64" ]; then
    fail "$FRAMEWORK_REL ios-arm64 directory is a symlink; keep the built framework in place"
    return 1
  fi
  if [ -L "$slice" ]; then
    fail "$FRAMEWORK_REL device slice is a symlink; keep the built llama.framework in place"
    return 1
  fi
  if [ ! -f "$slice/Info.plist" ]; then
    fail "$FRAMEWORK_REL device slice has no Info.plist"
    return 1
  fi
  validate_with "device slice Info.plist" slice-plist "$slice/Info.plist" || return 1
  if [ -L "$binary" ]; then
    fail "$FRAMEWORK_REL device binary is a symlink; keep a real built framework"
    return 1
  fi
  if [ ! -f "$binary" ]; then
    fail "$FRAMEWORK_REL has no device slice binary (ios-arm64/llama.framework/llama)"
    printf '     Rebuild with: cd ~/src/llama.cpp && ./build-xcframework.sh ios-device\n'
    return 1
  fi
  if [ ! -s "$binary" ]; then
    fail "$FRAMEWORK_REL device binary is empty"
    return 1
  fi
  if ! out=$(run_validator macho "$binary" 2>&1); then
    fail "$FRAMEWORK_REL device binary: $out"
    return 1
  fi
  if [ "$(uname -s)" = Darwin ]; then
    verify_macho_native "$binary" "source llama.framework" || return 1
  else
    ok "source llama.framework device binary: $out (structural check; native arm64 proof needs macOS)"
  fi

  for h in "${headers[@]}"; do
    if [ ! -s "$slice/Headers/$h" ]; then
      fail "$FRAMEWORK_REL is missing or has an empty Headers/$h"
      printf '     A source xcframework must be complete; rebuild it from the pinned commit.\n'
      return 1
    fi
  done
  if ! grep -q 'llama_memory_seq_cp' "$header" || ! grep -q 'kv_unified' "$header"; then
    fail "$FRAMEWORK_REL headers do not match the pinned %s API used by LlamaCppEngine" "$LLAMA_COMMIT"
    return 1
  fi
  if [ ! -s "$modulemap" ]; then
    fail "$FRAMEWORK_REL has no non-empty Modules/module.modulemap"
    return 1
  fi
  if ! grep -q 'framework module llama' "$modulemap" ||
     ! grep -q 'umbrella "Headers"' "$modulemap" ||
     ! grep -q 'link "c++"' "$modulemap" ||
     ! grep -q 'link framework "Accelerate"' "$modulemap" ||
     ! grep -q 'link framework "Metal"' "$modulemap" ||
     ! grep -q 'link framework "Foundation"' "$modulemap"; then
    fail "$FRAMEWORK_REL module map does not match the pinned llama module"
    return 1
  fi
  ok "source llama.xcframework: complete device slice, headers, module map, and AvailableLibraries"
}

check_framework_provenance() {
  local fw=$1
  local marker="$fw/$FRAMEWORK_MARKER"
  local out
  if [ ! -f "$marker" ]; then
    incomplete "$FRAMEWORK_REL has no build provenance marker; it is only a compile-time dependency, not a verified pinned artifact"
    return 2
  fi
  if ! out=$(run_validator provenance "$marker" "$LLAMA_COMMIT" "$fw" 2>&1); then
    incomplete "$FRAMEWORK_REL provenance is not usable: $out"
    return 2
  fi
  ok "framework provenance: $out"
}

check_framework() {
  local fw=$1
  check_framework_source "$fw" || return 1
  check_framework_provenance "$fw" || return $?
}

check_framework_embedded() {
  local fw=$1
  local binary="$fw/llama"
  local out

  if [ -L "$fw" ]; then
    fail "embedded llama.framework is a symlink; the app must embed the framework itself"
    return 1
  fi
  if [ -L "$(dirname "$fw")" ]; then
    fail "built app Frameworks directory is a symlink; refusing to follow it"
    return 1
  fi
  if [ ! -d "$fw" ]; then
    fail "built app has no embedded Frameworks/llama.framework"
    return 1
  fi
  if [ ! -f "$fw/Info.plist" ]; then
    fail "embedded llama.framework has no Info.plist"
    return 1
  fi
  validate_with "embedded framework Info.plist" slice-plist "$fw/Info.plist" || return 1
  if [ -L "$binary" ]; then
    fail "embedded llama.framework binary is a symlink"
    return 1
  fi
  if [ ! -f "$binary" ]; then
    fail "built app has no embedded llama.framework binary"
    return 1
  fi
  if [ ! -s "$binary" ]; then
    fail "embedded llama.framework binary is empty"
    return 1
  fi
  if ! out=$(run_validator macho "$binary" 2>&1); then
    fail "embedded llama.framework binary: $out"
    return 1
  fi
  if [ "$(uname -s)" = Darwin ]; then
    verify_macho_native "$binary" "embedded llama.framework" || return 1
  else
    ok "embedded llama.framework: $out (structural check; native arm64 proof needs macOS)"
  fi
  ok "embedded llama.framework is complete (headers/module map are legitimately absent in a built app)"
}

framework_rebuild_hint() {
  printf '     Rebuild safely without deleting an existing framework:\n'
  printf '       mv "%s" "%s.unverified"\n' "$ROOT/$FRAMEWORK_REL" "$ROOT/$FRAMEWORK_REL"
  printf '       %s framework --root "%s" --llama-src ~/src/llama.cpp\n' "$0" "$ROOT"
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
  if command -v python3 >/dev/null 2>&1; then
    ok "python3: $(python3 --version 2>&1)"
  else
    fail "python3 not found; strict calibration/skills/plist checks need it"
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
  if [ "$SKIPS" -ne 0 ] || [ "$INCOMPLETE" -ne 0 ]; then
    printf '\nPREFLIGHT INCOMPLETE: a required artifact is skipped or not provenance-verified; this is not install-ready.\n'
    if [ "$INCOMPLETE" -ne 0 ]; then
      framework_rebuild_hint
    fi
    return 2
  fi
  printf '\nPREFLIGHT PASSED: toolchain, framework, model, calibration, skills, and entitlements are ready.\n'
  printf 'Next: core tests, then %s build-unsigned\n' "$0"
}

bundle_model() {
  local src destdir dest base tmp
  src=$(model_path)
  check_model_file "$src" "shipping model" || return 1
  base=$(basename "$SHIPPING_MODEL_REL")
  destdir="$ROOT/app/PocketGlimmer/Resources/Models"
  dest="$destdir/$base"
  if [ -L "$ROOT/app/PocketGlimmer/Resources" ]; then
    fail "refusing to write through a symlinked Resources directory: $ROOT/app/PocketGlimmer/Resources"
    return 1
  fi
  if [ -L "$destdir" ]; then
    fail "refusing to write through a symlinked model directory: $destdir"
    return 1
  fi
  mkdir -p "$destdir" || { fail "cannot create $destdir"; return 1; }

  if [ -L "$dest" ]; then
    fail "refusing to use a symlink as the bundled model: $dest"
    printf '     Remove or replace it with a regular file; this script never writes through a link.\n'
    return 1
  fi
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

  tmp="$destdir/.$base.tmp.$$"
  if [ -e "$tmp" ] || [ -L "$tmp" ]; then
    fail "temporary copy path already exists: $tmp"
    return 1
  fi
  if ! cp "$src" "$tmp"; then
    rm -f "$tmp"
    fail "copy failed: $src -> $tmp"
    return 1
  fi
  if ! check_model_file "$tmp" "staged bundled model"; then
    rm -f "$tmp"
    fail "removed the staged copy this run created; no destination was changed"
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    rm -f "$tmp"
    fail "destination appeared during the copy; refusing to overwrite $dest"
    return 1
  fi
  if ! mv "$tmp" "$dest"; then
    rm -f "$tmp"
    fail "install failed: $tmp -> $dest"
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
  local src out log rc stage_parent stage binhash srchash porcelain
  local build_marker

  section "llama.xcframework"
  if [ -e "$fw" ] || [ -L "$fw" ]; then
    if [ ! -d "$fw" ]; then
      fail "$fw exists but is not a directory"
      return 1
    fi
    check_framework "$fw"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '\nFRAMEWORK PRESENT: existing xcframework verified at pinned provenance; it was not rebuilt.\n'
      return 0
    fi
    if [ "$rc" -eq 2 ]; then
      printf '\nFRAMEWORK INCOMPLETE: the existing xcframework is structurally usable but has no trustworthy build provenance.\n'
      framework_rebuild_hint
      return 2
    fi
    printf '\nFRAMEWORK INVALID: the existing xcframework failed structural validation.\n'
    framework_rebuild_hint
    return 1
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
  if [ "$src" != "$LLAMA_COMMIT" ]; then
    fail "llama.cpp checkout is at $src; the app is pinned to $LLAMA_COMMIT"
    printf '     Do not build a different API. In your own checkout run: git fetch origin && git checkout %s\n' "$LLAMA_COMMIT"
    return 1
  fi
  if ! porcelain=$(git -C "$LLAMA_SRC" status --porcelain --untracked-files=normal 2>/dev/null); then
    fail "cannot read the git status of $LLAMA_SRC"
    return 1
  fi
  if [ -n "$porcelain" ]; then
    fail "llama.cpp checkout is not clean; refuse to build a patched source tree"
    printf '%s\n' "$porcelain" | head -10
    printf '     Commit, stash, or remove the changes above. Ignored build artifacts do not block a retry.\n'
    return 1
  fi
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
  build_marker="$ROOT/ios/.build/logs/framework-start-$(date +%Y%m%d-%H%M%S)-$$"
  log="$ROOT/ios/.build/logs/framework-$(date +%Y%m%d-%H%M%S)-$$.log"
  mkdir -p "$(dirname "$log")"
  : > "$build_marker"
  printf 'Building at pinned commit %s. The llama.cpp script will rebuild its build-* directories under %s.\n' "$LLAMA_COMMIT" "$LLAMA_SRC"
  if [ "$WITH_SIMULATOR" = 1 ]; then
    set -- ios-device ios-sim
  else
    set -- ios-device
  fi
  ( cd "$LLAMA_SRC" && ./build-xcframework.sh "$@" ) >"$log" 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "build-xcframework.sh failed (exit $rc)"
    printf '     Full log: %s\n' "$log"
    tail -30 "$log" >&2 || true
    return 1
  fi
  if [ ! -d "$out" ]; then
    fail "build-xcframework.sh finished but $out is missing"
    return 1
  fi
  if [ -z "$(find "$out" -newer "$build_marker" -print -quit 2>/dev/null)" ]; then
    fail "build-xcframework.sh exited 0 but $out was not refreshed (stale output)"
    return 1
  fi
  if [ -e "$fw" ] || [ -L "$fw" ]; then
    fail "$fw appeared while the build was running; refusing to overwrite it"
    return 1
  fi
  mkdir -p "$(dirname "$fw")" || { fail "cannot create app/Frameworks"; return 1; }
  stage_parent=$(mktemp -d "$ROOT/app/Frameworks/.llama.xcframework.staging.XXXXXX") || {
    fail "cannot create a staging directory next to $fw"
    return 1
  }
  STAGE_PARENT=$stage_parent
  stage="$stage_parent/llama.xcframework"
  if ! cp -R "$out" "$stage"; then
    fail "copy failed: $out -> $stage"
    return 1
  fi
  if ! check_framework_source "$stage"; then
    printf '\nFRAMEWORK BUILD FAILED validation; no existing framework was changed. Log: %s\n' "$log"
    return 1
  fi
  binhash=$(hash_file "$stage/ios-arm64/llama.framework/llama") || {
    fail "cannot hash the staged framework binary"
    return 1
  }
  srchash=$(run_validator framework-digest "$stage") || {
    fail "cannot digest the staged framework headers/module map"
    return 1
  }
  cat > "$stage/$FRAMEWORK_MARKER" <<EOF
{
  "commit": "$LLAMA_COMMIT",
  "clean": true,
  "device_binary_sha256": "$binhash",
  "headers_sha256": "$srchash"
}
EOF
  if ! check_framework_provenance "$stage"; then
    fail "staged framework provenance did not validate; nothing was installed"
    return 1
  fi
  if [ -e "$fw" ] || [ -L "$fw" ]; then
    fail "$fw appeared before install; refusing to overwrite it"
    return 1
  fi
  if ! mv "$stage" "$fw"; then
    fail "install failed: $stage -> $fw"
    return 1
  fi
  STAGE_PARENT=""
  rmdir "$stage_parent" 2>/dev/null || true
  printf '\nFRAMEWORK READY: %s (pinned %s, log %s)\n' "$fw" "$LLAMA_COMMIT" "$log"
}

generate_project() {
  local log
  log="$ROOT/ios/.build/logs/xcodegen-$(date +%Y%m%d-%H%M%S)-$$.log"
  mkdir -p "$(dirname "$log")"
  if ! command -v xcodegen >/dev/null 2>&1; then
    fail "xcodegen not found"
    printf '     Install it yourself: brew install xcodegen\n'
    return 1
  fi
  if ! sh "$ROOT/scripts/generate-offllama-project.sh" >"$log" 2>&1; then
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

resolve_bundle_resource() {
  local app=$1 sub=$2 name=$3
  local primary="$app/$name"
  local secondary="" have_primary=0 have_secondary=0

  RESOLVED_PATH=""
  if [ -n "$sub" ]; then
    if [ -L "$app/$sub" ]; then
      fail "built app subdirectory $sub is a symlink; refusing to follow it"
      return 1
    fi
    secondary="$app/$sub/$name"
  fi

  if [ -L "$primary" ]; then
    fail "built app resource is a symlink: $primary"
    return 1
  fi
  if [ -e "$primary" ]; then have_primary=1; fi
  if [ -n "$secondary" ]; then
    if [ -L "$secondary" ]; then
      fail "built app resource is a symlink: $secondary"
      return 1
    fi
    if [ -e "$secondary" ]; then have_secondary=1; fi
  fi

  if [ "$have_primary" = 1 ] && [ "$have_secondary" = 1 ]; then
    if cmp -s "$primary" "$secondary"; then
      warn "identical duplicate $name at bundle root and $sub/; the app loads the root copy: $primary"
      RESOLVED_PATH="$primary"
    else
      fail "conflicting duplicate $name: $primary and $secondary differ"
      return 1
    fi
  elif [ "$have_primary" = 1 ]; then
    RESOLVED_PATH="$primary"
  elif [ "$have_secondary" = 1 ]; then
    RESOLVED_PATH="$secondary"
  fi
  return 0
}

first_named_file() {
  local dir=$1 name=$2
  shift 2
  local f skip arg
  while IFS= read -r -d '' f; do
    skip=0
    for arg in "$@"; do
      if [ "$f" = "$arg" ]; then
        skip=1
        break
      fi
    done
    if [ "$skip" = 0 ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done < <(find "$dir" \( -type f -o -type l \) -name "$name" -print0 2>/dev/null)
  return 0
}

unsupported_resource_copy() {
  local app=$1 sub=$2 name=$3
  if [ -n "$sub" ]; then
    first_named_file "$app" "$name" "$app/$name" "$app/$sub/$name"
  else
    first_named_file "$app" "$name" "$app/$name"
  fi
}

check_bundled_app_models() {
  local app=$1
  local found=0 f dir nested
  for dir in "$app" "$app/Models"; do
    if [ -L "$dir" ]; then
      fail "built app model directory is a symlink: $dir"
      return 1
    fi
    if [ ! -d "$dir" ]; then
      continue
    fi
    for f in "$dir"/*.gguf; do
      if [ ! -e "$f" ] && [ ! -L "$f" ]; then
        continue
      fi
      if [ -L "$f" ]; then
        found=1
        fail "bundled model is a symlink: $f"
        printf '     Rebuild the app with a regular file; the script never follows a model link.\n'
        continue
      fi
      found=1
      check_model_file "$f" "bundled model" || true
    done
  done

  if [ "$found" = 0 ]; then
    nested=$(first_named_file "$app" '*.gguf')
    if [ -n "$nested" ]; then
      fail "built app has no .gguf where AppModel.findModel looks (bundle root or Models/)"
      printf '     Found an unusable nested copy at %s; the app does not search there.\n' "$nested"
    elif [ "$REQUIRE_MODEL" = 1 ]; then
      fail "no .gguf in the built app (--require-model)"
    elif [ "$ALLOW_NO_MODEL" = 1 ]; then
      skip "no .gguf in the built app; compile-only request (--allow-no-model), not install-ready"
    else
      skip "no .gguf in the built app; a release app must bundle the verified model (pass --allow-no-model only for compile-only checks)"
    fi
  fi
}

check_app() {
  local app=$1
  local name cal skills

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
  if [ -L "$app/$name" ]; then
    fail "app executable is a symlink: $app/$name"
    return 1
  fi
  if [ ! -f "$app/$name" ]; then
    fail "app executable missing: $app/$name"
    return 1
  fi
  verify_app_executable "$app/$name" "app executable" || return 1
  if ! plist_true "$app/Info.plist" UIFileSharingEnabled; then
    fail "Info.plist does not enable UIFileSharingEnabled; Finder/Files model copy would not work"
    return 1
  fi
  ok "app bundle: $app (executable $name, Files sharing enabled)"

  resolve_bundle_resource "$app" "Models" "calibration.json" || return 1
  cal="$RESOLVED_PATH"
  if [ -z "$cal" ]; then
    local extra
    extra=$(unsupported_resource_copy "$app" "Models" "calibration.json")
    if [ -n "$extra" ]; then
      fail "built app has calibration.json only at an unsupported path: $extra"
      printf '     AppModel loads the bundle root, then Models/; XcodeGen copies Resources/Models flat.\n'
    else
      fail "built app has no calibration.json (looked at bundle root and Models/)"
      printf '     Check that app/PocketGlimmer/Resources/Models/calibration.json is in Copy Bundle Resources.\n'
    fi
  else
    validate_calibration "$cal" "built app calibration" || true
  fi

  resolve_bundle_resource "$app" "Skills" "builtin.json" || return 1
  skills="$RESOLVED_PATH"
  if [ -z "$skills" ]; then
    local extra
    extra=$(unsupported_resource_copy "$app" "Skills" "builtin.json")
    if [ -n "$extra" ]; then
      fail "built app has builtin.json only at an unsupported path: $extra"
      printf '     SkillSetup loads the bundle root, then Skills/.\n'
    else
      fail "built app has no builtin.json skills registry"
    fi
  else
    validate_skills "$skills" "built app skills registry" || true
  fi

  check_framework_embedded "$app/Frameworks/llama.framework" || true
  check_bundled_app_models "$app"

  if [ "$FAILS" -ne 0 ]; then
    printf '\nAPP BUNDLE FAILED: %d required check(s) failed.\n' "$FAILS"
    return 1
  fi
  if [ "$SKIPS" -ne 0 ] || [ "$INCOMPLETE" -ne 0 ]; then
    printf '\nAPP BUNDLE INCOMPLETE: %d check(s) skipped and %d not verified; this is not install-ready.\n' \
      "$SKIPS" "$INCOMPLETE"
    return 2
  fi
  printf '\nAPP BUNDLE PASSED: calibration, skills, embedded framework, and bundled model are in place.\n'
}

cmd_check_app() {
  local rc
  if [ -z "$APP_OPT" ]; then
    die "check-app needs --app PATH"
  fi
  section "Built app"
  check_app "$(abs_path "$APP_OPT")"
  rc=$?
  if [ "$FAILS" -ne 0 ]; then
    return 1
  fi
  return "$rc"
}

cmd_prepare() {
  section "Resources"
  if ! require_darwin; then return 1; fi
  check_model_source || true
  if [ "$BUNDLE_MODEL" = 1 ] && [ "$FAILS" -eq 0 ]; then
    section "Bundle model"
    bundle_model || true
  fi
  if [ "$BUNDLE_MODEL" = 0 ] || [ "$FAILS" -eq 0 ]; then
    check_bundled_models || true
  fi
  validate_resources
  check_framework "$ROOT/$FRAMEWORK_REL" || true

  if [ "$FAILS" -ne 0 ]; then
    printf '\nPREPARE FAILED: fix the checks above. Nothing was signed or installed.\n'
    return 1
  fi

  section "Xcode project"
  generate_project || return 1

  if [ "$SKIPS" -ne 0 ] || [ "$INCOMPLETE" -ne 0 ]; then
    printf '\nPREPARE INCOMPLETE: a required artifact is skipped or not provenance-verified; this is not install-ready.\n'
    if [ "$INCOMPLETE" -ne 0 ]; then
      framework_rebuild_hint
    fi
    return 2
  fi
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
  if ! command -v xcodegen >/dev/null 2>&1; then
    fail "xcodegen not found; install it (this command always regenerates the project)"
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

  section "Xcode project"
  generate_project || return 1

  dd=${DERIVED_DATA:-"$ROOT/ios/.build/DerivedData"}
  dd=$(abs_path "$dd")
  case "$dd" in
    /|"") fail "refusing an unsafe DerivedData path: '$dd'"; return 1 ;;
  esac
  mkdir -p "$dd"
  app="$dd/Build/Products/Release-iphoneos/PocketGlimmer.app"
  if [ -e "$app" ] || [ -L "$app" ]; then
    printf 'Removing the previous build product so a stale .app cannot pass: %s\n' "$app"
    rm -rf "$app" || { fail "cannot remove the previous build product: $app"; return 1; }
  fi
  if [ -e "$app" ] || [ -L "$app" ]; then
    fail "previous build product still exists: $app"
    return 1
  fi
  log="$ROOT/ios/.build/logs/unsigned-release-$(date +%Y%m%d-%H%M%S)-$$.log"
  mkdir -p "$(dirname "$log")"

  printf 'xcodebuild -project app/PocketGlimmer.xcodeproj -scheme PocketGlimmer -configuration Release\n'
  printf '  -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO\n'
  run_logged "$log" \
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
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "xcodebuild failed (exit $rc)"
    printf '     Full log: %s\n' "$log"
    tail -40 "$log" >&2 || true
    grep -qiE 'not installed|unable to find a destination|downloadPlatform' "$log" && \
      printf '     If the iOS platform is missing: Xcode > Settings > Components (or xcodebuild -downloadPlatform iOS, your choice).\n'
    return 1
  fi
  ok "xcodebuild finished"

  if [ -L "$app" ] || [ ! -d "$app" ]; then
    fail "xcodebuild exited 0 but did not produce a fresh app bundle at $app"
    printf '     The previous product was removed before the build; a stale or skipped build cannot pass.\n'
    printf '     Full log: %s\n' "$log"
    return 1
  fi
  section "Built app"
  check_app "$app"
  rc=$?
  if [ "$rc" -eq 1 ] || [ "$FAILS" -ne 0 ]; then
    printf '     Build log: %s\n' "$log"
    return 1
  fi
  if [ "$SKIPS" -ne 0 ] || [ "$INCOMPLETE" -ne 0 ]; then
    printf '\nUNSIGNED COMPILE PASSED; RELEASE INCOMPLETE: a required artifact is skipped or not provenance-verified.\n'
    if [ "$INCOMPLETE" -ne 0 ]; then
      printf 'The xcframework has no verified pin provenance; rebuild it before treating this as release proof.\n'
      framework_rebuild_hint
    fi
    printf 'This is not signed, not installed, and not run on a device.\n'
    printf 'App: %s\nLog: %s\n' "$app" "$log"
    return 2
  fi
  printf '\nUNSIGNED BUILD PASSED (compile/link and bundle resources only).\n'
  printf 'This is not signed, not installed, and not run on a device.\n'
  printf 'App: %s\nLog: %s\n' "$app" "$log"
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
