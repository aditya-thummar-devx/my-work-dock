#!/usr/bin/env bash
# Cut an OTA release: build the DMG, sign the Sparkle appcast, publish both on a GitHub release.
# Installed copies find it on their next hourly check and relaunch into it once idle.
#
#   scripts/release.sh 0.1.1          # asks before publishing (needs a real terminal)
#   scripts/release.sh 0.1.1 --yes    # no prompt, e.g. from Claude Code's `!`
#
# Needs: clean tree, HEAD pushed, `gh` logged in, and the Sparkle private key: in this Mac's login Keychain
# (restore it from the backup with `generate_keys -f <file>` on a new Mac), or in $SPARKLE_ED_PRIVATE_KEY (CI).
set -euo pipefail
cd "$(dirname "$0")/.."

VER=${1:?usage: scripts/release.sh <version, e.g. 0.1.1> [--yes]}
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

# My Calendar's Google client is baked into the app at build time. Empty values still build, but ship a tab that cannot sign in.
for key in GoogleClientID GoogleClientSecret; do
  [ -n "$(/usr/libexec/PlistBuddy -c "Print :$key" build/Build/Products/Release/MyWorkDock.app/Contents/Info.plist 2>/dev/null)" ] ||
    { echo "$key is empty in the built app: add Config/GoogleOAuth.xcconfig (see README) or the GOOGLE_OAUTH_* Actions secrets. Nothing published." >&2; exit 1; }
done

UPDATES=build/updates
rm -rf "$UPDATES" && mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
# Notes shown by "Check for Updates…": commit subjects since the previous release.
git fetch --tags -q
PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
NOTES="$UPDATES/$(basename "$DMG" .dmg).md"
git log -n 20 --no-merges --format='- %s' ${PREV:+$PREV..}HEAD > "$NOTES"
# CI has no Keychain: the key arrives in the environment and goes to generate_appcast on stdin, never to disk.
KEYARGS=(); [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ] || KEYARGS=(--ed-key-file -)
printf %s "${SPARKLE_ED_PRIVATE_KEY:-}" | build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast ${KEYARGS[@]+"${KEYARGS[@]}"} \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" --embed-release-notes "$UPDATES"

# A missing or mismatched key still exits 0 but writes an unsigned appcast, which installed copies would reject.
grep -q 'edSignature=' "$UPDATES/appcast.xml" || { echo "appcast.xml isn't signed: wrong or missing Sparkle key. Nothing published." >&2; exit 1; }

echo; cat "$NOTES"; echo
if [ "${2:-}" != --yes ]; then
  # Without a terminal `read` fails at EOF; under `set -e` that used to exit silently.
  read -r -p "Publish $TAG (build $BUILD) now? Every installed copy updates itself. [y/N] " ok || ok=n
  [ "$ok" = y ] || { echo "Not published: no confirmation (re-run with --yes to skip the prompt). Built files are in $UPDATES." >&2; exit 1; }
fi
gh release create "$TAG" -R "$REPO" --target "$SHA" --title "MyWorkDock $VER" --notes-file "$NOTES" "$DMG" "$UPDATES/appcast.xml"
echo "Published $TAG"
