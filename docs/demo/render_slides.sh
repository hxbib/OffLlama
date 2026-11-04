#!/usr/bin/env bash
# Render docs/demo/slides.html to docs/img/slide_01.png ... slide_11.png (1920x1080).
# Splits the deck into one HTML per slide (docs/demo/slides/slide_NN.html) because headless
# Chrome's --screenshot ignores #fragments, then screenshots each one.
# Usage (repo root): bash docs/demo/render_slides.sh   [CHROME=/path/to/chrome]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
CHROME="${CHROME:-$(command -v google-chrome || command -v chromium || echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")}"
python3 - <<'PY'
import re, pathlib
src = pathlib.Path("docs/demo/slides.html").read_text()
head = src.split("<body>")[0]
head = head.replace("margin:0 auto 40px}", "margin:0}", 1)
secs = re.findall(r'(<section id="slide(\d+)".*?</section>)', src, re.S)
out = pathlib.Path("docs/demo/slides"); out.mkdir(parents=True, exist_ok=True)
for html, n in secs:
    html = html.replace('src="../img/', 'src="../../img/')
    (out / f"slide_{int(n):02d}.html").write_text(head + '<body style="margin:0;overflow:hidden">\n' + html + "\n</body></html>\n")
print(f"wrote {len(secs)} slide files")
PY
for f in docs/demo/slides/slide_*.html; do
  n="$(basename "$f" .html)"
  "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1920,1080 --screenshot="$PWD/docs/img/$n.png" "file://$PWD/$f" >/dev/null 2>&1
  printf '%s %s bytes\n' "docs/img/$n.png" "$(wc -c < "docs/img/$n.png")"
done
