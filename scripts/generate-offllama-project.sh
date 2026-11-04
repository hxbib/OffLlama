#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
spec="$root/app/.offllama-project-build.yml"
plist="${TMPDIR:-/tmp}/offllama-build-info.plist"
trap 'rm -f "$spec"' EXIT
python3 - "$root/app/project.yml" "$spec" "$plist" <<'PY'
import sys
source, target, plist = sys.argv[1:]
s = open(source).read()
s = s.replace('- path: PocketGlimmer      # Resources/Models/*.gguf + calibration.json are copied as bundle resources', '- path: PocketGlimmer\n        excludes: [Support/Info.plist]')
s = s.replace('path: PocketGlimmer/Support/Info.plist', 'path: ' + plist)
open(target, 'w').write(s)
PY
cd "$root/app"
xcodegen generate --spec "$spec"
