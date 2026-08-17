# Build & Test Commands

## Running Tests

Run WXYC.xctestplan.

### Affected-only test runs (`scripts/test-affected.sh`)

Mirrors CI's affected-tests filtering for local iteration: diffs the working tree against `origin/master`, maps changed `Shared/<pkg>/` paths through the same dependency graph used by `.github/scripts/affected-tests.sh`, and runs only the test targets whose package or transitive dependents were touched.

Two-step execution:

1. **swift test (host, fast):** runs `swift test --package-path Shared/<pkg>` for each affected SPM-runnable package. Skips xcodebuild and simulator entirely. Also covers CoreTests when Core is affected — the Swift Testing parallel-scheduler hang only triggers in the xcodebuild + simulator path, not on host. `ConcertsTests` and `WXUITests` run this way too, even though neither target is in `WXYC.xctestplan` — see `scripts/verify-spm-parity.sh` for how their simulator-side coverage is verified separately.
2. **xcodebuild test (simulator):** runs only when the affected set includes a non-SPM-runnable package in `WXYC.xctestplan` (Playback, Artwork, ColorPalette, Intents, AppServices, PartyHorn, PlayerHeaderView, Wallpaper) or when `--full` is forced. Scoped via `-only-testing` to just the affected app/UI targets. Logger is deliberately not in this list — see below.

For Metadata-only changes the script finishes in ~30s (swift test only). For a pure PartyHorn change xcodebuild handles it. Mixed sets run both, with swift test acting as an early fail-fast signal.

```bash
scripts/test-affected.sh                              # affected tests since origin/master
scripts/test-affected.sh --base-ref HEAD              # only working-tree changes
scripts/test-affected.sh --simulator name=iPhone\ 17  # name= or id=<UUID>
scripts/test-affected.sh --dry-run                    # print commands, don't execute
scripts/test-affected.sh --full                       # force the full xcodebuild plan
scripts/test-affected.sh --skip-spm                   # skip swift test, only xcodebuild
```

Fail-open: if the base ref can't be resolved or app code (`WXYC/**`) / the project file / the test plan changed, the script falls back to the full xcodebuild plan, matching CI semantics. Working-tree edits, staged changes, and untracked non-ignored files are all considered. The diff uses `git merge-base` rather than two-dot, so a branch behind master doesn't pull phantom changes from master commits into its affected set.

SPM-runnable packages (host-tested via `swift test`): AnalyticsMacros, Core, Caching, Analytics, Playlist, LikedSongs, Metadata, MusicShareKit, Concerts, WXUI. Every package on this list is expected to pass `scripts/verify-spm-parity.sh` — its host `swift test` count must match what the same test target executes in the iOS Simulator, so a package can't be silently skipping real coverage while still showing green. Most of the remainder fall through to xcodebuild, each for its own reason (kept in sync with the exclusion comment above `SPM_RUNNABLE` in `.github/scripts/affected-tests.sh`, the source of truth): Playback (dozens of `#if canImport(UIKit)`/`os()` platform gates silently skip on the macOS host — a large-scale version of the ColorPalette failure mode below — plus a separate MP3Streamer state-tracking divergence between macOS host AudioToolbox and the iOS simulator), ColorPalette (`DominantColorExtractor` is `#if canImport(UIKit)`-gated and silently skips on the macOS host, #394), Artwork (`swift test` hangs indefinitely on macos-latest after linking ArtworkPackageTests), Intents (an ~18-test gap between declared and host-executed counts, not yet root-caused), AppServices (`MockURLProtocol` static-handler + `WidgetCenter` cause host hangs), PartyHorn (Bundle.module), PlayerHeaderView / Wallpaper (submodule), DebugPanel (`CADisplayLink(target:selector:)` and `.textInputAutocapitalization` are both unavailable on the macOS host, so the package doesn't build there at all). **Logger is the one exception that does not fall through to xcodebuild**: `LoggerTests` (16 tests, excluded from `SPM_RUNNABLE` for a shared-state race in `Logger.addDestination`) is also absent from `WXYC.xctestplan`'s targets, so it currently runs in no CI configuration at all — tracked in #800, not yet fixed.

To wire it into a pre-push hook so unsaved tests block the push, set `core.hooksPath` once at the repo or global scope so the hook fires from every worktree:

```bash
git config core.hooksPath scripts/hooks
```

