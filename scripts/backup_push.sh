#!/usr/bin/env bash
# Box half of the GitHub backup. Builds /workspace/pg.bundle (incremental if possible).
# The copy-to-PC and push steps are agent tool calls; see scripts/BACKUP.md.
# Idempotent: never rewrites history, never force-pushes.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/workspace/pg.bundle}"
cd "$REPO"
git config user.name  "Sadman Habib"
git config user.email "hxbib@users.noreply.github.com"
# Optional: commit pending tracked/untracked (gitignored files stay out) when BACKUP_AUTOCOMMIT=1
if [ "${BACKUP_AUTOCOMMIT:-0}" = 1 ] && [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -qm "backup: autosave $(date '+%Y-%m-%d %H:%M %Z')"
fi
# Incremental: exclude what the PC already has (recorded by the last successful push).
BASE="$(git rev-parse -q --verify refs/backup/pushed 2>/dev/null || true)"
if [ -n "$BASE" ] && [ "$(git rev-list --count --branches --tags ^"$BASE")" = 0 ]; then
  echo "NOTHING_NEW (all refs already in refs/backup/pushed=$BASE)"; exit 0
fi
rm -f "$OUT"
if [ -n "$BASE" ]; then
  git bundle create "$OUT" --branches --tags "^$BASE"
else
  git bundle create "$OUT" --branches --tags
fi
git bundle verify "$OUT" >/dev/null 2>&1 || git bundle list-heads "$OUT" >/dev/null
echo "BUNDLE=$OUT HEAD=$(git rev-parse HEAD) COUNT=$(git rev-list --count HEAD)"
echo "Next: CopyFromBox $OUT -> PC C:\\src\\pg.bundle, then run the PC step in scripts/BACKUP.md,"
echo "then on the box: git update-ref refs/backup/pushed HEAD"
