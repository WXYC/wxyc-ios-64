# Project Structure

- Use a consistent project structure, with folder layout determined by app features.
- When modifying the project file (`project.pbxproj`):
  - The Ruby `xcodeproj` gem and Python `pbxproj` library may fail on complex projects due to parsing incompatibilities.
  - If libraries fail, use line-by-line text processing: the pbxproj format is indentation-based and predictable.
  - Use brace counting (`{`/`}`) to capture complete configuration blocks.
  - When duplicating entries (e.g., build configurations), generate UUIDs upfront so references in `XCConfigurationList` match the definitions.
  - Always validate after modifying: `xcodebuild -project WXYC.xcodeproj -list` should show the expected configurations/schemes.
  - A local package under `Shared/` needs **two** references, not one: an `XCLocalSwiftPackageReference` in the project's `packageReferences`, **and** a folder-typed `PBXFileReference` (`lastKnownFileType = folder`) listed in the `Packages` `PBXGroup`. The group entry looks like navigator decoration but is load-bearing: without it `xcodebuild` resolves the package as a plain path dependency — `xcodebuild -list` annotates it `@ local` — instead of one of the project's own packages, and its test target then cannot be selected at all. `-only-testing:<Pkg>Tests` fails with "isn't a member of the specified test plan or scheme" even when `WXYC.xctestplan` lists the target (#809). After any package wiring change, check that the package is absent from the `@ local` list in `xcodebuild -list`; the only two entries that belong there are `AnalyticsMacros` and `WXYCAPIModels`, which are consumed solely as path dependencies of other packages and have no test target in the plan.
- Use xcodeproj when modifying frameworks referenced in the Xcode project file.
- Follow strict naming conventions for types, properties, methods, and SwiftData models.
- Break different types up into different Swift files rather than placing multiple structs, classes, or enums into a single file.
- Write unit tests for core application logic.
- Only write UI tests if unit tests are not possible.
- Add code comments and documentation comments as needed.
- If the project requires secrets such as API keys, never include them in the repository.

## Linking a package product into more than one target

When one package product is linked into more than one target (for example `PlaylistTesting` into both the app and `WXYCTests`), SwiftPM builds that package's dependency closure (`Playlist`, `Analytics`, `PostHog`) as dynamic frameworks. A target that does `import PostHog` but only reached it transitively then fails to link, with an undefined-symbol or missing-module error on the transitively imported module. The fix is to declare that product explicitly on the target that imports it, as PR #1246 did for the app and the Now Playing widget.

`posthog-ios` is required in two places that cannot read each other: `Shared/Analytics/Package.swift` and the `XCRemoteSwiftPackageReference "posthog-ios"` in `WXYC.xcodeproj/project.pbxproj` (`minimumVersion`). Bump both together; `scripts/verify-posthog-floor.sh` fails when they differ and runs in the Shell Script Tests workflow.

