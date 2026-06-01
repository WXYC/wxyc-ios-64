# Build & Test Commands

## Running Tests

Run WXYC.xctestplan.

### Affected-only test runs (`scripts/test-affected.sh`)

Mirrors CI's affected-tests filtering for local iteration: diffs the working tree against `origin/master`, maps changed `Shared/<pkg>/` paths through the same dependency graph used by `.github/scripts/affected-tests.sh`, and runs only the test targets whose package or transitive dependents were touched.

Two-step execution:

1. **swift test (host, fast):** runs `swift test --package-path Shared/<pkg>` for each affected SPM-runnable package. Skips xcodebuild and simulator entirely. Also covers CoreTests when Core is affected — the Swift Testing parallel-scheduler hang only triggers in the xcodebuild + simulator path, not on host.
2. **xcodebuild test (simulator):** runs only when the affected set includes a non-SPM-runnable package (PartyHorn, MusicShareKit, PlayerHeaderView, Wallpaper, AppServices) or when `--full` is forced. Scoped via `-only-testing` to just the affected app/UI targets.

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

SPM-runnable packages (host-tested via `swift test`): AnalyticsMacros, Core, Caching, Analytics, ColorPalette, Playlist. The remainder fall through to xcodebuild: Logger (shared-state race in `Logger.addDestination` across parallel test suites), Playback (MP3Streamer state-tracking diverges between macOS host AudioToolbox and the iOS simulator), Artwork (swift test hangs indefinitely on macos-latest after linking ArtworkPackageTests), Metadata (untested on CI virtualization; deferred until Artwork's hang is diagnosed), AppServices (`MockURLProtocol` static-handler race), PartyHorn (Bundle.module), MusicShareKit (SwiftUI `#Preview`), PlayerHeaderView / Wallpaper (submodule).

To wire it into a pre-push hook so unsaved tests block the push, set `core.hooksPath` once at the repo or global scope so the hook fires from every worktree:

```bash
git config core.hooksPath scripts/hooks
```

Or, for the main worktree only, symlink in place:

```bash
ln -s ../../scripts/hooks/pre-push .git/hooks/pre-push
```

Skip a single push with `git push --no-verify`, or globally with `git config wxyc.skipTests true`.

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

E2E tests tagged with `.e2e` (e.g., `MusicShareKitTests/AuthNetworkClientE2ETests`) hit real backends and are skipped by default. Run them on demand by setting `RUN_E2E=1`:

```bash
RUN_E2E=1 xcodebuild test -scheme WXYC \
    -destination 'platform=iOS Simulator,name=iPhone Air' \
    -only-testing:MusicShareKitTests/AuthNetworkClientE2ETests
```

## UI Tests

See `WXYC/iOS/Tests/WXYCUITests/README.md` for UI test documentation.

```bash
# Run UI tests
xcodebuild test -scheme WXYC -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:WXYCUITests
```
