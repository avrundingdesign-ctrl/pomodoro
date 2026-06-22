#!/usr/bin/env bash
#
# Downloads the eight Public-Domain paintings from Wikimedia Commons and places
# them next to the app's bundled resources (FocusPiece/Resources/Artworks). The
# app loads them by base name at runtime; until they are present it shows a
# graceful placeholder.
#
# Usage:  ./Scripts/fetch_artworks.sh [width]
#         width defaults to 1200 (good balance of quality / size for mobile).
#
set -euo pipefail

WIDTH="${1:-1200}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/FocusPiece/Resources/Artworks"
mkdir -p "$DEST"

# base-name : Wikimedia file name
FILES=(
  "Almond_blossom.jpg"
  "Tsunami_by_hokusai_19th_century.jpg"
  "Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg"
  "Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg"
  "Red_Fuji_southern_wind_clear_morning.jpg"
  "Claude_Monet,_Impression,_soleil_levant.jpg"
  "Gustav_Klimt_016.jpg"
  "Pieter_Bruegel_the_Elder-_The_Harvesters_-_Google_Art_Project.jpg"
)

UA="FocusPiece/1.0 (educational; contact: you@example.com)"

for name in "${FILES[@]}"; do
  url="https://commons.wikimedia.org/wiki/Special:FilePath/${name}?width=${WIDTH}"
  out="$DEST/${name}"
  echo "→ ${name}"
  curl -fsSL -A "$UA" -o "$out" "$url"
done

echo
echo "Done. ${#FILES[@]} paintings saved to:"
echo "  $DEST"
echo "Re-build in Xcode to bundle them."
