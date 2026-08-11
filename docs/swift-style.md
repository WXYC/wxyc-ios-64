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
- Protect shared mutable state with the `Synchronization` module, not `NSLock`. Reach for `actor` or `@MainActor` isolation first — a lock is for state that must stay readable from synchronous, non-isolated API. `Mutex` is `Sendable` when its `State` is, so a type holding one earns a checked conformance instead of an asserted `@unchecked Sendable`, and `withLock`'s non-escaping, non-async closure makes `await` inside a critical section a compile error. The ladder:
  - `Mutex<State>` by default, with the state held *inside* it rather than a bare lock sitting beside the `var`s it notionally guards.
  - `Atomic<T>` for a single scalar with no invariant to maintain.
  - `NSLock` only where the critical section genuinely cannot fit that closure — and say why in a comment.
  - `os_unfair_lock` only on realtime audio render paths (`MP3Streamer`).
  - Generated code under `Shared/WXYCAPIModels/Infrastructure/` is exempt; openapi-generator ships its own `OpenAPIMutex` and hand edits are lost on regeneration.
  - Migrate existing `NSLock` sites opportunistically, when you are already editing the file — not in a sweep.
- When writing test suites, please put mocks and other ancilliary objects below the tests.
- Inject `DefaultsStorage` (from Caching) for persistence instead of accessing `UserDefaults.standard` or `.wxyc` directly. This enables parallel test execution via `InMemoryDefaults`. Exception: widgets may use `@AppStorage` with the app group store.
- Pick the persistence layer by the data's eviction contract: `DefaultsStorage` and the `Caching` package are for small prefs and re-derivable caches (Caching purges infinite-lifespan entries at init and TTL-expires finite ones). Durable, never-evict user data — data the app cannot re-derive, like liked songs or dismissed shows — uses the `FileStorage` seam (`Shared/Core`): a Codable JSON file in Application Support with atomic write-through and a `CoreTesting`-provided `InMemoryFileStorage` test double.
