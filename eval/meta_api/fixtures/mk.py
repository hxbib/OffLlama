"""Regenerates the smoke-test fixtures (no downloads, no real people or documents).

    /tmp/gencode/mplenv/bin/python eval/meta_api/fixtures/mk.py      # any python with matplotlib + pillow
    ffmpeg -f lavfi -i "flite=text='Remind me to call Mom at seven tonight.':voice=slt" -ar 16000 -ac 1 -c:a pcm_s16le remind.wav
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from PIL import Image

OUT = Path(__file__).resolve().parent

# bars.jpg: 640x400 bar chart, Thu (9) is the tallest bar.
fig, ax = plt.subplots(figsize=(6.4, 4.0), dpi=100)
ax.bar(["Mon", "Tue", "Wed", "Thu", "Fri"], [3, 7, 4, 9, 5], color=["#4C78A8"] * 3 + ["#E45756"] + ["#4C78A8"])
ax.set_title("Steps (thousands)"); ax.set_ylabel("k steps")
fig.tight_layout(); fig.savefig(OUT / "bars.png"); plt.close(fig)

# whiteboard.jpg: 800x500 whiteboard with five yellow sticky notes.
fig = plt.figure(figsize=(8, 5), dpi=100); ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, 800); ax.set_ylim(500, 0); ax.axis("off")
ax.add_patch(FancyBboxPatch((20, 20), 760, 460, boxstyle="round,pad=4", fc="#f7f7f5", ec="#888", lw=3))
for x, y, t in [(70, 70, "Buy oat milk"), (300, 90, "Call Mom 7pm"), (540, 60, "Ship demo"), (120, 290, "Book dentist"), (420, 300, "Pay rent Fri")]:
    ax.add_patch(plt.Rectangle((x, y), 170, 130, fc="#FFE45C", ec="#d9b800", lw=1.5))
    ax.text(x + 85, y + 65, t, ha="center", va="center", fontsize=14, family="DejaVu Sans")
ax.text(400, 470, "WEEK PLAN", ha="center", fontsize=16, color="#333")
fig.savefig(OUT / "whiteboard.png"); plt.close(fig)

for name in ("bars", "whiteboard"):
    png = OUT / f"{name}.png"
    Image.open(png).convert("RGB").save(OUT / f"{name}.jpg", quality=80)
    png.unlink()
