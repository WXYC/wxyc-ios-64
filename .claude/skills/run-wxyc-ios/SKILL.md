---
name: run-wxyc-ios
description: Build, run, and screenshot the WXYC iOS app in the iOS simulator. Use when asked to run the app, launch it in the simulator, take a screenshot, or visually verify a UI change.
---

# Run the WXYC iOS app in the simulator

All paths are relative to the repo root (`wxyc-ios-64/`). The driver is `.claude/skills/run-wxyc-ios/driver.sh` — a shell wrapper around `xcodebuild` and `simctl`. It is fully headless: it never opens Simulator.app and never sends host mouse/keyboard events, so it never steals Jake's cursor or window focus. Screenshots are the only observation channel.

There is deliberately no synthetic-tap support. An earlier version drove the app with host-level CGEvent clicks mapped onto the Simulator window; that stole Jake's mouse and foregrounded Simulator.app over whatever he was actively working on, repeatedly, across sessions. If reaching a screen requires navigating through the app, ask Jake to drive it himself, or hand him the exact steps to take — do not automate input.

## Agent path (primary)

```bash
D=.claude/skills/run-wxyc-ios/driver.sh
"$D" build          # xcodebuild for the iPhone 17 sim (~1-4 min; incremental after)
"$D" launch         # boots sim headlessly, installs, launches — no window, no focus steal
"$D" screenshot /path/out.png
"$D" quit
```

Screenshots are 1206x2622 (iPhone 17).

Workflow: `build` → `launch` → `screenshot` → Read the png to confirm what's on screen. To reach a screen beyond the launch state (a specific tab, a detail view, a sheet), ask Jake to navigate there and then screenshot, rather than trying to drive it yourself.

## Simulator

- Device: **iPhone 17, UDID `B49BE311-B868-4E8B-AE14-85C159CAD776`** (iOS 27 runtime — the only sim `xcodebuild -showdestinations` resolves; see MEMORY.md).
- Debug bundle id is **`org.wxyc.iphoneappdebug`** (not `org.wxyc.iphoneapp` — the Debug config suffixes it). The driver reads it from the built Info.plist.

## Human path

Open `WXYC.xcodeproj` in Xcode, scheme WXYC, iPhone 17 sim, Run.

## Gotchas (each of these burned real time)

- **Stale DerivedData from other worktrees.** ~15 `DerivedData/WXYC-<hash>/` dirs coexist, one per worktree, every one containing a `Debug-iphonesimulator/WXYC.app`. A wildcard + `head -1` installed a week-old binary from the `-cta` worktree and produced an hour-long hunt for a "regression" (missing tab bar, page-dot root) that was just an old app. The driver resolves the hash by matching `defaults read <dir>/info WorkspacePath` against this checkout.
- **`Debug-maccatalyst/WXYC.app`** also exists in DerivedData and fails to install on an iPhone sim ("not built to support this device family"). The driver pins `Debug-iphonesimulator`.
- **`-skipMacroValidation` is required** on every xcodebuild invocation (macro fingerprint changes otherwise fail validation).
- To inspect what's actually on screen when a screenshot confuses you, attach lldb: `lldb -b -o "attach <pid>" -o "expr -l objc -O -- [[[[UIApplication sharedApplication] windows] objectAtIndex:0] recursiveDescription]" -o detach -o quit` (pid is printed by `launch`).

## Troubleshooting

- `App installation failed: not made for this device` → you grabbed the Catalyst (or a device) build; use the driver's `app_path`, don't glob yourself.
- `xcodebuild … -showdestinations` doesn't list your sim → only iOS 27-runtime sims resolve under the current toolchain; stick to the pinned UDID.
