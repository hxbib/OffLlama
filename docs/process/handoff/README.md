# handoff/

Our own non-repo hackathon work, copied in for backup.

- `mac-day/`: the bundle staged for Mac day. `pg.tgz` on the box was a tarball of this very repo
  (already covered by git history) and the `.gguf` weights (771 MB) are excluded, so only
  `SHA256SUMS` is kept so the exact artifacts can be verified later.
- `kickoff/`: kickoff transcripts, summary, slide OCR, frame OCR text and the capture scripts.
  Excluded: recordings (`*.mp4`, `*.ts`, `*.wav`, `seg/`), frame/scene JPEGs, logs, and `m3u8.txt`.
  The signed Vimeo stream URL is redacted in `follow.sh` / `backfill.sh`.

Third-party papers (/workspace/papers) are intentionally not included.
