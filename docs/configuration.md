# Configuration, Signing & Extensions

## Configuration

App configuration (PostHog API key, API base URL, request-o-matic URL) is managed by `AppConfiguration` in the AppServices package. Values are hardcoded as defaults and optionally fetched from the backend `/config` endpoint at launch. Confidential API credentials (Discogs, Spotify) are no longer embedded in the app; those calls are proxied through Backend-Service behind anonymous device session auth.

## Code Signing

- Development Team: `92V374HC38`
- Code Sign Style: Automatic
- All targets (including extensions) must have `DevelopmentTeam` in their TargetAttributes

### Extension Targets

- **Request Share Extension**: Share sheet integration for sharing songs
- **NowPlayingWidget**: Home screen widget showing current track
- **CarPlay**: CarPlay scene delegate in main app

## App Delegate

`WXYC/iOS/AppDelegate.swift`, wired into `WXYCApp` via `@UIApplicationDelegateAdaptor`, exists for exactly one reason: `application(_:handlerFor:)` returns `PlayMediaIntentHandler` (`Shared/Intents/Sources/Intents/PlayMediaIntentHandler.swift`) for a directly-dispatched `INPlayMediaIntent` — the background-capable entry point a media-suggestion tile (the one iOS offers after headphones connect) needs, since the app's only other SiriKit intake, the `NSUserActivity` continuation in `AppLifecycleModifier.swift`, requires a foreground launch. See #829.

**`AppDelegate` must never implement `application(_:configurationForConnecting:options:)`.** That method takes precedence over the `UIApplicationSceneManifest` declared in `WXYC/iOS/Assets/Info.plist` (`:86-111`), which is what wires `WXYC.CarPlaySceneDelegate` for the CarPlay scene role. An app delegate that implements it — even to fall through to a default — silently breaks CarPlay scene creation, and nothing in the automated test suite would catch that failure mode on its own; `AppDelegateTests` guards it mechanically by asserting `responds(to:)` is `false` for that selector, but the constraint itself has to be honored by never adding the method in the first place.

`com.apple.developer.siri` is already granted in `WXYC/Entitlements/WXYC.entitlements`, so no capability work was needed to add the handler. `INIntentsSupported` (`[INPlayMediaIntent]`) is declared only in `WXYC/iOS/Assets/Info.plist` — the Share Extension and NowPlayingWidget have their own separate `INFOPLIST_FILE`s, and `WXYC/WXYC TV/WXYC-TV-Info.plist` / `WXYC/WatchXYC/WatchXYC-Info.plist` don't need it, so there's no inheritance to guard against.

## Widget Considerations

- Widget refresh budget: 40-70 updates/day
- Foreground refreshes don't count against budget
- Background refresh scheduled every 15 minutes

## App Store Previews

App Store screenshots and preview assets live in a separate project at `../app-store-previews`. Use that project when preparing assets for App Store publication.

## Minimum iOS Version

iOS 18.6 (based on SDK version in built app)
