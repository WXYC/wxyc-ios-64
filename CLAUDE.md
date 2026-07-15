# WXYC iOS App - Claude Code Instructions

## Project Overview

WXYC is the iOS app for WXYC 89.3 FM, the student-run radio station at UNC Chapel Hill, written in Swift, SwiftUI, and Metal. It also supports tvOS, watchOS, and macOS (designed for iPad).

## Topic guides

CLAUDE.md is a router for the always-loaded reference card. Topic depth lives in `docs/`:

- **[`docs/architecture.md`](docs/architecture.md)** — Modular Swift packages in `Shared/`, the `Singletonia` app entry point, DI/`@Observable`/async-await/MainActor patterns, and a map of the most important files in the codebase
- **[`docs/swift-style.md`](docs/swift-style.md)** — Swift 6.2 conventions: `Observations`/AsyncStream over closures, modern Foundation API, no GCD, no force-unwraps, swift-atomics over NSLock, `DefaultsStorage` injection for persistence
- **[`docs/swiftui.md`](docs/swiftui.md)** — SwiftUI conventions: `foregroundStyle`/`clipShape(.rect)`/`Tab`/`@Observable`/`NavigationStack`, no `ObservableObject`/`onTapGesture`/`GeometryReader`/`Task.sleep(nanoseconds:)`, view-logic into view models
- **[`docs/build-test.md`](docs/build-test.md)** — `xcodebuild` invocations for device/simulator builds, running `WXYC.xctestplan`, opt-in E2E tests via `RUN_E2E=1`, and the UI-test entry point
- **[`docs/configuration.md`](docs/configuration.md)** — `AppConfiguration` (PostHog/API/request-o-matic), code-signing (team `92V374HC38`, automatic), extension targets (Share/Widget/CarPlay), widget refresh budget, App Store previews, minimum iOS version
- **[`docs/project-structure.md`](docs/project-structure.md)** — Folder layout, the `project.pbxproj` editing playbook (xcodeproj/pbxproj fragility, line-by-line brace-counting fallback, UUID coordination, `xcodebuild -list` validation), naming, one-type-per-file
- **[`docs/file-headers.md`](docs/file-headers.md)** — Standard Swift/Metal file header comment template and the `scripts/hooks/header-check.sh` pre-commit hook that enforces it
- **[`docs/test-fixtures.md`](docs/test-fixtures.md)** — Preferred `Playcut.stub()` / `FlowsheetEntry` literals using WXYC-canonical tracks (Juana Molina, Stereolab, Cat Power, etc.) rather than generic "Test Artist" placeholders

Read the relevant topic doc before doing work in that area.

## Core instructions

- Target iOS 26.0 (yes, it definitely exists) or later, backporting APIs to a minimum of iOS 18.6 when necessary.
- Swift 6.2 or later, using modern Swift concurrency.
- SwiftUI backed up by `@Observable` classes for shared data.
- Do not introduce third-party frameworks without asking first.
- Avoid UIKit unless requested.
- There is no "iPhone 16 Pro" simulator. Simulator B49BE311-B868-4E8B-AE14-85C159CAD776 should be available. Check the available simulators if not.

## Coding style

- Don't replace blank lines with blank lines.
- At the end of a file, there should be one and only one blank line.
- Infrastructure scripts go in `scripts/`. Xcode Cloud scripts go in `ci_scripts/`.

## Testing Standards

This project follows **Test-Driven Development (TDD)**. All code changes must be test-driven - this is not optional.

### TDD Workflow

1. **Red**: Write a failing test that describes the desired behavior. Run it and verify it fails for the expected reason (compile error for new API, assertion failure for bug fix).
2. **Green**: Write the minimum code necessary to make the test pass. Run the test and confirm it passes.
3. **Refactor**: Look for opportunities to improve the code while keeping tests green. Re-run tests after each change.
4. **Repeat**: Continue this cycle until the feature is complete.

**Key principle**: No production code without a failing test first.

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
