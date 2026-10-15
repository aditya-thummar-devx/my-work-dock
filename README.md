# MyWorkDock

Your work dock, in the notch. Hover the top of your Mac's screen: clipboard history, notes, Claude account usage and simulator controls are one hover or one hotkey away.

**📖 Documentation: https://aditya-thummar-devx.github.io/my-work-dock/**

![Peek strip over the notch](docs/assets/shots/peek.png)

## What is inside

- **Clipboard**: searchable text history with tags and pins. Password managers are never recorded.
- **Notes**: TODOs, plus saved Commands, Prompts and Links.
- **claudex**: usage gauges and account switching for the optional `claudex` CLI.
- **Emulator**: start and stop iOS simulators and Android emulators, pair devices over Wi-Fi, run `adb reverse` tunnels.
- **Global hotkeys**: jump to a tab from any app with `⌘ ⇧` plus a letter. `⌥ Space` opens the panel.
- **Updates itself**: checks hourly and installs quietly when idle.

## Install

Requires macOS 14 Sonoma or later on Apple Silicon (M1 and newer).

1. Download the latest `.dmg` from [Releases](https://github.com/aditya-thummar-devx/my-work-dock/releases/latest).
2. Drag **MyWorkDock** to **Applications** and open it.
3. macOS blocks the first launch because the app is not notarized. Follow the [privacy blocker guide](https://aditya-thummar-devx.github.io/my-work-dock/privacy-blocker.html) once.

Full steps: [Install guide](https://aditya-thummar-devx.github.io/my-work-dock/install.html).

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
