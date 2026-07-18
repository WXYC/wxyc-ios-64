---
name: run-wxyc-ios
description: Build, run, screenshot, and drive the WXYC iOS app in the iOS simulator. Use when asked to run the app, launch it in the simulator, take a screenshot, tap/swipe through screens, or visually verify a UI change.
---

# Run the WXYC iOS app in the simulator

All paths are relative to the repo root (`wxyc-ios-64/`). The driver is `.claude/skills/run-wxyc-ios/driver.sh` — a shell wrapper around `xcodebuild`, `simctl`, and a CGEvent click helper (`click.swift`). Screenshots are the observation channel; taps/swipes are synthetic host mouse events mapped from device-pixel coordinates.

## Agent path (primary)

```bash
D=.claude/skills/run-wxyc-ios/driver.sh
"$D" build          # xcodebuild for the iPhone 17 sim (~1-4 min; incremental after)
"$D" launch         # boots sim, opens Simulator.app, installs, launches
"$D" screenshot /path/out.png
"$D" tap 600 2460   # DEVICE-PIXEL coords, i.e. exactly what you read off a screenshot
"$D" press 600 1300 # 1s long-press — this is how the theme picker opens
"$D" swipe 600 900 600 2200   # drag; also used to dismiss the overlay sheet
"$D" quit
```

Screenshots are 1206x2622 (iPhone 17). Pass coordinates in that space; the driver reads the live Simulator window geometry per tap and maps them.

Workflow that works: `launch` → `screenshot` → Read the png → compute target coords from the image → `tap`/`swipe` → `screenshot` again to confirm the interaction landed. Never assume a tap worked without a confirming screenshot.

## Simulator

- Device: **iPhone 17, UDID `B49BE311-B868-4E8B-AE14-85C159CAD776`** (iOS 27 runtime — the only sim `xcodebuild -showdestinations` resolves; see MEMORY.md).
- Debug bundle id is **`org.wxyc.iphoneappdebug`** (not `org.wxyc.iphoneapp` — the Debug config suffixes it). The driver reads it from the built Info.plist.

## Human path

Open `WXYC.xcodeproj` in Xcode, scheme WXYC, iPhone 17 sim, Run. Useless for an agent — no programmatic input/observation.

## Gotchas (each of these burned real time)

- **Stale DerivedData from other worktrees.** ~15 `DerivedData/WXYC-<hash>/` dirs coexist, one per worktree, every one containing a `Debug-iphonesimulator/WXYC.app`. A wildcard + `head -1` installed a week-old binary from the `-cta` worktree and produced an hour-long hunt for a "regression" (missing tab bar, page-dot root) that was just an old app. The driver resolves the hash by matching `defaults read <dir>/info WorkspacePath` against this checkout.
- **Multiple booted sims / wrong window.** `open -a Simulator` can boot extra devices (iPhone 16, 17 Pro Max showed up mid-session). AppleScript `window 1` is whichever device was focused last, so taps silently go to the wrong phone. The driver matches the window named `iPhone 17 – …` (en dash — a bare `iPhone 17 ` prefix also matches `iPhone 17 Pro Max`). If taps stop landing, run `xcrun simctl list devices booted` and shut down strays.
- **Stray clicks can wedge app state.** A mouse-down whose mouse-up lands in a different window reads as a long-press → opens the theme picker → can silently change the persisted theme. If the wallpaper suddenly looks different, `press` mid-screen to open the picker, `swipe 900 1000 300 1000` to page (title at top names each theme; the default is **WXYC 1983**), `tap 600 1300` to select.
- **Click tooling:** `cliclick`/`idb` are not installed; `osascript` `click at` fails with `-25204`; system `python3` has no Quartz module. `swift click.swift` (CGEvent) is the dependency-free path that works. First click after activating the Simulator occasionally gets eaten by window activation — retry once.
- **`Debug-maccatalyst/WXYC.app`** also exists in DerivedData and fails to install on an iPhone sim ("not built to support this device family"). The driver pins `Debug-iphonesimulator`.
- **`-skipMacroValidation` is required** on every xcodebuild invocation (macro fingerprint changes otherwise fail validation).
- The overlay detail sheet (tapping a playcut/ⓘ) dismisses via downward `swipe`, not a background tap.
- To inspect what's actually on screen when a screenshot confuses you, attach lldb: `lldb -b -o "attach <pid>" -o "expr -l objc -O -- [[[[UIApplication sharedApplication] windows] objectAtIndex:0] recursiveDescription]" -o detach -o quit` (pid is printed by `launch`).

## Troubleshooting

- `App installation failed: not made for this device` → you grabbed the Catalyst (or a device) build; use the driver's `app_path`, don't glob yourself.
- `xcodebuild … -showdestinations` doesn't list your sim → only iOS 27-runtime sims resolve under the current toolchain; stick to the pinned UDID.
- Tap prints sane coords but nothing happens → wrong Simulator window (see gotchas) or the window moved between geometry read and click; just retry — geometry is re-read per tap.