Or, for the main worktree only, symlink in place:

```bash
ln -s ../../scripts/hooks/pre-push .git/hooks/pre-push
```

The hook derives its diff base from the ref data git pipes on stdin (the remote's current sha for the ref being updated) rather than hardcoding `origin/master`, so it scopes correctly for a push to a fork, a non-master tracking branch, or a same-ref push. On a brand-new branch (no remote ref yet) it falls back to the local branch's configured upstream, or `scripts/test-affected.sh`'s own `origin/master` default if there is none; a pure branch-delete push skips validation entirely.

Skip a single push with `git push --no-verify`, or globally with `git config wxyc.skipTests true`.

### Testing the build scripts themselves

`.github/scripts/affected-tests.sh` decides which tests run for every change in this repo, so a regression in it does not fail loudly — it silently runs fewer tests than it should. The Sentry dSYM upload has the same shape: when it breaks, the build stays green and the symbols merely never arrive. The shell suites listed below cover that family of scripts. They auto-run on `pull_request` via `.github/workflows/shell-script-tests.yml` — a separate, much lighter workflow than `build-and-test.yml` (no Xcode, no simulator, no submodule; the whole set runs in under two seconds), which is why it can auto-run when `build-and-test.yml` deliberately stays `workflow_dispatch`-only. Run them by hand after touching any of the scripts they cover:

```bash
zsh .github/scripts/tests/test-affected-tests.sh    # affected-tests.sh: pbxproj classification, whitespace input, output() guard
zsh scripts/tests/test-pre-push-hook.sh             # scripts/hooks/pre-push: BASE_REF derivation from git's stdin protocol
zsh scripts/tests/test-affected-error-fallback.sh   # test-affected.sh: CoreTests coverage when affected-tests.sh itself crashes
zsh scripts/tests/test-upload-debug-symbols.sh      # upload-debug-symbols.sh: archive-errors/build-warns, and the no-dSYM exemption
zsh scripts/tests/test-install-sentry-cli.sh        # install-sentry-cli.sh: version pinning, idempotency, ~/.sentryclirc handling
```

They are dependency-free (no bats) and share their assertions — `ok`/`fail`/`expect_*`/`summarize` live in `scripts/tests/harness.zsh`, which every suite sources — so they print the same TAP-ish `ok -` / `FAIL -` lines and exit nonzero on any failure. They build throwaway fixtures in `mktemp -d`, so they never touch the working tree — the two sentry-cli suites also stub the download and the binary, and redirect `HOME`, so they neither hit the network nor go near a real auth token.

One case deserves care when editing `is_pbxproj_change_structural`: it compares *sorted structural fingerprints* of the two file versions rather than grepping the textual diff for marker keywords, because the array a membership entry lives in can be dozens of lines long and the keyword only appears on the array's unchanged declaration line. A fixture whose `membershipExceptions` array is short enough to keep that line inside git's 3 lines of context will pass while the real `WXYC.xcodeproj` fails. The suite pins mid-array add, mid-array remove, and cross-target move for exactly this reason.

### Running the full plan directly (mind the two flags)

Prefer `scripts/test-affected.sh --full` over invoking `xcodebuild test -scheme WXYC` by hand. A bare `xcodebuild test -scheme WXYC` is a trap: it runs the whole `WXYC.xctestplan`, including tests the sanctioned runs deliberately exclude, so it fails with confusing "environmental" errors that aren't real defects. To match what CI and `test-affected.sh` actually run, pass both:

```bash
TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1 xcodebuild test -scheme WXYC \
    -destination 'platform=iOS Simulator,id=<UUID>' \
    -skip-testing:WXYCUITests
```

- `TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1` — one env var, two unrelated causes. It skips the genuinely load-flaky suites tracked by #371 (Widget relevance, stream-error analytics, render-tap teardown, in `Shared/Playback` / `Shared/AppServices`), *and* the six `MusicShareKit` tests that need a Keychain entitlement the SPM unit-test bundle lacks on the simulator (`errSecMissingEntitlement`). Those six are **not** part of #371 and are not flaky — they fail deterministically on this path and pass every time on the `swift test` host path, which is how CI covers them. xcodebuild strips the `TEST_RUNNER_` prefix when forwarding to the simulator test runner, so the plain env var reaches the tests. Without it, `KeychainTokenStorageTests` / `DeviceFingerprintTests` fail on every run. (CI's own xcodebuild step excludes `MusicShareKitTests` outright, so this half of the var only matters locally.)
- `-skip-testing:WXYCUITests` — the UI tests need live-stream network egress and a foregrounded app; they are not part of the default batch. Both CI and `test-affected.sh` skip them. Run them explicitly per the [UI Tests](#ui-tests) section below.

Note that `scripts/test-affected.sh` does **not** set the flake-skip var itself — only CI does. When its affected set includes an xcodebuild-path package (Playback, Artwork, ColorPalette, Intents, AppServices, PartyHorn, PlayerHeaderView, Wallpaper) or you pass `--full`, export it yourself first — and, per the [xcodebuild flag above](#running-the-full-plan-directly-mind-the-two-flags), it needs the `TEST_RUNNER_` prefix for that path (`export TEST_RUNNER_WXYC_SKIP_KNOWN_FLAKES=1`), not the bare name. The bare `WXYC_SKIP_KNOWN_FLAKES=1` only reaches tests on the `swift test` host path (SPM-runnable packages); xcodebuild strips the `TEST_RUNNER_` prefix on its way into the simulator test runner, so exporting the bare var for an xcodebuild-path run does nothing and the Keychain/DeviceFingerprint tests fail with `errSecMissingEntitlement` as if the skip were never set. The script already handles `-skip-testing:WXYCUITests` for you.

## Building

```bash
# After cloning, initialize the Wallpaper submodule
git submodule update --init --recursive

# Build for device
xcodebuild -scheme WXYC -destination 'generic/platform=iOS'

# Build for simulator
xcodebuild -scheme WXYC -destination 'platform=iOS Simulator,name=iPhone Air'
```

## The Xcode 27 Beta Toolchain

`Shared/Intents` has eight `#if compiler(>=6.4)` gates in `Sources/Intents` and four more in `Tests/WXYCIntentsTests`, guarding AppIntents APIs (the `.audio` AppIntents schema, `IndexedEntityQuery` reindexing, etc.) that only exist in the Xcode 27 beta SDK. `#if compiler(>=X.Y)` keys off the compiler binary doing the compiling, not the deployment target or the simulator/device you build for — a routine build with the stable toolchain never even type-checks the gated block, regardless of which simulator you point it at.

**Location and versions.** The beta lives at `/Applications/Xcode-beta.app`, side by side with the stable install. Verified 2026-08-11: `DEVELOPER_DIR=/Applications/Xcode-beta.app xcrun swiftc --version` reports `Apple Swift version 6.4 (swiftlang-6.4.0.27.1 …)` against an iOS 27.0 SDK (per `xcodebuild -showsdks`); the stable install reports `Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 …)`. A `#error`-in-both-branches probe compiled under each toolchain confirms `#if compiler(>=6.4)` evaluates false on stable and true on the beta — and confirms it identically whether the probe targets the macOS host or the iOS 27.0 simulator, which is the direct proof that the gate tracks the compiler, not the target.

**Select the beta via `xcodebuild`/`xcrun`, never bare `swift`/`swiftc`.** `DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild …` (or `xcrun swiftc …`) reliably dispatches to the beta compiler. Bare `swift`/`swiftc` do not: if a Swift toolchain manager (e.g. `swiftly`) is installed, its shim sits ahead of both Xcode installs on `$PATH` and silently ignores `DEVELOPER_DIR`, routing instead to whatever toolchain it has configured as its own default — a third toolchain, unrelated to either Xcode install. Confirmed on this machine 2026-08-11: `which swift` resolved to `~/.swiftly/bin/swift`, and a `DEVELOPER_DIR`-prefixed bare `swiftc` call against a `#if compiler(>=6.4)` probe returned the *same* (wrong, stable-like) result whether `DEVELOPER_DIR` pointed at the stable install or the beta — both invocations were silently landing on the swiftly-managed toolchain instead. `which swift` / `which swiftc` reveals the interception; `xcrun -f swiftc` under the desired `DEVELOPER_DIR` shows the binary that will actually run.

**Host `swift build`/`swift test` can fail under the beta for a real, unrelated reason — not a broken SDK.** `Shared/Intents/Package.swift` declares `.macOS(.v15)` as its platform floor (macOS isn't Intents' real target; the floor exists for other code in the package). The beta SDK's `AppIntents.audio` schema symbols that the `#if compiler(>=6.4)` gates reference are `@available(macOS 27.0, *)`. A **host** build (`swift build`/`swift test`, which always compiles for the Mac you're running on, ignoring the package's `.iOS` platform entry) type-checks the gated code against that macOS 15 floor and fails — e.g. `'audio' is only available in macOS 27.0 or newer` — even though the declarations are correctly annotated `@available(iOS 27.0, *)` for their real, iOS deployment target. Reproduced 2026-08-11 via `DEVELOPER_DIR=/Applications/Xcode-beta.app xcrun swift build --package-path Shared/Intents`; passing an explicit `-Xswiftc -target` does **not** fix it — SwiftPM recomputes its own `-target` flag from `Package.swift` and silently drops the override.

**This is not why `Intents` is excluded from `SPM_RUNNABLE`,** and it is worth being explicit about that, because the two facts sit next to each other and invite the wrong inference. The exclusion is for an unrelated 18-to-20-test gap between the declared suite and what runs on host, cause not root-caused — `.github/scripts/affected-tests.sh` says so in as many words ("Excluded pending investigation, not because of a confirmed platform-gate skip like ColorPalette/Playback"), and that remains the authoritative statement. The beta failure described here *cannot* be a reason for it: CI and every routine local run use the stable toolchain, where `#if compiler(>=6.4)` is false and the gated code is never compiled at all. See [Affected-only test runs](#affected-only-test-runs-scriptstest-affectedsh) above. The iOS **simulator** path is unaffected — there the deployment target is `.iOS("18.4")` and the local `@available(iOS 27.0, *)` annotation is the only gate that applies — which is how the shipped features behind these gates were actually built and verified: via `xcodebuild` against an iOS 27.0 simulator, never via a host `swift build`.

The load-bearing input above is the *annotation set on the six `.audio`-schema declarations*, not the package's macOS floor: `AudioItem`, `LiveRadioStationEntity`, `PlayWXYCAudio`, `PlaybackAttributes`, `QueueInsertionLocation`, and `WarmupAudioQueueResult` are each `@available(iOS 27.0, *)` with no macOS platform, so on a host build there is no macOS version above which the compiler will accept the reference. Widening those six to include macOS is therefore the fix, and it removes the host-build failure this section describes.

Treat that as the state of `Shared/Intents` on 2026-08-11 and re-check with `git grep '@available(iOS 27.0' Shared/Intents/Sources` before relying on it. Expect a **mixed** result, and read the split rather than the count: the two `IndexedEntityQuery` reindexing files already carry `@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)` and are not part of this failure. The question is only whether the six named above still lack `macOS`. When they no longer do, this failure mode is gone and only the `#if compiler(>=6.4)` half of this section still applies.

## E2E Tests

E2E tests tagged with `.e2e` hit real backends or real CoreAudio/AVAudioEngine and are skipped by default. Currently gated:

- `MusicShareKitTests/AuthNetworkClient E2E Tests` — real Backend-Service auth endpoint
- `WXYCTests/PlayWXYC Intent Tests` — singleton `AudioPlayerController.shared` with real network playback
- `PlaybackTests/AudioEnginePlayer Tests` — real `AVAudioEngine` lifecycle (hangs on the paravirt CI simulator)
- `PlaybackTests/MP3StreamDecoder Tests` — real `AVAudioConverter` with 30-120s decode timeouts
- `PlaybackTests/AudioEnginePlayer Analytics Tests` — real `AVAudioEngine` analytics path

Run them on demand by setting `RUN_E2E=1`:

```bash
# swift test (host): plain env var
RUN_E2E=1 swift test --package-path Shared/MusicShareKit --filter AuthNetworkClient

# xcodebuild test (sim): needs TEST_RUNNER_ prefix — xcodebuild strips it
# when forwarding to the simulator test runner.
TEST_RUNNER_RUN_E2E=1 xcodebuild test -scheme WXYC \
    -destination 'platform=iOS Simulator,name=iPhone Air' \
    -only-testing:'PlaybackTests/AudioEnginePlayer Tests'
```

## UI Tests

See `WXYC/iOS/Tests/WXYCUITests/README.md` for UI test documentation.

```bash
# Run UI tests
xcodebuild test -scheme WXYC -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:WXYCUITests
```
