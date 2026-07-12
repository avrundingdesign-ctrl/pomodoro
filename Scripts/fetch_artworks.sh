#!/usr/bin/env bash
#
# Downloads the Public-Domain paintings from Wikimedia Commons and places them
# next to the app's bundled resources (FocusPiece/Resources/Artworks). The app
# loads them by base name at runtime; until they are present it shows a
# graceful placeholder.
#
# Covers the free "Klassiker" set and the purchasable sets (Impressionen,
# Goldenes Zeitalter, Nachtstücke). A file that fails to download is skipped
# with a warning so one renamed Commons file never breaks the rest.
#
# Usage:  ./Scripts/fetch_artworks.sh [width]
#         width defaults to 1200 (good balance of quality / size for mobile).
#
set -euo pipefail

WIDTH="${1:-1200}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/FocusPiece/Resources/Artworks"
mkdir -p "$DEST"

# Wikimedia file names; the base name (minus .jpg) is the app's assetName.
FILES=(
  # Klassiker (frei)
  "Almond_blossom.jpg"
  "Tsunami_by_hokusai_19th_century.jpg"
  "Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg"
  "Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg"
  "Red_Fuji_southern_wind_clear_morning.jpg"
  "Claude_Monet,_Impression,_soleil_levant.jpg"
  "Gustav_Klimt_016.jpg"
  "Pieter_Bruegel_the_Elder-_The_Harvesters_-_Google_Art_Project.jpg"
  # Set: Impressionen
  "Claude_Monet_-_Water_Lilies_-_1906,_Ryerson.jpg"
  "Pierre-Auguste_Renoir,_Le_Moulin_de_la_Galette.jpg"
  "Gustave_Caillebotte_-_Paris_Street;_Rainy_Day_-_Google_Art_Project.jpg"
  "Claude_Monet_-_Woman_with_a_Parasol_-_Madame_Monet_and_Her_Son_-_Google_Art_Project.jpg"
  # Set: Goldenes Zeitalter
  "1665_Girl_with_a_Pearl_Earring.jpg"
  "Johannes_Vermeer_-_Het_melkmeisje_-_Google_Art_Project.jpg"
  "Rembrandt_van_Rijn_-_Self-Portrait_-_Google_Art_Project.jpg"
  "Vermeer-view-of-delft.jpg"
  # Set: Nachtstücke
  "Vincent_Willem_van_Gogh_-_Cafe_Terrace_at_Night_(Yorck).jpg"
  "Caspar_David_Friedrich_-_Mondaufgang_am_Meer_-_Google_Art_Project.jpg"
  "James_Abbott_McNeill_Whistler_-_Nocturne_in_Black_and_Gold_-_The_Falling_Rocket_-_Google_Art_Project.jpg"
  "Starry_Night_Over_the_Rhone.jpg"
)

UA="FocusPiece/1.0 (educational; contact: you@example.com)"

ok=0; failed=()
for name in "${FILES[@]}"; do
  url="https://commons.wikimedia.org/wiki/Special:FilePath/${name}?width=${WIDTH}"
  out="$DEST/${name}"
  echo "→ ${name}"
  if curl -fsSL -A "$UA" -o "$out" "$url"; then
    ok=$((ok + 1))
  else
    rm -f "$out"
    failed+=("$name")
    echo "  ⚠️  Download fehlgeschlagen — übersprungen (App zeigt Platzhalter)."
  fi
done

echo
echo "Done. ${ok}/${#FILES[@]} paintings saved to:"
echo "  $DEST"
if [ ${#failed[@]} -gt 0 ]; then
  echo "Skipped (check the Commons file name, then re-run):"
  printf '  - %s\n' "${failed[@]}"
fi
echo "Re-build in Xcode to bundle them."
