# iOS UI Integration Tests

## Overview

This directory contains UI integration tests for the WXYC iOS app. These tests verify that the user interface responds correctly to state changes, particularly around observation behavior.

## Test Files

### `PlaybackUITests.swift`
Existing tests for basic playback functionality and crash prevention.

### `PlaybackButtonObservationUITests.swift`
UI integration tests for PlaybackButton and CarPlay observation behavior.

**PlaybackButton tests (implemented):**
- `playbackButtonVisualStateUpdates()` - Verifies button state changes on tap
- `playbackButtonStateSyncs()` - Verifies UI stays in sync with AudioPlayerController
- `rapidTappingHandled()` - Verifies app handles rapid button taps without issues
- `stateSurvivesBackgrounding()` - Verifies state persists across app backgrounding
- `animationPlaysSmooth()` - Verifies animations complete without issues

**CarPlay tests (disabled - requires manual testing):**
- CarPlay UI automation is not available in standard XCUITest runs
- Use Xcode's CarPlay Simulator for manual testing
- See test file for manual testing steps

## Running UI Tests

### Via Xcode
1. Select the WXYC scheme
2. Choose a simulator or device
3. Product → Test (⌘U)

### Via Command Line
```bash
# Run all UI tests
xcodebuild test \
  -scheme WXYC \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:WXYCUITests

# Run specific test suite
xcodebuild test \
  -scheme WXYC \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:WXYCUITests/PlaybackButtonObservationUITests
```

## Related Tests

**Unit/Integration Tests:** Located in `WXYC/Shared/StreamingAudioPlayer/Tests/`
- `ObservationBugTests.swift` - Proves the observation bug exists
- `ObservationTestHarness.swift` - Compares observation strategies  
- `CrossPlatformObservationTests.swift` - Platform compatibility

**Documentation:**
- `WXYC/Shared/StreamingAudioPlayer/Tests/StreamingAudioPlayerTests/OBSERVATION_TESTING_GUIDE.md`
- `WXYC/Shared/StreamingAudioPlayer/Tests/StreamingAudioPlayerTests/TESTING_SUMMARY.md`

## Notes

- UI tests are slower than unit tests
- Run unit tests first to catch observation bugs early
- UI tests verify the fix actually works in the real app
- Use accessibility identifiers for reliable element selection
