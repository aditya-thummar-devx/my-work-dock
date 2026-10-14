#!/usr/bin/env bash
# Cut an OTA release: build the DMG, sign the Sparkle appcast, publish both on a GitHub release.
# Installed copies find it on their next hourly check and relaunch into it once idle.
#
#   scripts/release.sh 0.1.1
#
# Needs: clean tree, HEAD pushed, `gh` logged in, and the Sparkle private key in this Mac's login Keychain
# (restore it from the backup with `generate_keys -f <file>` on a new Mac).
set -euo pipefail
cd "$(dirname "$0")/.."

VER=${1:?usage: scripts/release.sh <version, e.g. 0.1.1>}
TAG=v$VER
REPO=aditya-thummar-devx/my-work-dock

[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes; commit first." >&2; exit 1; }
SHA=$(git rev-parse HEAD)
git branch -r --contains "$SHA" | grep -q . || { echo "HEAD isn't pushed; push first." >&2; exit 1; }
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then echo "$TAG already exists." >&2; exit 1; fi
# Sparkle compares this number, not the version string. ponytail: it only grows along one branch, so never release from a branch
# with fewer commits than the last release (installed copies would skip the update).
BUILD=$(git rev-list --count HEAD)

DMG=$(VERSION=$VER BUILD=$BUILD scripts/make-dmg.sh | tail -1)

UPDATES=build/updates
rm -rf "$UPDATES" && mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
# Notes shown by "Check for Updates…": commit subjects since the previous release.
git fetch --tags -q
PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
NOTES="$UPDATES/$(basename "$DMG" .dmg).md"
git log -n 20 --no-merges --format='- %s' ${PREV:+$PREV..}HEAD > "$NOTES"
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" --embed-release-notes "$UPDATES"

echo; cat "$NOTES"; echo
read -r -p "Publish $TAG (build $BUILD) now? Every installed copy updates itself. [y/N] " ok
[ "$ok" = y ] || { echo "Not published. Built files are in $UPDATES."; exit 1; }
gh release create "$TAG" -R "$REPO" --target "$SHA" --title "MyWorkDock $VER" --notes-file "$NOTES" "$DMG" "$UPDATES/appcast.xml"
echo "Published $TAG"
