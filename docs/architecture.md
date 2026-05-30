# App Architecture

## Modular Swift Packages

The app uses a highly modular architecture with local Swift packages in `Shared/`. The Wallpaper package is a private git submodule sourced from `WXYC/wallpaper-ios`; run `git submodule update --init --recursive` after cloning.

| Package | Purpose |
|---------|---------|
| **Analytics** | PostHog analytics wrapper |
| **AppServices** | App-level services (NowPlayingInfoCenter, background refresh, AppConfiguration) |
| **Artwork** | Album artwork fetching from multiple sources |
| **Caching** | Disk/memory caching with TTL support |
| **Core** | Core types (RadioStation, Playcut, etc.) |
| **Logger** | Logging infrastructure |
| **Metadata** | Playlist metadata parsing |
| **MusicShareKit** | Share extension support for music sharing |
| **Obfuscate** | ObfuscateMacro (unused, retained as transitive dependency) |
| **OpenNSFW** | NSFW image detection for artwork filtering |
| **PartyHorn** | An easter egg. Users must scroll to the bottom of the playlist view and tap 'what the freq?' to access it.' |
| **Playback** | Houses several playback engines. Eventually this will whittle down to 1 or 2, but is currently in an experimental phase. |
| **PlayerHeaderView** | Now playing header UI component |
| **Playlist** | Playlist service and data models |
| **Wallpaper** | Metal shader-based animated backgrounds (private submodule from `WXYC/wallpaper-ios`) |
| **WXUI** | Shared SwiftUI components |

## App Entry Point

`WXYC/iOS/WXYCApp.swift` contains:
- `Singletonia` - Observable singleton holding shared state (PlaylistService, ArtworkService, WallpaperConfiguration)
- Environment injection pattern for dependency injection
- Background refresh scheduling (15-minute intervals via BGTaskScheduler)
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
| `WXYC/iOS/Views/Root/BackgroundLayer.swift` | Animated background |
| `Shared/Playback/Sources/Playback/AudioPlayerController.swift` | Audio playback |
| `Shared/Playlist/Sources/Playlist/PlaylistService.swift` | Playlist fetching |
| `Shared/Artwork/Sources/Artwork/MultisourceArtworkService.swift` | Artwork fetching |
