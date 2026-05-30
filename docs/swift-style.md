# Swift Style

## Swift instructions

- Prefer Swift 6.2's `Observations` type and AsyncIterator/AsyncStream over closure-based callback handlers. It's okay to use closure-based handlers for simple things like button presses (e.g., `onButtonTapped`). `Observations.swift` exists in the repository to make this API available to iOS 18+.
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
