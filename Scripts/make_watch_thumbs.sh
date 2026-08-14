#!/usr/bin/env bash
#
# Builds the small artwork thumbnails the Apple Watch app ships for its
# reward screen, from the full-size paintings the iPhone app bundles.
#
# The iPhone's Resources/Artworks folder is ~20 MB across 37 JPGs, which has
# no business inside a watch bundle. The watch only ever shows one painting
# at a time, and only once a cycle is complete, so a long edge of 320 px is
# plenty — the whole set lands at well under 1 MB.
#
# Every file is derived from what is already on disk rather than from a
# hardcoded list, so a new pack needs no edit here: fetch the paintings, run
# this, done. Names are preserved exactly, because the app resolves a
# painting through Artwork.assetName via Bundle.main.path(forResource:).
#
# Uses sips, which ships with macOS — no dependencies to install.
#
# Usage:  ./Scripts/make_watch_thumbs.sh [long_edge] [quality]
#         long_edge defaults to 320 (fits the 396 pt 45mm display with room
#         for the frame inset), quality to 70.
#
set -euo pipefail

LONG_EDGE="${1:-320}"
QUALITY="${2:-70}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/FocusPiece/Resources/Artworks"
DEST="$ROOT/FocusPieceWatch/Resources/Thumbs"

if [ ! -d "$SRC" ]; then
  echo "error: $SRC does not exist — run ./Scripts/fetch_artworks.sh first." >&2
  exit 1
fi

shopt -s nullglob
sources=("$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.png)
if [ ${#sources[@]} -eq 0 ]; then
  echo "error: no paintings in $SRC — run ./Scripts/fetch_artworks.sh first." >&2
  exit 1
fi

mkdir -p "$DEST"

written=0
skipped=0
for src in "${sources[@]}"; do
  base="$(basename "$src")"
  base="${base%.*}"
  out="$DEST/$base.jpg"

  # Skip work that is already done and newer than its source, so re-running
  # after adding a single pack stays quick.
  if [ -f "$out" ] && [ "$out" -nt "$src" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  if sips -Z "$LONG_EDGE" -s format jpeg -s formatOptions "$QUALITY" \
       "$src" --out "$out" >/dev/null 2>&1; then
    written=$((written + 1))
  else
    echo "warning: could not convert $base — skipping." >&2
  fi
done

total="$(du -sh "$DEST" | cut -f1)"
echo "Watch thumbnails: ${written} written, ${skipped} already current."
echo "  ${DEST}  (${total} total, long edge ${LONG_EDGE}px, quality ${QUALITY})"
echo
echo "Add the folder to the FocusPieceWatch target in Xcode if it is not"
echo "already inside the target's synchronized group."
