# App Architecture

## Modular Swift Packages

The app uses a highly modular architecture with local Swift packages in `Shared/`. The Wallpaper package is a private git submodule sourced from `WXYC/wallpaper-ios`; run `git submodule update --init --recursive` after cloning.

| Package | Purpose |
|---------|---------|
| **Analytics** | PostHog analytics wrapper |
| **AnalyticsMacros** | `@AnalyticsEvent` macro (swift-syntax compiler plugin) that derives snake_case event names and `properties` from a type declaration |
| **AppServices** | App-level services: `AppConfiguration` (backend `/config` bootstrap), Spotlight indexing/donation for concerts and playcuts, App Store review prompts, On Tour alert scheduling, widget state/relevance, `NowPlayingService`, `MediaSuggestionService` (declares media-suggestion eligibility via `INMediaUserContext`/`INUpcomingMediaManager`, iOS-only) |
| **Artwork** | Album artwork fetching from multiple sources |
| **Caching** | Disk/memory caching with TTL support |
| **ColorPalette** | Dominant-color extraction and palette generation from artwork images; also the home for both of the codebase's hue-based color models — `HSBColor` (degree-based hue, bridges to UIKit/AppKit, backs the wallpaper theming system) and `HSL` (CSS `hsl()` semantics, for design-system colors transcribed from a spec) |
| **Concerts** | On Tour concert models, the dismissed-concerts store, and the Box Office ticket presenter |
| **Core** | Core types (RadioStation, Playcut, etc.); the `FileStorage`/`AppSupportFileStorage` durable never-evict byte-file seam (`CoreTesting` for the `InMemoryFileStorage` double), shared by LikedSongs and Concerts; dependency-free concurrency utilities (`LatestValueRelay` for ordered, latest-wins handoff of state out of a synchronous caller, `ForegroundVisibility` for reading a `ScenePhase` and `ForegroundSessionTracker` for collapsing a run of those into one measured on-screen span, alongside `Cancellation`/`TimedOperation`/`ExponentialBackoffTimer`) |
| **DebugPanel** | DEBUG-only settings/HUD panel: performance metrics overlay, feature toggles, cache purge |
| **Intents** | App Intents (`WXYCIntents` product): Siri/Spotlight entities and queries (PlayWXYC, artist/release/venue lookups). Also home to `PlayMediaIntentHandler` (#829) — the repo's first SiriKit `INPlayMediaIntentHandling` conformer, a different technology from App Intents, returned by `WXYC/iOS/AppDelegate.swift` so a media-suggestion tile's `INPlayMediaIntent` can dispatch in the background |
| **LikedSongs** | On-device liked-songs store (#492): folded song identity, durable never-evict JSON file store (Core's `FileStorage` seam), artist-id healing for the For You shelf |
| **Logger** | Logging infrastructure |
| **Metadata** | Playlist metadata parsing |
| **MusicShareKit** | Share extension support for music sharing |
| **PartyHorn** | An easter egg. Users must scroll to the bottom of the playlist view and tap 'what the freq?' to access it.' |
| **Playback** | Houses several playback engines. Eventually this will whittle down to 1 or 2, but is currently in an experimental phase. |
| **PlayerHeaderView** | Now playing header UI component |
| **Playlist** | Playlist service and data models |
| **Wallpaper** | Metal shader-based animated backgrounds (private submodule from `WXYC/wallpaper-ios`) |
| **WXUI** | Shared SwiftUI components (`StatusPill`, etc.), plus the on-air banner's SF Pro variable-font typography: `SFProVariation` and its axes, glyph metrics, the per-letter grade wave, and the width-axis fitter. Depends on nothing but system frameworks — keep it that way |
| **WXYCAPIModels** | Vendored, generated (openapi-generator) Swift models from `wxyc-shared`'s `api.yaml`. Models + Infrastructure only, no endpoint clients. Regenerate via `scripts/regenerate-api-types.sh`. Adopted at runtime by Metadata's album proxy and AppServices' `/config` bootstrap (#915), plus a PlaylistTests-only parity guard; further adoption is case-by-case per `docs/code-generation.md`. |

## App Entry Point

`WXYC/iOS/WXYCApp.swift` contains the app's `@main` entry point and:
- Environment injection pattern for dependency injection
- Background refresh scheduling (15-minute intervals via BGTaskScheduler); each refresh ingests the fetched playcuts into `PlaycutHistoryStore` directly before the Spotlight donation batch
- Widget refresh budget management

`WXYC/iOS/Singletonia.swift` contains `Singletonia` - Observable singleton holding shared state (PlaylistService, ArtworkService, WallpaperConfiguration, SpotlightDonationService, PlaycutHistoryStore — the Playlist package's persistent ~90-day playcut history + rotation set, built to enable the future Spotlight reindex handler)

## Key Patterns

1. **Dependency Injection**: four mechanisms, one job each. Reaching a single service through two of them at once is the recurring bug (WXYC/wxyc-ios-64#768) — `PlaylistView` used to hold both `@Environment(\.playlistService)` and `@Environment(Singletonia.self)`, where `Singletonia` already owned `playlistService`, and the environment key's silent `nil` default turned a missed injection into a view that rendered forever-empty with no crash, log, or test failure.
   - **Views** read shared app state through SwiftUI Environment. Prefer `@Environment(Singletonia.self)` for anything `Singletonia` already owns — that's most services. Reach for a custom environment key only for the consumers `Singletonia` can't reach: watchOS, tvOS, and packages like `DebugPanel` that can't import an app-target type. A custom key must never default to `nil` — `PlaylistServiceEnvironmentDefault` in `PlaylistServiceEnvironment.swift` is the pattern: a non-optional `defaultValue` that logs at `.error`, traps via `assertionFailure` in DEBUG (loud, immediate signal that an `.environment(...)` call is missing), and falls through to a single disconnected fallback instance once Release strips assertions — never a silent, forever-empty view. Hold the fallback in a `static let`, not a computed `defaultValue`: SwiftUI re-reads `defaultValue` on every environment lookup that misses, so a computed one allocates a fresh service per read. Injecting the key is then mandatory at every entry point, previews included, because a miss now fails loudly rather than degrading.
   - **Services** (the `Playlist`/`Artwork`/`Playback`/... package types) take their dependencies through `init`, not the environment — the environment is a SwiftUI-only mechanism and these types predate, and outlive, any particular view tree.
   - **`.shared` singletons** (`AudioPlayerController.shared`, `StructuredPostHogAnalytics.shared`, etc.) are read only at a composition root — `Singletonia.init`, `WXYCApp`, or the watchOS/tvOS entry point — to construct or wire other things. A mid-graph service or a view reaching for `.shared` directly is the same "second path to the same value" bug as a redundant environment key.
   - **`AppDependencyManager`** is reserved for AppIntents' own `@Dependency` seam (Siri/Spotlight entities and queries), the one place SwiftUI Environment can't reach because intents run in a separate extension process. `AppIntentsDependencies.registerForApp(...)`, called first thing in `Singletonia.init`, is the sole registration site so every process that links `WXYCIntents` — including the widget extension — gets the same bootstrap; see the widget `@Dependency` trap in WXYC/wxyc-ios-64#751.
2. **@Observable**: Used for reactive state management (requires iOS 17+)
3. **Async/Await**: Modern concurrency throughout
4. **MainActor**: UI-bound code isolated to main actor

## Important Files

| File | Description |
|------|-------------|
| `WXYC/iOS/WXYCApp.swift` | Main app entry point |
| `WXYC/iOS/Views/Root/RootTabView.swift` | Root navigation |
| `Shared/Wallpaper/Sources/WallpaperTheme/BackgroundLayer.swift` | Animated background (in the Wallpaper submodule) |
| `Shared/Playback/Sources/PlaybackAPI/AudioPlayerController.swift` | Audio playback (Playback splits into `PlaybackAPI` and `PlaybackCore`) |
| `Shared/Playlist/Sources/Playlist/PlaylistService.swift` | Playlist fetching |
| `Shared/Artwork/Sources/Artwork/MultisourceArtworkService.swift` | Artwork fetching |
