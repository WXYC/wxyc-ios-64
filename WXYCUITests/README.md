# iOS UI Integration Tests

## Overview

This directory contains UI integration tests for the WXYC iOS app. These tests verify that the user interface responds correctly to state changes, particularly around observation behavior.

## Test Files

### `PlaybackUITests.swift`
Existing tests for basic playback functionality and crash prevention.

### `PlaybackButtonObservationUITests.swift` (TODO)
UI integration tests for PlaybackButton and CarPlay observation behavior.

**Status:** Template created, tests need implementation

**What needs to be tested:**
1. PlaybackButton visual state updates correctly
2. State synchronization between AudioPlayerController and UI
3. Rapid interaction handling
4. State persistence across backgrounding
5. Animation smoothness
6. CarPlay template updates
7. Cross-component state synchronization

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

## Implementation Priority

1. **High Priority:**
   - `playbackButtonVisualStateUpdates()` - Core functionality
   - `playbackButtonStateSyncs()` - Verifies the observation fix works

2. **Medium Priority:**
   - `rapidTappingHandled()` - Edge case handling
   - `stateSurvivesBackgrounding()` - State persistence

3. **Low Priority:**
   - `animationPlaysSmooth()` - Polish
   - CarPlay tests - Feature-specific

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
