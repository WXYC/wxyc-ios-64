# Native macOS Target: "WXYC Mac" (a Mac-assed Mac app)

## Context

The WXYC app currently reaches macOS via **Mac Catalyst** (`SUPPORTS_MACCATALYST = YES` on the WXYC target; Designed-for-iPad is explicitly disabled — the org CLAUDE.md's "macOS (designed for iPad)" is wrong and should be corrected as part of this work). Catalyst is effectively deprecated, and its warts are permanent: media-key routing that can't be fixed (#315 residue — F8 stays with Music.app), iPad-shaped chrome, and no access to Mac idioms (Settings scene, MenuBarExtra, Dock menu). Issue #197 already anticipated this: its closed plan called itself "the prerequisite for a follow-up that removes Catalyst and adds a native macOS target."

Exploration confirmed the codebase is unusually ready: **all 21 Shared packages declare `.macOS(.v15)`**, the image/color/artwork stack is dual UIKit/AppKit behind Core's `Image` typealias, the Wallpaper Metal engine already implements `NSViewRepresentable`/`makeNSView`, Playback's `AVAudioSession` coupling is behind a protocol with a macOS stub, and `Singletonia`'s `MPNowPlayingInfoCenter` wiring is explicitly commented as intended for macOS. The NowPlayingWidget extension already builds for `macosx` (floor 15.6) with no native host to embed in — this plan gives it one. The real work concentrates in the app target, exactly like the existing thin-target precedent (`WXYC TV`, `WatchXYC`).

**Outcome:** a native `WXYC Mac` app target (SDKROOT `macosx`) that supersedes the Catalyst binary on the same Mac App Store record, with first-class Mac behavior; Catalyst retired once it ships.

## Locked decisions (user-approved)

| Decision | Choice |
|---|---|
| Target shape | Separate thin `WXYC Mac` target following the TV/Watch precedent; NOT multiplatform-izing the iOS target |
| Bundle IDs | Same as iOS (`org.wxyc.iphoneapp`, `org.wxyc.iphoneappdebug`) so the native app replaces Catalyst on the same App Store record; universal purchase preserved |
| Navigation | Custom toolbar-switcher root: `.windowStyle(.hiddenTitleBar)`, full-bleed `ThemePickerContainer` wallpaper, 4 sections via window-toolbar items + ⌘1–⌘4. **No `NavigationSplitView`, no `.sidebarAdaptable`** (standing ruling: opaque split-view columns over the wallpaper are unacceptable). **Re-confirmed 2026-08-03** against HIG + a macOS-26 spike — see "Navigation — decision validated" below |
| Detail presentation | `PlaycutDetailView` / concert detail via `.sheet` on Mac (`fullScreenCover` + zoom transition are iOS-only) |
| macOS floor | 15.6 (parallels iOS 18.6-floor philosophy; packages already `.macOS(.v15)`; widget slice already 15.6) |
| v1 scope | Settings scene (⌘,), MenuBarExtra mini player, Mac widget (embed NowPlayingWidget's existing macosx slice), Dock menu play/pause, `NSSharingServicePicker` share |
| Content views | Reuse `PlaylistView` / `OnTourTabView` / `LikedTabView` / `StationView` — no Mac-specific rewrites of content |
| Excluded from Mac | CarPlay scene, Request Share Extension, BGTaskScheduler background refresh, Settings.bundle |
| Catalyst retirement | Final phase: flip `SUPPORTS_MACCATALYST = NO` on the WXYC target only once WXYC Mac ships; Catalyst keeps shipping until then |

## Navigation — decision validated (2026-08-03)

The toolbar-switcher choice was re-examined against Apple's current HIG and a throwaway spike on real macOS 26.5, because the original rationale ("opaque split-view columns are unacceptable") was an iOS/UIKit, pre-Liquid-Glass observation and worth re-testing.

- **HIG.** A sidebar (`NavigationSplitView` source list) is Apple's *first-choice* top-level nav for a library/content app — our four sections map onto Music.app's sidebar. But the HIG also sanctions a toolbar for navigation ("convenient access to frequently used commands, controls, navigation, and search") and endorses a segmented control to "switch between views in a toolbar." So the toolbar switcher is a legitimate, if second-choice, pattern. **Implementation note:** realize the switcher as a single **segmented control** (or a *selectable* `NSToolbar` with `selectedItemIdentifier`) rather than four independent buttons — that's the HIG-standard control and gives the standard selected-segment affordance.
- **Spike (macOS 26.5, five configs).** A real `NavigationSplitView` still **cannot** run the app's Metal wallpaper under the sidebar. On macOS 26 the sidebar is a floating **Liquid Glass** column (softer than the old grey slab) but it samples the *desktop behind the window*, never the app wallpaper; `.backgroundExtensionEffect()`, `.background(.clear)`, `.scrollContentBackground(.hidden)`, a ZStack wallpaper behind the whole split view, and `.prominentDetail` all fail to bridge it (the detail pane can be made wallpaper-through, the sidebar can't).
- **Option 3 (custom `HStack` + `NavigationStack`)** *does* achieve edge-to-edge Metal under a transparent sidebar, with working selection/collapse/⌘1–⌘4/push-nav — but at the cost of owning all that chrome (plus a11y, focus ring, resize, narrow-collapse) forever.
- **Decision:** the **toolbar switcher** — it delivers edge-to-edge Metal with a HIG-sanctioned control and **does not fight the framework** (no transparent-sidebar hacks, no re-implementing `NavigationSplitView`). Option 2 is out (can't get edge-to-edge Metal); Option 3 is the fallback only if a persistent Music-style source list becomes a hard requirement.

Evidence: memory `reference_macos26_navsplitview_sidebar_transparency` (spike source, screenshots, and per-config results). See also `[[feedback_no_navigationsplitview]]` / `[[project_nav_redesign]]` for the earlier iOS-era finding this supersedes for the Mac target.

## Prior art: `origin/native-macos-target` (March 2026 spike — superseded, harvested)

A 13-commit spike branch (last commit 2026-03-26; master has moved **538 commits** since its merge-base) already attempted this: it created `WXYC/macOS/` (`WXYCMacApp.swift`, `MacRootView.swift`, `MacSingletonia.swift`, Mac-specific playlist views), flipped Catalyst off, and did +439 lines of pbxproj surgery. **Disposition: supersede, do not rebase or cherry-pick.** It predates the Secrets removal (imports `Secrets`/`PostHog` directly), predates On Tour/Liked/Station, forks a `MacSingletonia` composition root, and uses the `NavigationSplitView` layout the locked decisions reject. Its file paths collide with this plan's — the branch should be deleted or archived under a `spike/` prefix when PR M lands.

**Lessons harvested into this plan:**
1. **Sentry local-network prompt (commit a506217c):** Sentry's `SCNetworkReachability` usage triggers macOS's "find devices on local networks" permission prompt. `AppBootstrap`'s Sentry setup must branch on macOS: `enableNetworkTracking = false`, `enableNetworkBreadcrumbs = false` (iOS keeps `enableNetworkTracking = true`).
2. **App group is load-bearing on macOS (25d15cdf → 77f73652):** the spike removed the app-group entitlement, then had to restore it for cache/UserDefaults access — independent validation of Track A's `group.wxyc.iphone` decision.
3. **ATS exceptions required (cb14def3):** the spike hit the plain-HTTP stream/playlist failures and added the same ATS exceptions Track A's Info.plist carries over.
4. **Window sizing precedent:** the spike used `.defaultSize(width: 420, height: 750)` — adopt as `MacRootView`'s starting default (tune during PR D QA).
5. The spike's `openURL` migration (1b825a8d) covers the same three call sites as PR C — redo fresh on master (trivial) rather than cherry-pick across 538 commits.

## Implementation tracks

_(Track details being synthesized from Plan agents — sections below to be filled.)_

### Track A: Xcode project mechanics

**Approach: hand-edit `project.pbxproj` per the `docs/project-structure.md` playbook**, cloning the `WXYC TV` target's blocks. (Rejected: Xcode GUI target creation — scaffolds a redundant synced root group + template files and risks whole-file rewrite; the ruby `xcodeproj` gem re-serializes/reorders the entire file. The TV/Watch/Widget targets were provably added by hand — the pbxproj contains hand-minted UUIDs like `23TV0001…`.) Mint the full UUID table (~30 IDs, one greppable prefix e.g. `23AC…`) before any edit.

**No new file group needed:** `WXYC/macOS/` lives *inside* the existing file-system-synchronized `WXYC` root group (`23FB1F2F…`). The Mac target gets one new `PBXFileSystemSynchronizedBuildFileExceptionSet` whose `membershipExceptions` INCLUDE its files; the WXYC (iOS) target's existing exception set gets EXCLUSIONS added for everything under `macOS/` (memory-confirmed semantics: owning target's set excludes, non-owning includes). ⚠️ Every file is one literal line — no globs; forgetting an exclusion compiles a second `@main` into the iOS app; a typo'd inclusion silently drops a file from the Mac build.

**New files on disk (before any pbxproj edit):**
- `WXYC/macOS/WXYCMacApp.swift` (placeholder `@main`; Track B replaces)
- `WXYC/macOS/Assets.xcassets` (AccentColor; app icon via membership of shared `iOS/Assets/AppIcon.icon` — WatchXYC precedent)
- `WXYC/macOS/WXYC-Mac-Info.plist` — modeled on `WXYC-TV-Info.plist`; **must keep the NSAppTransportSecurity exception for `audio-mp3.ibiblio.org`** (stream is plain HTTP). Do *not* carry over a `wxyc.info` exception — it existed only for the legacy v1 playlist feed and was removed in #262; no `UIApplicationSceneManifest`/CarPlay
- `WXYC/Entitlements/WXYC Mac.entitlements` + `WXYC MacDebug.entitlements` — **keep:** associated-domains (`applinks:wxyc.org`), `group.wxyc.iphone` app group, keychain-access-groups, group-session; **drop:** carplay-audio, networking.multipath, siri (iOS-only; leaving them in breaks macOS automatic profile generation). Sandbox/network stay as build settings (`ENABLE_APP_SANDBOX`/`ENABLE_OUTGOING_NETWORK_CONNECTIONS`), matching the iOS target.

**App group on macOS — resolved:** use `group.wxyc.iphone` unchanged. `group.*` identifiers are first-class on macOS 15/Xcode 16, and the widget's macosx slice *already ships* signed with this group under team 92V374HC38 — it's provably provisioned for macOS. Keep `REGISTER_APP_GROUPS = YES`. Mac app + widget share `~/Library/Group Containers/group.wxyc.iphone/`.

**pbxproj edits (one commit, 15 sections, ordered top-to-bottom):** PBXBuildFile entries (package products + `NowPlayingWidget.appex in Embed Foundation Extensions`, `RemoveHeadersOnCopy`, **no platformFilter** — target is Mac-only); PBXContainerItemProxy + PBXTargetDependency on NowPlayingWidget (`236B51CD…`); new Embed Foundation Extensions copy phase (`dstSubfolder = PlugIns`); product PBXFileReference; the two exception-set edits + root-group `exceptions` append; Frameworks/Sources/Resources phases; PBXNativeTarget (no `fileSystemSynchronizedGroups` — only the owning target has that); PBXProject `targets` + `TargetAttributes` (team 92V374HC38, Automatic); 5 XCBuildConfiguration blocks + XCConfigurationList; XCSwiftPackageProductDependency entries (`productName` only for local packages; Sentry once — the iOS target lists Sentry **twice**, don't replicate that cruft, nor the stale `FRAMEWORK_SEARCH_PATHS`).

**Key build settings (all 5 configs — Debug, Debug TestFlight, Release, Release (Active Arch), TestFlight):** `SDKROOT = macosx` (implies platform; no SUPPORTED_PLATFORMS/TARGETED_DEVICE_FAMILY needed), `MACOSX_DEPLOYMENT_TARGET = 15.6`, `PRODUCT_NAME = WXYC` (ships as `WXYC.app`; fall back to `$(TARGET_NAME)` only if the duplicate product name chokes tooling), `PRODUCT_BUNDLE_IDENTIFIER = org.wxyc.iphoneapp` (`…appdebug` on Debug only, matching iOS), `ENABLE_APP_SANDBOX/HARDENED_RUNTIME/OUTGOING_NETWORK_CONNECTIONS = YES`, `GENERATE_INFOPLIST_FILE = YES` + explicit `INFOPLIST_FILE` (widget precedent — they merge), `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.music`, `LD_RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks` (macOS layout), `REGISTER_APP_GROUPS = YES`, same `EXCLUDED_SOURCE_FILE_NAMES` PostHog block as WXYC, `SWIFT_VERSION = 6.0`. Inherit project-level MainActor-default-isolation, MARKETING_VERSION, etc.

**Package products (mirror WXYC minus cruft):** Core, Logger, Analytics, Playback, Caching, Playlist, LikedSongs, Metadata, Artwork, AppServices, WXUI, PartyHorn, PlayerHeaderView, Wallpaper, DebugPanel, ColorPalette, WXYCIntents, MusicShareKit, Sentry(×1). Prune later if Track B drops any — deleting is 3 lines, adding is 3 sections.

**Scheme:** new `WXYC Mac.xcscheme` cloned from `WXYC TV.xcscheme` (BuildableName `WXYC.app`, implicit deps pull the widget; Launch=Debug, Archive=Release, empty Testables). **Do not** touch `WXYC.xcscheme` — keeps CI/Xcode Cloud/test-affected.sh untouched until retirement. No Mac test bundle yet; package tests already run on macOS host.

**Validation gates (after each phase):**
- Gate 0: `plutil -lint project.pbxproj` after every save
- Gate A: `xcodebuild -list` → 8 targets (9 once PR M's `WXYCMacTests` bundle lands), 5 configs, new scheme
- Gate B: build `-scheme "WXYC Mac" -destination 'platform=macOS,arch=arm64' -skipMacroValidation`; grep the log to confirm each included file compiled
- Gate C: iOS still builds (sim `B49BE311-B868-4E8B-AE14-85C159CAD776`) — proves the exclusion edits
- Gate D: `ls Contents/PlugIns` (appex embedded); `codesign -d --entitlements -` on app + appex (group present, no carplay); `otool -l | grep LC_BUILD_VERSION` (platform MACOS, not Catalyst)
- Gate E: `xcodebuild archive -destination generic/platform=macOS -allowProvisioningUpdates` (first native-macOS profile mint for `org.wxyc.iphoneapp` — riskiest external step; worst case bring up under the debug bundle ID first)
- Gate F: `scripts/test-affected.sh` (pbxproj change ⇒ full plan; `WXYC_SKIP_KNOWN_FLAKES=1`)

**Found bug (fix opportunistically):** NowPlayingWidget has `ENABLE_APP_SANDBOX = YES` but no `ENABLE_OUTGOING_NETWORK_CONNECTIONS` — its macosx slice ships today with no network-client entitlement. If the Mac widget does direct URL loads (artwork), add the setting to its 5 configs.

**Catalyst retirement (final phase, ships with the Mac app):**
1. WXYC target ×5 configs: `SUPPORTS_MACCATALYST = NO`; keep `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = YES` (visionOS DfI must not break). Widget `SUPPORTED_PLATFORMS` untouched.
2. ⚠️ App Store: a native macOS binary under `org.wxyc.iphoneapp` converts the Mac offering from Catalyst to native — they cannot coexist; Mac build number must exceed the last Catalyst build (Xcode Cloud build stamping must cover the Mac workflow).
3. Xcode Cloud: create the Mac workflow in the Cloud UI (never hand-edit `xcodecloud/manifest.json` — ASC-side GUIDs); `ci_post_clone.sh` works as-is.
4. `build_and_upload.sh`: optional follow-up — parameterize `--scheme`/`--destination` (existing exportOptions plist is valid for macOS unchanged); primary path is Xcode Cloud.
5. Separate cleanup ticket (not this work): delete orphaned `WXYC/Configuration/*.xcconfig` (also requires removing their 3 exclusion-set entries) and the dead generation tooling — `scripts/generate_project.sh` + `scripts/postprocess_xcodeproj.py` still reference `project.yml`, which was removed (7162719d). ⚠️ **Never run `generate_project.sh` during this work** — if resurrected it would clobber the hand-minted target.

### Track B: Swift composition (app code)

**Premise corrections from deep-read (both tracks agree):** `NowPlayingInfoCenterProtocol`/`RemoteCommandCenterProtocol` already include `os(macOS)` — no work. `ArtworkLoader.swift` (Shared/Artwork) is wrapped *entirely* in `#if canImport(UIKit)` with `State.loaded(UIImage)` — a hard blocker, migrated to `Core.Image` (source-compatible on iOS). `StationView` imports MessageUI (not on macOS) — `FeedbackMailRouter.route(canSendMail: false, …)` already models the fallback. `BackgroundTasks` doesn't exist on macOS — `BackgroundRefreshController`/`BackgroundTaskScheduling` are target-excluded, not branched. `NowPlayingItem` already carries `Core.Image` — the mini player gets cross-platform artwork free.

**New `WXYC/macOS/` files** (standard headers, one type per file):
- `WXYCMacApp.swift` — `@main`. Scenes: `Window("WXYC", id: "main")` (single-window — `WindowGroup` would invite ⌘N duplicates the one-shot deep-link routing isn't designed for) + `.windowStyle(.hiddenTitleBar)` + `.windowResizability(.contentMinSize)`; `Settings { MacSettingsView }`; `MenuBarExtra("WXYC", systemImage: "radio") { MiniPlayerView }.menuBarExtraStyle(.window)`; `.commands { MacCommands }`; `@NSApplicationDelegateAdaptor(MacAppDelegate.self)`.
- `MacAppDelegate.swift` — sole job `applicationDockMenu` → `DockMenuBuilder.menu(isPlaying:)`; lifecycle stays in SwiftUI.
- `DockMenuBuilder.swift` — pure testable spec structs + NSMenu assembly; actions call `AudioPlayerController.shared.toggle(reason: .dockMenu)`.
- `MacNavigationModel.swift` — `@Observable`, `selectedSection: AppSection`, pure `handleDeepLinks(concert:playcut:venue:)` mirroring RootTabView's three `.onChange` mappings (unit-testable).
- `Views/MacRootView.swift` — `ThemePickerContainer { ZStack { section switch; DEBUG HUD } }`; hosts the four reused views (`PlaylistView`/`OnTourTabView`/`LikedTabView`/`StationView`) with `.themePickerGesture`; detail via shared `.detailCover` (sheet on Mac) with `.environment(appState)` re-injection; `.toolbar { MacSectionToolbar }` + `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`; deep-link `.onChange`s; no `forceLightStatusBar`/`crossfadeColorSchemeTransitions` (iOS-only).
- `Views/MacSectionToolbar.swift` — four ToolbarItem toggles from `AppSection.allCases`, LCD-accent selected tint (reuse `tabTintBrightness` logic), accessibility ids preserved.
- `MacCommands.swift` — embeds reusable `WXYCCommandMenus` (UIKit-free) + `CommandGroup` with ⌘1–⌘4 section switching; system-provided About/Settings items suffice for v1.
- `MacAppLifecycleModifier.swift` — `.onAppear`: `setForegrounded(true)` once, widget/review/deep-link observer starts, palette extraction; `.onOpenURL`/`.onContinueUserActivity` → shared `DeepLinkHandler`. No quick actions, memory-warning, or MarketingMode.
- `Settings/MacSettingsView.swift` + `Settings/SettingsModel.swift` — grouped Form: artwork cache size (`CacheCoordinator.AlbumArt.totalSize()`) + Clear (fires the existing `ArtworkCacheCleared` event, `source: "mac_settings"`); Send Feedback via `FeedbackMailRouter.route(canSendMail: false, …)` → mailto; about/version. VM injects `ArtworkCacheManaging` protocol + `AnalyticsService` for TDD.
- `MenuBar/MiniPlayerView.swift` + `MenuBar/MiniPlayerModel.swift` — artwork + title/artist + play/pause + "Open WXYC" (`openWindow(id: "main")`) + Quit; plain `.regularMaterial` panel (no Metal in a 300pt popover). Model follows the `NowPlayingInfoCenterManager` processor pattern; Singletonia grows `startMiniPlayerObservation(model:)` reusing the existing `NowPlayingService` iterator + `Observations` dedupe patterns.
- `Views/MacSharingServicePicker.swift` — `NSViewRepresentable` anchor presenting `NSSharingServicePicker(items: [url])` (bare-URL invariant preserved; macOS renders its own preview).

**Shared hoists (new files, both targets):** `AppSection.swift` (hoisted from `RootTabView.Page` — nested enum can't be shared since RootTabView stays iOS-only; migrate `RootTabPageTests` → `AppSectionTests`); `DetailCoverModifier.swift` (`detailCover` = fullScreenCover on iOS / sheet on macOS; `zoomTransition`/`zoomTransitionSource` = real on iOS / identity on macOS); `DeepLinkHandler.swift` (extracted from `AppLifecycleModifier` — already effectively pure); `AppBootstrap.swift` (analytics/Sentry/error-reporting setup extracted from `WXYCApp` so the two `@main`s can't drift; Sentry setup branches on macOS — `enableNetworkTracking = false`, `enableNetworkBreadcrumbs = false` — to avoid the SCNetworkReachability local-network permission prompt, per the spike's a506217c); `WallpaperPaletteExtraction.swift`; `ArtworkDisplayMetrics.swift` (UIScreen path on iOS, documented 600px constant on Mac); `PlaceholderArtwork.swift` (split from `NowPlayingInfoCenterManager`, AppKit branch via existing pure-CG helpers).

**Lifecycle decisions:** on macOS the app is "foregrounded" for its entire run — `setForegrounded(true)` once, never false; window close must NOT touch playback (`handleAppDidEnterBackground` never called); SSE stays connected by design; freshness = PlaylistService's 300s poll + SSE (no BGTask). Termination: `ApplicationWillTerminateMessage` grows an `#elseif canImport(AppKit)` branch (`Subject = NSApplication`) so `WidgetStateService` clears `isPlaying` on quit. **Drop** `donateSiriIntent()` (INPlayMediaIntent donation has no macOS surface; App Intents themselves stay — `Intents.swift` is INCLUDED so Spotlight donations are tappable). Keep review requests (`requestReview` exists on macOS).

**Key leaf seams** (mechanism per site; two new WXUI shims — `PlatformImage.swift` typealias + `Image(platform:)`, and `Pasteboard.swift`):
| Coupling | Fix |
|---|---|
| `UIImage` in views/rows/detail/widget/Intents | `PlatformImage` + `Image(platform:)` sweep |
| `UIApplication.shared.open` (ExternalLinkButton, ReviewsSection, StreamingButton) | `@Environment(\.openURL)` (preferred on iOS anyway); SafariView `#if os(iOS)` |
| `UIPasteboard` (StationView) | WXUI `Pasteboard.copy(_:)` |
| MessageUI (StationView) | `#if canImport(MessageUI)` around composer; mac falls back to existing `externalMailto` route |
| Share sheets (ConcertShareSheet) | same modifier API, `#if os(iOS)` UIActivityViewController / `#else` MacSharingServicePicker |
| `UIScreen` (Singletonia, PlaycutRowView) | `ArtworkDisplayMetrics`; `NSScreen.main` fallback for the shadow math |
| ClockView `UIGraphicsImageRenderer` | `NSImage(size:flipped:drawingHandler:)` around identical CG body |
| openSettingsURLString (ConcertCalendarSheet) | `x-apple.systempreferences:…Privacy_Calendars` on Mac |
| Haptics | Pow vendored files already gated; `HapticEventSpec` gets `#if canImport(CoreHaptics)`; no NSHapticFeedback in v1 |
| Artwork memory warning | iOS modifier keeps it; Mac has no counterpart (no equivalent notification) |
| MP3StreamDecoder CoreAudio import | `#if targetEnvironment(macCatalyst) || os(macOS)` |
| WidgetStateService willTerminate | widen gate, platform-neutral observer |
| New `PlaybackReason` cases | `.menuBar`, `.dockMenu` (additive, analytics-visible) |

**Excluded from Mac target** (feeds Track A's exclusion mechanics): `WXYCApp.swift`, `RootTabView.swift`, `AppLifecycleModifier.swift`, `CarPlaySceneDelegate.swift`, `BackgroundRefreshController.swift`, `BackgroundTaskScheduling.swift`, `MarketingMode.swift` + `Marketing/`, `SafariView.swift`, `TabBarTransparency.swift`, `StatusBarStyleModifier.swift`, `ColorSchemeCrossfade.swift`, `SiriTipView.swift`, `Settings.bundle`. Everything else under `WXYC/iOS/` joins the Mac target's inclusion list.

### PR sequencing (each ≤1000 lines; A–C are iOS-green with no Mac target yet)

1. **PR A — package seams:** Core willTerminate AppKit branch; WidgetStateService gate; ArtworkLoader → `Core.Image`; MP3StreamDecoder import; WXUI `PlatformImage`/`Pasteboard` + WXUI's first test target; `PlaybackReason` cases. Tests first. (~400 lines)
2. **PR B — presentation seams:** `AppSection` hoist (+tests), `DetailCoverModifier` + migrate 4 cover sites/3 transition sources, `DeepLinkHandler` extraction, `WallpaperPaletteExtraction` hoist. Pure refactor. (~500)
3. **PR C — leaf shims:** openURL/pasteboard/MessageUI/PlatformImage sweep, `PlaceholderArtwork`, `ArtworkDisplayMetrics`, calendar-settings branch, CoreHaptics gate, Intents shim, `AppBootstrap` extraction. (~700; split C1/C2 at the PlatformImage boundary if hot)
4. **PR M — target creation (Track A Phases 0–5):** pbxproj surgery, entitlements, Info.plist, scheme, placeholder `@main`, **`WXYCMacTests` macOS unit-test bundle + `WXYC Mac.xctestplan` + Mac scheme Testables wired** (composition needs it for TDD on Mac-target types — overrides Track A's "no test bundle yet"; without the test plan the Mac suites would run nowhere automated), extend `scripts/test-affected.sh`/`.github/scripts/affected-tests.sh` with a Mac-scheme test invocation, Gates 0–E. Doc updates: `docs/project-structure.md` (folder layout + new target), `docs/build-test.md` (macOS build/test invocations). Requires A–C landed (inclusion list must compile). Note: `Concerts` is intentionally absent from the Mac product list — the iOS target also reaches it transitively (via AppServices/Playlist/WXYCIntents); an OnTour compile failure at Gate B is the signal to add it explicitly, not before.
5. **PR D — Mac skeleton:** `WXYCMacApp`, `MacRootView`, `MacSectionToolbar`, `MacNavigationModel`(+tests), `MacCommands`, `MacAppLifecycleModifier`. **Milestone gate: stream plays + media keys work + window over wallpaper + ⌘1–⌘4** — proves the never-exercised native-macOS playback path before feature PRs. (~600)
6. **PR E — Settings scene** (+`SettingsModel` tests). (~250)
7. **PR F — MenuBarExtra** (+`MiniPlayerModel` tests + Singletonia observation). (~350)
8. **PR G — Dock menu + share** (`MacAppDelegate`, `DockMenuBuilder`+tests, `MacSharingServicePicker` + ConcertShareSheet branch). (~350)
9. **PR H — Catalyst retirement** (Track A Phase 6): `SUPPORTS_MACCATALYST = NO`, widget network-entitlement verification/fix, Xcode Cloud Mac workflow (created via the ASC/Xcode UI — the workflow is ASC-managed; the local `xcodecloud/manifest.json` is untracked on disk and is never hand-edited), release notes, and doc sweep: `CLAUDE.md:5` "macOS (designed for iPad)" → native macOS, `docs/architecture.md` (second `@main` + `AppBootstrap`), `docs/configuration.md` (macOS floor 15.6, Mac target signing), WXUI README/CLAUDE for `PlatformImage`/`Pasteboard`. Ships with the Mac app's App Store submission; build number must exceed last Catalyst build. Delete/archive the superseded `native-macos-target` spike branch + the two stale `adaptive-nav*` branches.

E/F/G are parallelizable after D. Wallpaper submodule: v1 assumes zero changes (NSViewRepresentable exists; its ShareSheet compiles away); any surprise becomes a cross-repo PR.

### Branch & worktree strategy

Each PR gets its own worktree **created before any code** (global workflow): `mac-seams-packages` (A), `mac-seams-presentation` (B), `mac-seams-leaf` (C), `mac-target` (M), `mac-skeleton` (D), `mac-settings` (E), `mac-menubar` (F), `mac-dock-share` (G), `catalyst-retirement` (H). ⚠️ Every new worktree needs `git submodule update --init Shared/Wallpaper` (worktrees leave it empty, breaking package resolution); remove worktrees with `rm -rf` + `git worktree prune`, never `submodule deinit`. Parallel worktree builds need per-worktree `-derivedDataPath`.

**In-flight branch coordination (verified 2026-08-03):**
- `origin/adaptive-navigation-split-view` (Apr 9) + `origin/adaptive-nav-background` (Apr 15): stale #197 work, superseded by this plan's locked nav decision — close/archive alongside the spike branch.
- `origin/on-tour-share-receive` (Jul 20, 11 commits — active #535 sharing epic): touches OnTour/`ConcertShareSheet`. **Land or rebase it before PR C and PR G.**
- `origin/tab-bar-accent-offset` (Jul 24, 1 commit): touches RootTabView tinting — land before PR B's `AppSection` hoist.
- `origin/playlist-container-glass` (Aug 2, 1 commit): touches PlaylistView — land before PR C's PlatformImage sweep.
Rule: small live branches land first (rebase-merge per workflow); this plan's PRs rebase on top. Never start a colliding PR while its counterpart is unmerged.

### Riskiest items (merged from both tracks)

1. **Membership-exception direction errors** — missed exclusion ⇒ second `@main` in the iOS app; typo'd inclusion ⇒ silently missing file in Mac build. Mitigate: single-commit exception edits, Gate C immediately after Gate B, grep build log for compiled files.
2. **First native-macOS provisioning for `org.wxyc.iphoneapp`** — automatic signing must mint a macOS profile with the app group/applinks/keychain set; any stale iOS-only entitlement fails opaquely. Mitigate: vetted entitlement set only; widget's shipping macOS slice proves the group; bring up under debug bundle ID if needed.
3. **First real runtime exercise of playback on native macOS** — AVAudioEngine/MP3Streamer with the never-run `AudioSessionProtocol` stub, media keys, Now Playing promotion. Mitigate: PR D milestone gate before any feature work.
4. **Window chrome over Metal wallpaper** — hiddenTitleBar + hidden toolbar background + full-bleed Metal has six subtle ways to look wrong; fixes inside Wallpaper cross the submodule boundary. Mitigate: accept manual-QA iteration in PR D; keep chrome minimal.
5. **Long tail of "reuse the four views unchanged"** — the sweep isn't exhaustive until the Mac target compiles. Budget a mop-up commit in PR D; resist forking Mac copies of content views when a two-line gate will do.

## Verification

- **Per-PR:** failing test first (Swift Testing), then green. Two execution paths — don't conflate them:
  - *Host-run package tests* (`swift test` / existing xctestplan via `scripts/test-affected.sh`, `WXYC_SKIP_KNOWN_FLAKES=1`): `AppSectionTests`, `ArtworkDisplayMetricsTests` (WXYCTests, iOS host), WXUI `PasteboardTests`, Core message tests (AppKit branch proves itself on macOS host), WidgetStateService termination seam, PlaybackReason analytics strings.
  - *Mac-scheme tests* (`xcodebuild test -scheme "WXYC Mac" -destination 'platform=macOS,arch=arm64'` via the new `WXYC Mac.xctestplan`): `MiniPlayerModelTests`, `DockMenuBuilderTests`, `SettingsModelTests`, `MacNavigationModelTests`. Wired into `test-affected.sh` in PR M so they run automated, not just locally.
- **PR M gates:** `plutil -lint`; `xcodebuild -list` (8 targets); Mac build + iOS build (sim `B49BE311…`) both green with `-skipMacroValidation`; `Contents/PlugIns/NowPlayingWidget.appex` present; `codesign -d --entitlements -` shows group + applinks, no carplay; `otool` LC_BUILD_VERSION = MACOS; archive with `-allowProvisioningUpdates` succeeds.
- **PR D milestone (manual):** stream plays; play/pause from media keys + Control Center Now Playing; window renders wallpaper full-bleed with hidden title bar; ⌘1–⌘4 + toolbar switch sections; detail opens as sheet; deep link `wxyc://` routes; Handoff banner appears on iPhone when Mac plays (activity type string unchanged: `org.wxyc.iphoneapp.play`).
- **v1 acceptance (manual):** Settings ⌘, clears cache and reports size; MenuBarExtra controls playback with main window closed and reopens it; Dock right-click play/pause; concert share presents NSSharingServicePicker with working URL; widget shows now-playing on the Mac desktop (verify network entitlement); app survives quit-while-playing (widget state cleared).
- **Retirement gate:** TestFlight/App Store build supersedes Catalyst (build number check); universal purchase intact; iOS/tvOS/watchOS untouched (`WXYC.xcscheme` never modified until PR H).
