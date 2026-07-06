#!/usr/bin/env bash
#
# Downloads the Public-Domain paintings from Wikimedia Commons and places
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
  # Basis-Sammlung
  "Almond_blossom.jpg"
  "Tsunami_by_hokusai_19th_century.jpg"
  "Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg"
  "Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog.jpg"
  "Red_Fuji_southern_wind_clear_morning.jpg"
  "Claude_Monet,_Impression,_soleil_levant.jpg"
  "Gustav_Klimt_016.jpg"
  "Pieter_Bruegel_the_Elder-_The_Harvesters_-_Google_Art_Project.jpg"
  "Meisje_met_de_parel.jpg"
  "Edvard_Munch,_1893,_The_Scream,_oil,_tempera_and_pastel_on_cardboard,_91_x_73_cm,_National_Gallery_of_Norway.jpg"
  "Vincent_van_Gogh_-_Wheat_Field_with_Cypresses_-_Google_Art_Project.jpg"
  "Claude_Monet_-_Water_Lilies_-_Google_Art_Project_(462013).jpg"
  # Store-Paket: Japanische Meister
  "Hiroshige-53-Stations-Hoeido-46-Shono-Edo-Tokyo-M-01.jpg"
  "De_pruimenboomgaard_te_Kameido-Rijksmuseum_RP-P-1956-743.jpeg"
  "Hiroshige_Atake_sous_une_averse_soudaine.jpg"
  "Katsushika_Hokusai,_Japanese_-_Pilgrims_at_Kirifuri_Waterfall_on_Mount_Kurokami_in_Shimotsuke_Province_-_Google_Art_Project.jpg"
  # Store-Paket: Impressionisten & Licht
  "Claude_Monet_-_Woman_with_a_Parasol_-_Madame_Monet_and_Her_Son_-_Google_Art_Project.jpg"
  "Pierre-Auguste_Renoir,_Le_Moulin_de_la_Galette.jpg"
  "Gustave_Caillebotte_-_Paris_Street;_Rainy_Day_-_Google_Art_Project.jpg"
  "Edgar_Degas_-_The_Ballet_Class_-_Google_Art_Project.jpg"
  # Store-Paket: Alte Meister
  "Sandro_Botticelli_-_La_nascita_di_Venere_-_Google_Art_Project_-_edited.jpg"
  "Mona_Lisa,_by_Leonardo_da_Vinci,_from_C2RMF_retouched.jpg"
  "The_Night_Watch_-_HD.jpg"
  "Johannes_Vermeer_-_Het_melkmeisje_-_Google_Art_Project.jpg"
  # Store-Paket: Aufbruch zur Moderne
  "Vassily_Kandinsky,_1913_-_Composition_7.jpg"
  "La_Bohémienne_endormie.jpg"
  "Vincent_van_Gogh_-_Self-Portrait_-_Google_Art_Project_(454045).jpg"
  "Gustav_Klimt_046.jpg"
)

# Wikimedia blocks bare tool UAs (403); a Mozilla-prefixed descriptive UA passes.
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 FocusPieceFetch/1.0"

OK=0
FAIL=0
for name in "${FILES[@]}"; do
  url="https://commons.wikimedia.org/wiki/Special:FilePath/${name}?width=${WIDTH}"
  out="$DEST/${name}"
  echo "→ ${name}"
  # Einzelne Fehltreffer (umbenannte Commons-Dateien) brechen den Lauf nicht
  # ab — die App zeigt für fehlende Bilder ohnehin einen Platzhalter.
  if curl -fsSL -A "$UA" -o "$out" "$url"; then
    OK=$((OK + 1))
  else
    echo "   ! Download fehlgeschlagen — wird übersprungen."
    rm -f "$out"
    FAIL=$((FAIL + 1))
  fi
done

echo
echo "Done. ${OK} paintings saved to:"
echo "  $DEST"
[ "$FAIL" -gt 0 ] && echo "(${FAIL} Downloads fehlgeschlagen — Platzhalter greifen.)"
echo "Re-build in Xcode to bundle them."
