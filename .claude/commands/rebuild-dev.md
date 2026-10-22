---
description: Step-by-step dev rebuild of MyWorkDock - remove installed app, rebuild from the working tree, install to /Applications
allowed-tools: Bash, AskUserQuestion
---

Rebuild and reinstall MyWorkDock for local dev. Run from the repo root. Ask each step with AskUserQuestion (Yes / No), in order, one at a time. Do not ask a later step before the earlier one is finished.

App facts: `/Applications/MyWorkDock.app`, process name `MyWorkDock`, build output `build/Build/Products/<Debug|Release>/MyWorkDock.app` (`build/` is gitignored). Ad-hoc signing only: never add DEVELOPMENT_TEAM, a signing identity or entitlements.

Quit helper (use in step 1 and 3 whenever the app is running, check with `pgrep -x MyWorkDock`): `osascript -e 'quit app "MyWorkDock"'`, wait up to 5s, re-check. Still running: ask the user before `pkill -x MyWorkDock`. Never force-kill without asking.

Trash helper: `mv /Applications/MyWorkDock.app ~/.Trash/MyWorkDock-$(date +%Y%m%d-%H%M%S).app`. Never `rm -rf` the app.

## Step 1 - Remove existing app?
Ask: "Remove the installed MyWorkDock from /Applications?" Yes / No.
- No: skip to step 2.
- Yes: look only at `/Applications/MyWorkDock.app`.
  - Not there: say so and continue to step 2.
  - There: show its version (`/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/MyWorkDock.app/Contents/Info.plist`) and build (`CFBundleVersion`), ask to confirm removal. Confirmed: quit it if running (quit helper), then move it to Trash (trash helper).

## Step 2 - Good to go with rebuild?
Ask: "Good to go with rebuild from the working tree as-is?" Yes / No.
- No: skip to step 3.
- Yes:
  1. Ask: "Build configuration?" Debug (recommended) / Release.
  2. Run `xcodegen generate`. It is idempotent: no diff in the tracked xcodeproj unless `project.yml` changed. (An mtime check is unreliable, git rewrites mtimes on checkout.)
  3. Build: `xcodebuild -project MyWorkDock.xcodeproj -scheme MyWorkDock -configuration <chosen> -derivedDataPath build build -quiet CURRENT_PROJECT_VERSION=99999`. The high build number stops Sparkle from replacing this dev build with a release within the hour.
  4. Build failed: quote the shortest decisive error line, stop here, skip step 3.

## Step 3 - Install now?
Ask: "Install the build now?" Yes / No.
- No: print "Install skipped. Latest build: <path>" (newest app, see below, or "none" if there is none) and stop.
- Yes:
  1. Pick the newest app: `ls -dt build/Build/Products/{Debug,Release}/MyWorkDock.app 2>/dev/null | head -1`. This is the fresh build from step 2, or an older one if step 2 was skipped. None found: say "No build found, run rebuild first" and stop.
  2. If `/Applications/MyWorkDock.app` still exists (step 1 was No or skipped): ask "Overwrite the installed app?" Yes / No. No: stop. Yes: quit it if running (quit helper), then trash it (trash helper).
  3. Install: `cp -R <picked app> /Applications/` then `open /Applications/MyWorkDock.app`.
  4. Verify: print the installed version and build number (PlistBuddy) and the config it was built from.

## Final message
Report what was removed, built (config) and installed (version/build). Then add two notes:
- Ad-hoc re-signing changes the code signature, so macOS may ask again for Local Network permission (wireless adb).
- Build 99999 blocks OTA updates until a release DMG is reinstalled.
