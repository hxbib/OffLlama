#!/bin/sh
# Generates app/PocketGlimmer.xcodeproj from the tracked app/project.yml without touching
# app/PocketGlimmer/Support/Info.plist (a user-preserved file that XcodeGen would otherwise overwrite).
# The generated Info.plist goes to ios/.build/generated/Info.plist (gitignored, stable, rewritten every run) and the
# preserved plist is excluded from the source copy list so it is not also bundled.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
generated_rel="../ios/.build/generated/Info.plist"
mkdir -p "$root/ios/.build/generated"

lock="$root/ios/.build/generate-project.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "error: another project generation is running (remove $lock only if no generator is active)" >&2
  exit 1
fi
spec=$(mktemp "$root/app/.offllama-spec.XXXXXX")
trap 'rm -f "$spec"; rmdir "$lock" 2>/dev/null || true' EXIT

python3 - "$root/app/project.yml" "$spec" "$generated_rel" <<'PY'
import sys
source, target, plist = sys.argv[1:]
s = open(source).read()
edits = [
    ('- path: PocketGlimmer      # Resources/Models/*.gguf + calibration.json are copied as bundle resources',
     '- path: PocketGlimmer\n        excludes: [Support/Info.plist]'),
    ('path: PocketGlimmer/Support/Info.plist', 'path: ' + plist),
]
for old, new in edits:
    if s.count(old) != 1:
        sys.exit("error: app/project.yml no longer contains exactly one `%s`; update scripts/generate-offllama-project.sh" % old.splitlines()[0])
    s = s.replace(old, new)
open(target, "w").write(s)
PY

cd "$root/app"
xcodegen generate --spec "$spec"
if ! grep -q "ios/.build/generated/Info.plist" PocketGlimmer.xcodeproj/project.pbxproj; then
  echo "error: generated project does not use $generated_rel" >&2
  exit 1
fi
[ -s "$root/ios/.build/generated/Info.plist" ] || { echo "error: generated Info.plist missing" >&2; exit 1; }
echo "generated app/PocketGlimmer.xcodeproj (Info.plist: ios/.build/generated/Info.plist)"
