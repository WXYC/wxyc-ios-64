# WXYC iOS App - Claude Code Instructions

## Project Overview

WXYC is the iOS app for WXYC 89.3 FM, the student-run radio station at UNC Chapel Hill, written in Swift, SwiftUI, and
Metal. It also supports tvOS, watchOS, and macOS (designed for iPad).

## Core instructions

- Target iOS 26.0 (yes, it definitely exists) or later, backporting APIs to a minimum of iOS 18.6 when necessary.
- Swift 6.2 or later, using modern Swift concurrency.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- Prefer a test-driven approach to making changes. The idea is that you write a failing test first, either because the code has a bug, or it doesn't compile because it tests an API that doesn't yet exist. Then change the code under test.
- There is no "iPhone 16 Pro" simulator. Simulator 156E5217-1C62-4531-B8BE-B0299138F6DB should be available. Check the available simulators if not.

## Coding style
- Don't replace blank lines with blank lines.
- At the end of a file, there should be one and only one blank line.
- Infrastructure scripts go in `scripts/`. Xcode Cloud scripts go in `ci_scripts/`.

## File headers

All Swift and Metal files (except `Package.swift`) must have a standard header comment:

```swift
//
//  Filename.swift
//  PackageName
//
//  Brief description of what this file does and how it fits into its package.
//
//  Created by Author Name on MM/DD/YY.
//  Copyright © YYYY WXYC. All rights reserved.
//
```

When creating new files:
- Use today's date for "Created by"
- Use the current year for copyright
- The package name should match the Swift package or "WXYC" for app files
- Always include a description explaining the file's purpose

The pre-commit hook (`scripts/hooks/header-check.sh`) validates headers and can use Claude to generate missing descriptions automatically.

## Swift instructions

- Prefer Swift 6.2's `Observations` type and AsyncIterator/AsyncStream over closure-based callback handlers. It's okay to use closure-based handlers for simple things like button presses (e.g., `onButtonTapped`). `Observations.swift` exists in the repository to make this API available to iOS 18+.
- Use a test-driven approach to changing and writing new code. Write a failing test, and then make the change you intend to write.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Avoid using the `return` keyword if you can.
- For protecting simple accesses to a variable in a multithreaded context, prefer swift-atomics over NSLock.
- When writing test suites, please put mocks and other ancilliary objects below the tests.
- Inject `DefaultsStorage` (from Caching) for persistence instead of accessing `UserDefaults.standard` or `.wxyc` directly. This enables parallel test execution via `InMemoryDefaults`. Exception: widgets may use `@AppStorage` with the app group store.

## SwiftUI instructions

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use `ObservableObject`; always prefer `@Observable` classes instead.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Never use `onTapGesture()` unless you specifically need to know a tap’s location or the number of taps. All other usages should use `Button`.
- Never use `Task.sleep(nanoseconds:)`; always use `Task.sleep(for:)` instead.
- Never use `UIScreen.main.bounds` to read the size of the available space.
- Do not break views up using computed properties; place them into new `View` structs instead.
- Do not force specific font sizes; prefer using Dynamic Type instead.
- Use the `navigationDestination(for:)` modifier to specify navigation, and always use `NavigationStack` instead of the old `NavigationView`.
- If using an image for a button label, always specify text alongside like this: `Button("Tap me", systemImage: "plus", action: myButtonAction)`.
- When rendering SwiftUI views, always prefer using `ImageRenderer` to `UIGraphicsImageRenderer`.
- Don’t apply the `fontWeight()` modifier unless there is good reason. If you want to make some text bold, always use `bold()` instead of `fontWeight(.bold)`.
- Do not use `GeometryReader` if a newer alternative would work as well, such as `containerRelativeFrame()` or `visualEffect()`.
- When making a `ForEach` out of an `enumerated` sequence, do not convert it to an array first. So, prefer `ForEach(x.enumerated(), id: \.element.id)` instead of `ForEach(Array(x.enumerated()), id: \.element.id)`.
- When hiding scroll view indicators, use the `.scrollIndicators(.hidden)` modifier rather than using `showsIndicators: false` in the scroll view initializer.
- Place view logic into view models or similar, so it can be tested.
- Avoid `AnyView` unless it is absolutely required.
- Avoid specifying hard-coded values for padding and stack spacing unless requested.
- Avoid using UIKit colors in SwiftUI code.

## Project structure

- Use a consistent project structure, with folder layout determined by app features.
- When modifying the project file (`project.pbxproj`):
  - The Ruby `xcodeproj` gem and Python `pbxproj` library may fail on complex projects due to parsing incompatibilities.
  - If libraries fail, use line-by-line text processing: the pbxproj format is indentation-based and predictable.
  - Use brace counting (`{`/`}`) to capture complete configuration blocks.
  - When duplicating entries (e.g., build configurations), generate UUIDs upfront so references in `XCConfigurationList` match the definitions.
  - Always validate after modifying: `xcodebuild -project WXYC.xcodeproj -list` should show the expected configurations/schemes.
