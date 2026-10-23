# MyWorkDock

Your work dock, in the notch. Hover the top of your Mac's screen: clipboard history, your Google Calendar, notes, Claude account usage and simulator controls are one hover or one hotkey away.

**📖 Documentation: https://aditya-thummar-devx.github.io/my-work-dock/**

![Peek strip over the notch](docs/assets/shots/peek.png)

## What is inside

- **Clipboard**: searchable text history with tags and pins. Password managers are never recorded.
- **My Calendar**: your Google Calendar by month, week or day, with the same event details Google shows. Read-only, for devxlabs.ai accounts.
- **Notes**: TODOs, plus saved Commands, Prompts and Links. Claude Code can add TODOs too (see below).
- **Claude**: **Agents** (approvals waiting for you, live sessions), **Sessions** (a board of your sessions) and **Tokens & cost** (what Claude Code used on this Mac). None of it needs claudex.
- **claudex**: usage gauges and account switching for the optional `claudex` CLI.
- **Emulator**: start and stop iOS simulators and Android emulators, pair devices over Wi-Fi, run `adb reverse` tunnels.
- **Global hotkeys**: jump to a tab from any app with `⌘ ⇧` plus a letter. `⌥ Space` opens the panel.
- **Updates itself**: checks daily and asks to install.

## Install

Requires macOS 14 Sonoma or later on Apple Silicon (M1 and newer).

1. Download the latest `.dmg` from [Releases](https://github.com/aditya-thummar-devx/my-work-dock/releases/latest).
2. Drag **MyWorkDock** to **Applications** and open it.
3. macOS blocks the first launch because the app is not notarized. Follow the [privacy blocker guide](https://aditya-thummar-devx.github.io/my-work-dock/privacy-blocker.html) once.

Full steps: [Install guide](https://aditya-thummar-devx.github.io/my-work-dock/install.html).

## Claude Code MCP

MyWorkDock ships an MCP server, `mwd-mcp`, so Claude Code can add todos to the TODO list. Click **Connect** on the banner in Notes › TODO; it runs `claude mcp add --scope user myworkdock -- <path>` for you. Then, in a new Claude Code session, ask "add a todo: review the PR #work" (or use `/todo` inside this repo).

- The app must be running with Notes › TODO switched on; otherwise the tool answers that MyWorkDock isn't running.
- Without the `claude` command on your PATH, the banner shows the exact command to run yourself.
- The server lives inside the app and Claude Code runs a copy in `~/Library/Application Support/MyWorkDock/bin`, refreshed on every launch, so app updates update it too. Sessions that were already open keep the old copy until they restart (or reconnect in `/mcp`).

## Docs

- [Install](https://aditya-thummar-devx.github.io/my-work-dock/install.html)
- [Privacy blocker](https://aditya-thummar-devx.github.io/my-work-dock/privacy-blocker.html)
- [Usage](https://aditya-thummar-devx.github.io/my-work-dock/usage.html)
- [Features](https://aditya-thummar-devx.github.io/my-work-dock/features.html)
- [Updates](https://aditya-thummar-devx.github.io/my-work-dock/updates.html)
- [Troubleshooting](https://aditya-thummar-devx.github.io/my-work-dock/troubleshooting.html)

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/aditya-thummar-devx/my-work-dock.git
cd my-work-dock
xcodegen generate
open MyWorkDock.xcodeproj
```

My Calendar signs in with Google, so a build needs an OAuth client: a Desktop-app client from a Google Cloud project that has the Calendar API on. Copy `Config/GoogleOAuth.example.xcconfig` to `Config/GoogleOAuth.xcconfig` (gitignored) and fill it in. Without it the tab says sign-in is not configured and everything else works as usual.

## Releasing

Actions tab > **Release** > Run workflow > enter the version (e.g. `0.1.13`) > approve the run. It builds the DMG, signs the appcast and publishes the GitHub release; installed copies pick it up on their next daily check. It only runs from `main` and needs the `SPARKLE_ED_PRIVATE_KEY` secret on the `release` environment. `scripts/release.sh <version>` does the same from a Mac that holds the key in its Keychain.
