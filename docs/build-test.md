# Build & Test Commands

## Running Tests

Run WXYC.xctestplan.

### Affected-only test runs (`scripts/test-affected.sh`)

Mirrors CI's affected-tests filtering for local iteration: diffs the working tree against `origin/master`, maps changed `Shared/<pkg>/` paths through the same dependency graph used by `.github/scripts/affected-tests.sh`, and runs only the test targets whose package or transitive dependents were touched.

```bash
scripts/test-affected.sh                              # affected tests since origin/master
scripts/test-affected.sh --base-ref HEAD              # only working-tree changes
scripts/test-affected.sh --simulator name=iPhone\ 17  # name= or id=<UUID>
scripts/test-affected.sh --dry-run                    # print xcodebuild command, don't execute
scripts/test-affected.sh --full                       # force the full plan (skip affected logic)
scripts/test-affected.sh --no-core                    # skip the CoreTests step
```

Fail-open: if the base ref can't be resolved or app code (`WXYC/**`) / the project file / the test plan changed, the script falls back to the full plan, matching CI semantics. Working-tree edits, staged changes, and untracked non-ignored files are all considered.

To wire it into a pre-push hook so unsaved tests block the push:

```bash
ln -s ../../scripts/hooks/pre-push .git/hooks/pre-push
```

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
