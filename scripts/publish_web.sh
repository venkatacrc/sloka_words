#!/usr/bin/env bash
# Copies the web app and the current deck into the bhakti repo as flashcards/, which
# GitHub Pages serves at https://venkatacrc.github.io/bhakti/flashcards/.
# Usage: scripts/publish_web.sh [path/to/bhakti]   (default ~/code/bhakti)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BHAKTI="${1:-$HOME/code/bhakti}"
DEST="$BHAKTI/flashcards"
DECK="$ROOT/app/Sources/SlokaWords/Resources/words.json"

[ -d "$BHAKTI/.git" ] || { echo "Not a git repo: $BHAKTI" >&2; exit 1; }

if [ ! -f "$ROOT/web/icons/maskable-512.png" ]; then
    swift "$ROOT/scripts/make_icon.swift" --web "$ROOT/web/icons"
fi

rm -rf "$DEST"
mkdir -p "$DEST/icons"
cp "$ROOT"/web/{index.html,app.css,app.js,manifest.webmanifest} "$DEST/"
cp "$ROOT"/web/icons/*.png "$DEST/icons/"

# The web app doesn't need the repo locations the Mac app uses for pushing edits.
python3 - "$DECK" "$DEST/words.json" <<'PY'
import json, sys
deck = json.load(open(sys.argv[1], encoding='utf-8'))
for v in deck.get('verses', []):
    v.pop('file', None)
    v.pop('block', None)
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(deck, f, ensure_ascii=False, separators=(',', ':'))
PY

# A new cache name makes installed copies drop the old files.
VERSION="$(cat "$DEST"/*.* "$ROOT/web/sw.js" | shasum | cut -c1-10)"
sed "s/sloka-words-dev/sloka-words-$VERSION/" "$ROOT/web/sw.js" > "$DEST/sw.js"

echo "Published to $DEST (version $VERSION)"
echo "Commit and push bhakti to put it online."
