#!/usr/bin/env bash
# Run compare.sh for every reference PNG that has a snapshot state and print a table.
#
#   scripts/compare-all.sh
#
# Fragment states (<reference>@<part>) are listed under their reference and compare only their region.
# References without a state yet (content not built, or documentation-only artboards) are listed as "no state".
set -euo pipefail
cd "$(dirname "$0")/.."

app=build/Build/Products/Debug/MyWorkDock.app/Contents/MacOS/MyWorkDock
mkdir -p diff
[ -d MyWorkDock.xcodeproj ] || xcodegen generate >/dev/null
xcodebuild -project MyWorkDock.xcodeproj -scheme MyWorkDock -configuration Debug \
  -derivedDataPath build build -quiet >diff/build.log 2>&1 || { tail -30 diff/build.log >&2; exit 3; }
export NO_BUILD=1

shots=(screenshots/artboards/*.png screenshots/prototype/*.png)
dups=$(for f in "${shots[@]}"; do basename "$f" .png; done | sort | uniq -d)
[ -z "$dups" ] || { echo "reference names in both artboards/ and prototype/: $dups" >&2; exit 1; }

known=$("$app" --snapshot list 2>/dev/null)
row='%-26s %10s %10s %8s  %s\n'
printf "$row" state diff-px total-px pct note
compared=0
missing=0
run_one() {
  local n=$1 label=$2 res c t
  if res=$(scripts/compare.sh "$n" -q 2>/dev/null); then
    read -r c t <<<"$res"
    printf "$row" "$label" "$c" "$t" "$(awk -v c="$c" -v t="$t" 'BEGIN { printf "%.3f", 100 * c / t }')" ""
    compared=$((compared + 1))
  else
    printf "$row" "$label" - - - "FAILED (run scripts/compare.sh $n)"
  fi
}
for f in "${shots[@]}"; do
  n=$(basename "$f" .png)
  if grep -qx -- "$n" <<<"$known"; then
    run_one "$n" "$n"
  else
    printf "$row" "$n" - - - "no screen state"
    missing=$((missing + 1))
  fi
  while read -r frag; do
    [ -n "$frag" ] && run_one "$frag" "  @${frag#*@}"
  done < <(grep -- "^$n@" <<<"$known" || true)
done
echo "compared $compared, no state $missing. Images in diff/<name>-{ours,diff,side}.png"
