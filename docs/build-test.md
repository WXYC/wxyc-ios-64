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

SPM-runnable packages (host-tested via `swift test`): AnalyticsMacros, Core, Caching, Analytics, Playlist, LikedSongs, Metadata, MusicShareKit, Concerts, WXUI. Every package on this list is expected to pass `scripts/verify-spm-parity.sh` — its host `swift test` count must match what the same test target executes in the iOS Simulator, so a package can't be silently skipping real coverage while still showing green. Most of the remainder fall through to xcodebuild, each for its own reason (kept in sync with the exclusion comment above `SPM_RUNNABLE` in `.github/scripts/affected-tests.sh`, the source of truth): Playback (dozens of `#if canImport(UIKit)`/`os()` platform gates silently skip on the macOS host — a large-scale version of the ColorPalette failure mode below — plus a separate MP3Streamer state-tracking divergence between macOS host AudioToolbox and the iOS simulator), ColorPalette (`DominantColorExtractor` is `#if canImport(UIKit)`-gated and silently skips on the macOS host, #394), Artwork (`swift test` hangs indefinitely on macos-latest after linking ArtworkPackageTests), Intents (an ~18-test gap between declared and host-executed counts, not yet root-caused), AppServices (`MockURLProtocol` static-handler + `WidgetCenter` cause host hangs), PartyHorn (Bundle.module), PlayerHeaderView / Wallpaper (submodule). **Logger is the one exception that does not fall through to xcodebuild**: `LoggerTests` (16 tests, excluded from `SPM_RUNNABLE` for a shared-state race in `Logger.addDestination`) is also absent from `WXYC.xctestplan`'s targets, so it currently runs in no CI configuration at all — tracked in #800, not yet fixed.

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

### Testing the test-selection scripts themselves

`.github/scripts/affected-tests.sh` decides which tests run for every change in this repo, so a regression in it does not fail loudly — it silently runs fewer tests than it should. Two shell suites cover it, and neither is wired into a workflow (`build-and-test.yml` is `workflow_dispatch`-only). Run them by hand after touching either script:

```bash
zsh .github/scripts/tests/test-affected-tests.sh   # affected-tests.sh: pbxproj classification, whitespace input, output() guard
zsh scripts/tests/test-pre-push-hook.sh            # scripts/hooks/pre-push: BASE_REF derivation from git's stdin protocol
```

Both are dependency-free (no bats), print TAP-ish `ok -` / `FAIL -` lines, and exit nonzero on any failure. They build throwaway git repos in `mktemp -d`, so they never touch the working tree.

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
