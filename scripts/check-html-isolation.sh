#!/bin/sh
# Builds and runs the real-WebKit isolation check (macOS WebKit, same IsolatedHTMLController source as the app).
# Passes only if the harness assertions pass AND the local server saw no request from any isolated page.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out=${1:-$(mktemp -d "${TMPDIR:-/tmp}/offllama-html-isolation.XXXXXX")}
mkdir -p "$out"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
swiftc -O -o "$out/check" \
  "$root/core/Sources/PocketCore/RichReply.swift" \
  "$root/app/PocketGlimmer/Views/HTMLIsolation.swift" \
  "$root/app/Tests/HTMLIsolation/main.swift" \
  -framework WebKit -framework AppKit 2>"$out/build.log" || { cat "$out/build.log"; exit 2; }
python3 - "$out" <<'PY' &
import http.server, socketserver, sys, os
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def _log(self):
        with open(os.path.join(out, "requests.log"), "a") as f: f.write(self.path + "\n")
        self.send_response(200); self.send_header("Content-Type", "text/plain"); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")
    do_GET = do_POST = do_HEAD = _log
    def log_message(self, *a): pass
s = socketserver.TCPServer(("127.0.0.1", 0), H)
open(os.path.join(out, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
PY
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
while [ ! -s "$out/port" ]; do sleep 0.1; done
: > "$out/requests.log"
status=0
"$out/check" "$(cat "$out/port")" "$out/report.txt" || status=$?
cat "$out/report.txt"
echo "--- server request log (control- and ablate- paths are expected, anything else is an escape)"
sort "$out/requests.log" | uniq -c
escapes=$(grep -v -E '^/(control|ablate)-' "$out/requests.log" | wc -l | tr -d ' ')
controls=$(grep -c '^/control-' "$out/requests.log" || true)
ablated=$(grep -c '^/ablate-' "$out/requests.log" || true)
echo "escapes=$escapes controlRequests=$controls ablatedRequests=$ablated"
[ "$escapes" = 0 ] && [ "$controls" -gt 0 ] && [ "$ablated" -gt 0 ] && [ "$status" = 0 ] || { echo "HTML ISOLATION CHECK FAILED"; exit 1; }
echo "HTML ISOLATION CHECK PASSED (artifacts: $out)"
