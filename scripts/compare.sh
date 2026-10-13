#!/usr/bin/env bash
# Render one snapshot state and diff it against its reference PNG.
#
#   scripts/compare.sh <state-name> [-q]
#
# Reference: screenshots/<name>.png, else screenshots/prototype/<name>.png, else screenshots/artboards/<name>.png.
# Fragment states (`<reference>@<part>`, e.g. 03-notes-todo@subnav) render one component at its exact position and
# compare only that region of `<reference>`; the region comes from `MyWorkDock --snapshot region <name>`.
# Writes diff/<name>-ours.png (our full render), diff/<name>-diff.png (differences in red), diff/<name>-side.png (ours | reference);
# for fragments the diff and side images show just the region.
# Differing pixels = ImageMagick `compare -metric AE -fuzz 2%`.
# FONT=system renders UI text in SF Pro instead of Geist. -q prints only "<differing-px> <total-px>" (used by compare-all.sh). NO_BUILD=1 skips xcodebuild.
# Exit: 0 ok, 2 no reference, 3 render failed / unknown state, 4 size mismatch, 5 compare failed.
set -euo pipefail
cd "$(dirname "$0")/.."

name=${1:?usage: scripts/compare.sh <state-name> [-q]}
quiet=0
[ "${2:-}" = "-q" ] && quiet=1
app=build/Build/Products/Debug/MyWorkDock.app/Contents/MacOS/MyWorkDock
mkdir -p diff

if [ -z "${NO_BUILD:-}" ]; then
  [ -d MyWorkDock.xcodeproj ] || xcodegen generate >/dev/null
  xcodebuild -project MyWorkDock.xcodeproj -scheme MyWorkDock -configuration Debug \
    -derivedDataPath build build -quiet >diff/build.log 2>&1 || { tail -30 diff/build.log >&2; exit 3; }
fi

base=${name%%@*}
ref=
for d in screenshots screenshots/prototype screenshots/artboards; do
  if [ -f "$d/$base.png" ]; then ref=$d/$base.png; break; fi
done
[ -n "$ref" ] || { echo "no reference PNG for '$base' under screenshots/" >&2; exit 2; }

ours=diff/$name-ours.png
rm -f "$ours"
if ! "$app" --snapshot "$name" --out "$ours" ${FONT:+--font "$FONT"} 2>diff/"$name"-render.log; then
  grep -v -e linkd -e 'Process Instance Registry' diff/"$name"-render.log >&2 || true
  exit 3
fi

size_ours=$(identify -format '%wx%h' "$ours")
size_ref=$(identify -format '%wx%h' "$ref")
[ "$size_ours" = "$size_ref" ] || { echo "$name: SIZE MISMATCH ours=$size_ours ref=$size_ref" >&2; exit 4; }

# Fragments: crop both images to the fragment's region and compare those.
cmp_ours=$ours
cmp_ref=$ref
if [ "$base" != "$name" ]; then
  region=$("$app" --snapshot region "$name" 2>/dev/null) || { echo "$name: no region" >&2; exit 3; }
  IFS=, read -r rx ry rw rh <<<"$region"
  cmp_ours=diff/$name-ours-region.png
  cmp_ref=diff/$name-ref-region.png
  magick "$ours" -crop "${rw}x${rh}+${rx}+${ry}" +repage "$cmp_ours"
  magick "$ref" -crop "${rw}x${rh}+${rx}+${ry}" +repage "$cmp_ref"
  size_ref=${rw}x${rh}
fi

# compare exits 1 when the images differ and prints "<AE> (<fraction>)" on stderr. With -fuzz the HDRI build
# can report a fractional AE (e.g. "4.29542"), so parse a float and round.
out=$(compare -metric AE -fuzz 2% "$cmp_ours" "$cmp_ref" "diff/$name-diff.png" 2>&1 || true)
count=${out%% *}
case $count in
  ''|*[!0-9.eE+-]*) echo "$name: compare failed: $out" >&2; exit 5 ;;
esac
count=$(awk -v c="$count" 'BEGIN { printf "%d", c + 0.5 }')

magick "$cmp_ours" "$cmp_ref" -background '#666666' +smush 10 "diff/$name-side.png"

w=${size_ref%x*}
h=${size_ref#*x}
total=$((w * h))
if [ "$quiet" = 1 ]; then
  echo "$count $total"
else
  pct=$(awk -v c="$count" -v t="$total" 'BEGIN { printf "%.3f", 100 * c / t }')
  echo "$name: $count differing px of $total ($pct%), $size_ref, fuzz 2%"
  echo "  ours  diff/$name-ours.png"
  echo "  ref   $ref"
  echo "  diff  diff/$name-diff.png"
  echo "  side  diff/$name-side.png"
fi
