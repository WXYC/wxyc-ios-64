# Configuration, Signing & Extensions

## Configuration

App configuration (PostHog API key, API base URL, request-o-matic URL, donation destination) is managed by `AppConfiguration` in the AppServices package. Values are hardcoded as defaults and fetched from the backend `/config` endpoint at launch. The `AppConfig` type itself is the generated `WXYCAPIModels.AppConfig`, re-exported by AppServices via a scoped `@_exported import` (#915) — its field set and doc comments come from `api.yaml`, and contract drift is a build error rather than silent skew. Confidential API credentials (Discogs, Spotify) are no longer embedded in the app; those calls are proxied through Backend-Service behind anonymous device session auth.

### The launch fetch

`Singletonia.fetchConfiguration()` calls `AppConfiguration.config()` **before** its secrets retry loop and stores the result in `Singletonia.appConfig`, an `@Observable` property views read. Order matters: the loop is 4-attempt exponential backoff for the *authenticated* `/config/secrets` endpoint and returns outright when secrets never arrive, so a `/config` call appended after it would be skipped in exactly the cold-launch/no-auth case that matters most. `/config` is unauthenticated and must not be gated on auth.

The fetch happens once per launch. That is the right cadence for an endpoint served `Cache-Control: public, max-age=3600` — which also means every remote value here is a **deploy-time** switch with up to an hour of propagation delay, not an instant one.

`AppConfiguration.cached` is per-*instance*, and `fetchConfiguration()` builds a local `AppConfiguration()`, so the fetched value must be stored on `Singletonia` rather than read back off the actor.

### Donation fields

| Field | Backend-Service env var (EC2) | Absent value |
|---|---|---|
| `donateUrl` | `DONATE_URL` | `""` (not `null`) |
| `donateEnabled` | `DONATE_ENABLED` | `false` |

Both are **optional** in Swift. Non-optional properties would make `JSONDecoder.decode` throw against any backend that doesn't serve them yet, and `config()` catches a decode error by returning `defaults` wholesale — silently discarding the remote PostHog key and `apiBaseUrl` too. A backend rollback, a stale cached response, or shipping iOS ahead of Backend-Service all trigger that path, so `AppConfigurationTests` pins the missing-field decode.

`DonateRowModel` (`WXYC/iOS/Views/Station/DonateRowModel.swift`) resolves both into what the Station tab's Donate row renders:

- **Visibility** is `donateEnabled ?? false`. `nil` means "the backend doesn't serve the field" — the live state until Backend-Service PR#2115 deploys — and the row is a solicitation, so absence resolves dark; it renders only when the backend says `true` explicitly. `AppConfiguration.defaults` pins `donateEnabled: false` too, so every failure path agrees with the default rather than depending on it. Lighting up is three steps, in order: merge + deploy Backend-Service PR#2115 (it emits both donate fields and registers `DONATE_ENABLED` in `set-ec2-env-var.yml`'s allowlist — until then the runbook variable doesn't exist), set `DONATE_ENABLED` to lowercase `true` — the reader compares strictly — via that workflow (the light-up platform is EC2, not Railway), then flip the `defaults` literal in the next regular release so offline launches show the row too.
- **Destination** is the fetched `donateUrl` when it yields an http(s) URL, else the compile-time `RadioStation.WXYC.donateURL` (`https://wxyc.org/donate`); `defaults` carries no `donateUrl`, so there is no middle rung. `""`, a scheme-relative string, and `mailto:`/`javascript:` all count as absent, because `SFSafariViewController` traps on anything that isn't http(s).

The row opens its destination in an `SFSafariViewController` sheet, not `openURL`. Donations must be collected outside the app (App Store Review Guideline 3.2.1(vi) reserves in-app fundraising for approved nonprofits, which requires a Candid Seal that SEB does not have), so this is a web checkout regardless; the sheet keeps the listener in the app with a Done button and uninterrupted audio, and Apple Pay on the Web works in `SFSafariViewController` — the restriction is on `WKWebView`.

## Sentry Debug Symbols (dSYM upload)

Sentry symbolicates Release stacks **server-side**, from dSYMs uploaded at build time by the `Upload Debug Symbols to Sentry` build phase on the WXYC target. The phase is a one-line `exec` of `scripts/upload-debug-symbols.sh`; the logic lives in the script so it can be regression-tested (`scripts/tests/test-upload-debug-symbols.sh`) instead of edited blind inside `project.pbxproj`.

Without that upload, Sentry has addresses and no function names, and everything downstream of a symbolicated stack — grouping rules, fingerprints, the innermost-in-app-frame heuristics — silently stops working. Nothing in the build says so, which is why the script's failure behavior depends on what kind of build it is.

Every failure mode — no `sentry-cli`, no credentials, upload rejected — resolves the same way, and only the *build* changes the resolution:

| Build | A failed upload is | Because |
|---|---|---|
| An **archive** (`ACTION=install`), on a dev Mac or a runner | an `error:`, exit 1, no archive | this is the build that reaches TestFlight and the App Store |
| Any other **local** build, `Release` included | a `warning:`, exit 0 | the phase runs on every build and must not block work on a machine without `sentry-cli` |
| A **shipping CI** build that isn't an archive | an `error:`, exit 1 | nobody is waiting on a runner, so a spurious failure costs a rerun |
| A **non-shipping CI** build | never attempted | a test workflow uploads nothing, so it needs no token |

The archive row is the one that matters in practice: **WXYC archives locally**, from Xcode's Product > Archive, not on a runner. The first version of this (#955) keyed strictness on CI alone, which left the only build that actually ships taking the lenient path — the build manifest for the 2026-08-11 archive records `ACTION=install`, `CONFIGURATION=Release`, and no `CI` in the environment.

Two exemptions sit on top of the table, plus a deliberate manual override — see [Forcing an archive through](#forcing-an-archive-through):

- **A build with no dSYMs** skips — except where the table above says a failed upload is an `error:`, and then it is one. Every WXYC configuration sets `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`, so an archive with an empty `DWARF_DSYM_FOLDER_PATH` means something upstream broke, and passing that through quietly is the original bug with a new cause. Where it is lenient it prints a `note:` rather than a `warning:` — the one lenient path that doesn't warn, since a build with nothing to upload has nothing to warn about. A plain local `Release` build with no dSYMs takes it.
- **A CI build that can't ship** skips entirely. "Shipping" is `ACTION=install` (an archive) or a `CONFIGURATION` whose name does not start with `Debug`; a build with no `CONFIGURATION` at all counts as shipping, since a spurious CI failure is loud and a skipped upload is not. That guess costs nothing locally, where a non-archive is lenient however it is classified — it decides only whether a *CI* build skips.

The second exemption is load-bearing and easy to get wrong twice over.

**The presence of dSYMs is not the discriminator.** WXYC builds Debug with `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`, so a plain simulator build populates `DWARF_DSYM_FOLDER_PATH` exactly like an archive does. A strict-whenever-dSYMs-exist rule would demand a Sentry token from every CI test run and fail the ones that don't have one. Locally, Debug builds still upload as they always have — Sentry does symbolicate simulator events from dev machines.

**And the configuration test is a prefix, not an equality.** This project has five configurations — `Debug`, `Debug TestFlight`, `TestFlight`, `Release`, `Release (Active Arch)` — and the shared scheme's `TestAction` builds `Debug TestFlight`. Any `xcodebuild test -scheme WXYC` without an explicit `-configuration` (that includes `scripts/test-affected.sh`) lands there, so matching only the literal `Debug` would classify every test run as shipping.

CI-ness comes from the `CI` environment variable, read as a tri-state rather than a presence check: `false`, `0`, `no`, `off`, and empty all mean local, and GitHub Actions sets `CI=true`. It decides only the two CI rows of the table — an archive is strict on its own account, wherever it runs.

CI-ness also picks which fix the diagnostic names, since Xcode's issue navigator shows one line and nothing around it: a runner is told to add an install step or set the token from a repository secret, a dev Mac is told to `brew install getsentry/tools/sentry-cli` or to write a `.sentryclirc`. Sending either one the other's instructions is a dead end.

There used to be a second source — a `.ci-tools/ci-runner` marker file written into the checkout by `ci_post_clone.sh`, on the reasoning that an environment variable surviving into a run-script phase nested inside `xcodebuild` is a thinner guarantee than a file on disk. It went with the rest of the Xcode Cloud path (below). It was also a trap: nothing removed the file, so a developer who ran that script once had every later local `Release` build fail asking for a Sentry token. A leftover marker in a working copy now decides nothing, which the test suite pins.

### Forcing an archive through

A failed upload stops an archive, and sometimes that is the wrong answer at the wrong moment: sentry.io is down, the token expired overnight, the laptop is offline. Create an empty file at the repo root and every failure path goes back to a `warning:`:

```bash
touch .sentry-dsym-optional
```

It has to be a file. The build that needs it is Product > Archive under Xcode.app, which inherits `launchd`'s environment rather than a shell's — nothing you `export` reaches it, and a scheme environment variable does not reach a run-script phase either. The repo root is the only channel a developer has to that build.

The upload is still attempted; the marker only decides what a failure costs. An archive that can upload still uploads and still reports it.

Two things keep this from becoming the `.ci-tools/ci-runner` trap it structurally resembles:

- **It announces itself.** On any build it actually rescued — one that would otherwise have failed — the diagnostic names the file and says to delete it. A forgotten marker is a line in every archive log, not silence.
- **It is gitignored, and must stay that way.** A committed copy would disable the check for everyone, silently, which is exactly the [#955](https://github.com/WXYC/wxyc-ios-64/issues/955) bug with this file as the new cause. The test suite asserts the `.gitignore` entry rather than trusting the habit.

### Local setup

This is a prerequisite for archiving, not a nicety: **Product > Archive fails without it.** For an ordinary build it stays optional — a missing `sentry-cli` is a `warning:` and the build continues.

Install `sentry-cli` (`brew install getsentry/tools/sentry-cli`) and put an auth token in a `.sentryclirc` at the repo root:

```ini
[auth]
token=<your token>
```

Mint it at https://sentry.io/settings/wxyc/auth-tokens/ as an **organization auth token** (the `sntrys_…` kind). Its scope is fixed at `org:ci` / `project:releases` — enough to upload debug files, not enough to administer the project. Don't substitute a personal user token: those carry the minting user's full access and die with their account.

`.sentryclirc` is gitignored and must stay that way. A `~/.sentryclirc` works too and is worth having, since a repo-root one doesn't follow the checkout into a git worktree. The script also reads `SENTRY_AUTH_TOKEN` from the environment — but don't make that your only credential, because Xcode.app launched from the Dock inherits `launchd`'s environment rather than your shell's. An `export` in `.zshrc` reaches `xcodebuild archive` run from a terminal and nothing you start from the GUI.

The same inheritance decides whether the binary is findable at all, so the script does not rely on `PATH` alone to locate it. A build phase under Xcode.app gets the toolchain directories and then `/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` — no `/opt/homebrew/bin`, which is where Homebrew installs on Apple Silicon. `resolve_sentry_cli` therefore checks `PATH` first and then the prefixes in `SENTRY_CLI_SEARCH_DIRS`, which defaults to `/opt/homebrew/bin:/usr/local/bin`. Without that second step a `brew install` would satisfy the instructions above and the next archive would still fail asking for it. Set `SENTRY_CLI_SEARCH_DIRS` if yours lives somewhere else — that variable, not a magic path in the repo, is the supported way to pin a particular copy.

### CI

**No runner needs any of this today, and none is set up for it.** Both GitHub Actions workflows build `-configuration Debug`, which is the non-shipping CI row of the table: the phase skips the upload outright and wants neither a binary nor a token. Xcode Cloud isn't used at all — WXYC archives from Product > Archive on a dev Mac.

There was an Xcode Cloud path here: `ci_post_clone.sh` marked the checkout as a runner and ran an `install-sentry-cli.sh` that vendored a pinned binary into `.ci-tools/bin/` and wrote `~/.sentryclirc` from a secret environment variable. It was ~490 lines including its test suite, it had never once executed, and its marker file made local `Release` builds fail on any machine where the script had been run by hand. It was deleted rather than maintained on spec.

If a runner ever does build something shipping, the phase will fail it — deliberately, since a shipping build with no symbols is the whole bug — and the two things to give it are:

1. `sentry-cli` on the runner's `PATH` before the build step, or a `SENTRY_CLI_SEARCH_DIRS` pointing at wherever the step put it.
2. `SENTRY_AUTH_TOKEN` in the build environment, from a repository secret. Mint it as an **organization auth token** (the `sntrys_…` kind) at https://sentry.io/settings/wxyc/auth-tokens/ — scope fixed at `org:ci` / `project:releases`, enough to upload debug files and not enough to administer the project. Don't substitute a personal user token: those carry the minting user's full access and die with their account. The token belongs in the CI provider's secret store and never in this repo.

## Code Signing

- Development Team: `92V374HC38`
- Code Sign Style: Automatic
- All targets (including extensions) must have `DevelopmentTeam` in their TargetAttributes

### Extension Targets

- **Request Share Extension**: Share sheet integration for sharing songs
- **NowPlayingWidget**: Home screen widget showing current track
- **CarPlay**: CarPlay scene delegate in main app

## App Delegate

`WXYC/iOS/AppDelegate.swift`, wired into `WXYCApp` via `@UIApplicationDelegateAdaptor`, exists for exactly one reason: `application(_:handlerFor:)` returns `PlayMediaIntentHandler` (`Shared/Intents/Sources/Intents/PlayMediaIntentHandler.swift`) for a directly-dispatched `INPlayMediaIntent` — the background-capable entry point a media-suggestion tile (the one iOS offers after headphones connect) needs, since the app's only other SiriKit intake, the `NSUserActivity` continuation in `AppLifecycleModifier.swift`, requires a foreground launch. See #829.

**`AppDelegate` must never implement `application(_:configurationForConnecting:options:)`.** That method takes precedence over the `UIApplicationSceneManifest` declared in `WXYC/iOS/Assets/Info.plist` (`:90-115`), which is what wires `WXYC.CarPlaySceneDelegate` (`:104`) for the CarPlay scene role. An app delegate that implements it — even to fall through to a default — silently breaks CarPlay scene creation, and nothing in the automated test suite would catch that failure mode on its own; `AppDelegateTests` guards it mechanically by asserting `responds(to:)` is `false` for that selector, but the constraint itself has to be honored by never adding the method in the first place.

`com.apple.developer.siri` is already granted in `WXYC/Entitlements/WXYC.entitlements`, so no capability work was needed to add the handler. `INIntentsSupported` (`[INPlayMediaIntent]`) is declared only in `WXYC/iOS/Assets/Info.plist` — the Share Extension and NowPlayingWidget have their own separate `INFOPLIST_FILE`s, and `WXYC/WXYC TV/WXYC-TV-Info.plist` / `WXYC/WatchXYC/WatchXYC-Info.plist` don't need it, so there's no inheritance to guard against.

## Widget Considerations

- Widget refresh budget: 40-70 updates/day, per widget *instance*
- Background refresh scheduled every 15 minutes

WXYC turns over 10-15 playcuts an hour, so the budget cannot track the flowsheet play-for-play. The timeline asks for a flat `.after(5 minutes)` reload and is throttled once the day's budget is spent; the freshness that actually reaches the user comes from the budget-exempt path below.

**Budget-exempt reloads.** WidgetKit doesn't charge a reload while the containing app is in the foreground *or* holds an active audio session. `WidgetStateService` takes every reload that qualifies and declines every one that doesn't, so a listener's widget tracks the flowsheet change-for-change for free, while an idle backgrounded app spends nothing. Both conditions are in `reloadsAreExemptFromBudget`; `WidgetReloading` is the seam that makes them testable, since `WidgetCenter` silently no-ops under test.

## Display Refresh Rate (ProMotion)

`WXYC/iOS/Assets/Info.plist` sets `CADisableMinimumFrameDurationOnPhone` to `true`. Without that key iOS caps the *entire app* at 60 FPS on ProMotion iPhones, no matter what any individual surface asks for — `CADisplayLink`, `MTKView.preferredFramesPerSecond`, and SwiftUI's `TimelineView(.animation(minimumInterval:))` are all clamped together. It is a build-time declaration, so nothing at runtime can opt in without it. (iPad Pro and ProMotion Macs were never subject to the cap, which is why the key is named "OnPhone".)

Removing the cap is permission, not policy. Each surface still chooses its own rate:

- **Visualizer bars** — opt-in, off by default, via "Refresh Rate → Match Display Refresh Rate" in the Visualizer Settings panel. `VisualizerRefreshRate` turns the setting plus the display's maximum into the `TimelineView` interval; `VisualizerSmoothing` rescales the attack/decay constants by elapsed time so the animation keeps the same wall-clock shape at any rate. Those constants were authored per-frame against 60 FPS, so *any* future change to the visualizer's rate has to go through `VisualizerSmoothing` or the bars will decay at the wrong speed.
- **Metal wallpaper** — unaffected, and deliberately so. It lives in the `Shared/Wallpaper` submodule, where `MetalWallpaperView` pins `preferredFramesPerSecond` to 60 and `AdaptiveProfile.wallpaperFPSRange` clamps the adaptive quality controller to `15.0...60.0`. Raising that ceiling means changing what "max quality" means for every persisted learned profile (`AdaptiveProfile.isMaxQuality` compares against the range's upper bound), so it is a separate piece of work in a separate repo.

## App Store Previews

App Store screenshots and preview assets live in a separate project at `../app-store-previews`. Use that project when preparing assets for App Store publication.

## Minimum iOS Version

iOS 18.6 (based on SDK version in built app)
