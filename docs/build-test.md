# Build & Test Commands

## Running Tests

Run WXYC.xctestplan.

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
