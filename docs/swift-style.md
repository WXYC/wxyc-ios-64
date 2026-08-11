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
- Protect shared mutable state with the `Synchronization` module, not `NSLock`. Reach for `actor` or `@MainActor` isolation first — a lock is for state that must stay readable from synchronous, non-isolated API. `Mutex` is `Sendable` for *every* `Value`, including a non-`Sendable` one (`extension Mutex: @unchecked Sendable where Value: ~Copyable`), which is the whole point: wrapping non-`Sendable` state is what it is for, so your type gets a `Sendable` conformance without itself asserting `@unchecked` — the unsafety lives in the stdlib's audited primitive rather than in your code. `withLock`'s non-escaping, non-async closure additionally makes `await` inside a critical section a compile error. The ladder:
  - `Mutex<Value>` by default. It is `~Copyable`, so it must live in a `final class` (or a `~Copyable` struct) — a stored `Mutex` in an ordinary struct is a hard compile error, not a style question. Hold the state *inside* it rather than beside it.
  - `Atomic<Value>` for a single scalar with no invariant to maintain. Unlike `Mutex`, `Atomic` *is* conditionally `Sendable` (`where Value: Sendable`), and every operation takes an explicit `ordering:` — there is no default. If you need an ordering stronger than `.relaxed`, you have an invariant; use `Mutex`.
  - `NSLock`, `NSRecursiveLock`, and `pthread_mutex` only for what `Mutex` structurally cannot do: storage in a `Copyable` struct, recursive acquisition, or a `lock()`/`unlock()` pair split across function boundaries. Name which one in a comment. "The critical section can't fit a closure" is not a reason — `NSLock.withLock` has the same non-escaping, non-async shape `Mutex.withLock` does.
  - `os_unfair_lock` only on realtime audio render paths (`MP3Streamer`).
  - Generated code under `Shared/WXYCAPIModels/Sources/WXYCAPIModels/Infrastructure/` is exempt; openapi-generator ships its own `NSRecursiveLock`-backed `OpenAPIMutex` and hand edits are lost on regeneration.
  - Migrate existing `NSLock` sites opportunistically, when you are already editing the file — not in a sweep.
- When writing test suites, please put mocks and other ancilliary objects below the tests.
- Inject `DefaultsStorage` (from Caching) for persistence instead of accessing `UserDefaults.standard` or `.wxyc` directly. This enables parallel test execution via `InMemoryDefaults`. Exception: widgets may use `@AppStorage` with the app group store.
- Pick the persistence layer by the data's eviction contract: `DefaultsStorage` and the `Caching` package are for small prefs and re-derivable caches (Caching purges infinite-lifespan entries at init and TTL-expires finite ones). Durable, never-evict user data — data the app cannot re-derive, like liked songs or dismissed shows — uses the `FileStorage` seam (`Shared/Core`): a Codable JSON file in Application Support with atomic write-through and a `CoreTesting`-provided `InMemoryFileStorage` test double.
