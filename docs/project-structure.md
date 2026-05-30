# Project Structure

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
