# App Architecture

## Modular Swift Packages

The app uses a highly modular architecture with local Swift packages in `Shared/`. The Wallpaper package is a private git submodule sourced from `WXYC/wallpaper-ios`; run `git submodule update --init --recursive` after cloning.

| Package | Purpose |
|---------|---------|
| **Analytics** | PostHog analytics wrapper |
| **AnalyticsMacros** | `@AnalyticsEvent` macro (swift-syntax compiler plugin) that derives snake_case event names and `properties` from a type declaration |
| **AppServices** | App-level services: `AppConfiguration` (backend `/config` bootstrap), Spotlight indexing/donation for concerts and playcuts, App Store review prompts, On Tour alert scheduling, widget state/relevance, `NowPlayingService` |
| **Artwork** | Album artwork fetching from multiple sources |
| **Caching** | Disk/memory caching with TTL support |
| **ColorPalette** | Dominant-color extraction and palette generation from artwork images; also the home for both of the codebase's hue-based color models — `HSBColor` (degree-based hue, bridges to UIKit/AppKit, backs the wallpaper theming system) and `HSL` (CSS `hsl()` semantics, for design-system colors transcribed from a spec) |
| **Concerts** | On Tour concert models, the dismissed-concerts store, and the Box Office ticket presenter |
| **Core** | Core types (RadioStation, Playcut, etc.); the `FileStorage`/`AppSupportFileStorage` durable never-evict byte-file seam (`CoreTesting` for the `InMemoryFileStorage` double), shared by LikedSongs and Concerts |
| **DebugPanel** | DEBUG-only settings/HUD panel: performance metrics overlay, feature toggles, cache purge |
| **Intents** | App Intents (`WXYCIntents` product): Siri/Spotlight entities and queries (PlayWXYC, artist/release/venue lookups) |
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
| **WXYCAPIModels** | Vendored, generated (openapi-generator) Swift models from `wxyc-shared`'s `api.yaml`. Models + Infrastructure only, no endpoint clients. Regenerate via `scripts/regenerate-api-types.sh`; not yet adopted by app code (#412 Phase 0). |

## App Entry Point

`WXYC/iOS/WXYCApp.swift` contains:
- `Singletonia` - Observable singleton holding shared state (PlaylistService, ArtworkService, WallpaperConfiguration, SpotlightDonationService, PlaycutHistoryStore — the Playlist package's persistent ~90-day playcut history + rotation set, built to enable the future Spotlight reindex handler)
- Environment injection pattern for dependency injection
- Background refresh scheduling (15-minute intervals via BGTaskScheduler); each refresh ingests the fetched playcuts into `PlaycutHistoryStore` directly before the Spotlight donation batch
- Widget refresh budget management

## Key Patterns

1. **Dependency Injection**: Services are injected via SwiftUI Environment
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