- Use xcodeproj when modifying frameworks referenced in the Xcode project file.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.

## App Architecture

### Modular Swift Packages

The app uses a highly modular architecture with 19 local Swift packages in `Shared/`:

| Package | Purpose |
|---------|---------|
| **Analytics** | PostHog analytics wrapper |
| **AppServices** | App-level services (NowPlayingInfoCenter, background refresh) |
| **Artwork** | Album artwork fetching from multiple sources |
| **Caching** | Disk/memory caching with TTL support |
| **Core** | Core types (RadioStation, Playcut, etc.) |
| **Logger** | Logging infrastructure |
| **Metadata** | Playlist metadata parsing |
| **MusicShareKit** | Share extension support for music sharing |
| **Obfuscate** | ObfuscateMacro for API key protection |
| **OpenNSFW** | NSFW image detection for artwork filtering |
| **PartyHorn** | An easter egg. Users must scroll to the bottom of the playlist view and tap 'what the freq?' to access it.' |
| **Playback** | Houses several playback engines. Eventually this will whittle down to 1 or 2, but is currently in an experimental phase. |
| **PlayerHeaderView** | Now playing header UI component |
| **Playlist** | Playlist service and data models |
| **Secrets** | Generated file containing obfuscated API keys. Uses a precompiled Secrets.xcframework to avoid recompiling when the build cache is cleared. |
| **Wallpaper** | Metal shader-based animated backgrounds |
| **WXUI** | Shared SwiftUI components |

### App Entry Point

`WXYC/iOS/WXYCApp.swift` contains:
- `Singletonia` - Observable singleton holding shared state (PlaylistService, ArtworkService, WallpaperConfiguration)
- Environment injection pattern for dependency injection
- Background refresh scheduling (15-minute intervals via BGTaskScheduler)
- Widget refresh budget management

### Key Patterns

1. **Dependency Injection**: Services are injected via SwiftUI Environment
2. **@Observable**: Used for reactive state management (requires iOS 17+)
3. **Async/Await**: Modern concurrency throughout
4. **MainActor**: UI-bound code isolated to main actor

## Build & Test Commands

### Running Tests

Run WXYC.xctestplan.

### Building

```bash
# Build for device
xcodebuild -scheme WXYC -destination 'generic/platform=iOS'

# Build for simulator
xcodebuild -scheme WXYC -destination 'platform=iOS Simulator,name=iPhone Air'
```

### UI Tests

See `WXYC/iOS/Tests/WXYCUITests/README.md` for UI test documentation.

```bash
# Run UI tests
xcodebuild test -scheme WXYC -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:WXYCUITests
```

## Secrets Management

API keys are stored in `PROJECT_ROOT/../secrets/secrets.txt` and the Secrets package generates a git-ignored Secrets.swift file.

```bash
# Generate Secrets.swift from secrets.txt
./scripts/generate_secrets.sh
```

The generated file uses ObfuscateMacro to protect keys at compile time.

## Code Signing

- Development Team: `92V374HC38`
- Code Sign Style: Automatic
- All targets (including extensions) must have `DevelopmentTeam` in their TargetAttributes

### Extension Targets

- **Request Share Extension**: Share sheet integration for sharing songs
- **NowPlayingWidget**: Home screen widget showing current track
- **CarPlay**: CarPlay scene delegate in main app

## Important Files

| File | Description |
|------|-------------|
| `WXYC/iOS/WXYCApp.swift` | Main app entry point |
| `WXYC/iOS/Views/Root/RootTabView.swift` | Root navigation |
| `WXYC/iOS/Views/Root/BackgroundLayer.swift` | Animated background |
| `Shared/Playback/Sources/Playback/AudioPlayerController.swift` | Audio playback |
| `Shared/Playlist/Sources/Playlist/PlaylistService.swift` | Playlist fetching |
| `Shared/Artwork/Sources/Artwork/MultisourceArtworkService.swift` | Artwork fetching |

## Conventions

- Use `set up` (verb) not `setup` for method names (e.g., `setUpWidget`)
- Prefer editing existing files over creating new ones
- Use `git mv` when moving files to preserve history
- Check for staged files before committing
- Break multiple workstreams into separate commits in logical order
- Update existing documentation when making functional changes (not for bug fixes)

## Analytics

PostHog is used throughout. Key events:
- `app launch`
- `App entered background`
- `Background refresh completed`
- Error capture with context

## Widget Considerations

- Widget refresh budget: 40-70 updates/day
- Foreground refreshes don't count against budget
- Background refresh scheduled every 15 minutes
- OpenNSFW model seeded to shared container for widget access

## Minimum iOS Version

iOS 18.6 (based on SDK version in built app)
