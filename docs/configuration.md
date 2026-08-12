# Configuration, Signing & Extensions

## Configuration

App configuration (PostHog API key, API base URL, request-o-matic URL, donation destination) is managed by `AppConfiguration` in the AppServices package. Values are hardcoded as defaults and fetched from the backend `/config` endpoint at launch. Confidential API credentials (Discogs, Spotify) are no longer embedded in the app; those calls are proxied through Backend-Service behind anonymous device session auth.

### The launch fetch

`Singletonia.fetchConfiguration()` calls `AppConfiguration.config()` **before** its secrets retry loop and stores the result in `Singletonia.appConfig`, an `@Observable` property views read. Order matters: the loop is 4-attempt exponential backoff for the *authenticated* `/config/secrets` endpoint and returns outright when secrets never arrive, so a `/config` call appended after it would be skipped in exactly the cold-launch/no-auth case that matters most. `/config` is unauthenticated and must not be gated on auth.

The fetch happens once per launch. That is the right cadence for an endpoint served `Cache-Control: public, max-age=3600` — which also means every remote value here is a **deploy-time** switch with up to an hour of propagation delay, not an instant one.

`AppConfiguration.cached` is per-*instance*, and `fetchConfiguration()` builds a local `AppConfiguration()`, so the fetched value must be stored on `Singletonia` rather than read back off the actor.

### Donation fields

| Field | Env var on Railway | Absent value |
|---|---|---|
| `donateUrl` | `DONATE_URL` | `""` (not `null`) |
| `donateEnabled` | `DONATE_ENABLED` | `false` |

Both are **optional** in Swift. Non-optional properties would make `JSONDecoder.decode` throw against any backend that doesn't serve them yet, and `config()` catches a decode error by returning `defaults` wholesale — silently discarding the remote PostHog key and `apiBaseUrl` too. A backend rollback, a stale cached response, or shipping iOS ahead of Backend-Service all trigger that path, so `AppConfigurationTests` pins the missing-field decode.

`DonateRowModel` (`WXYC/iOS/Views/Station/DonateRowModel.swift`) resolves both into what the Station tab's Donate row renders:

- **Visibility** is `donateEnabled ?? true`. `nil` means "the backend predates the field", and the compile-time fallback is a valid destination. The dark-ship case is carried by `AppConfiguration.defaults` pinning `donateEnabled: false` **explicitly** — `defaults` is what `config()` returns on every failure path, so a `nil` there would show the row in exactly the release meant to hide it. Lighting up is two steps: set `DONATE_ENABLED=true` on Railway (no app release), then flip the `defaults` literal in the next regular release so offline launches show the row too.
- **Destination** walks a ladder — fetched `donateUrl` → `defaults.donateUrl` → `RadioStation.WXYC.donateURL` (`https://wxyc.org/donate`). A rung only wins if it yields an http(s) URL; `""`, a scheme-relative string, and `mailto:`/`javascript:` all count as absent, because `SFSafariViewController` traps on anything that isn't http(s).

The row opens its destination in an `SFSafariViewController` sheet, not `openURL`. Donations must be collected outside the app (App Store Review Guideline 3.2.1(vi) reserves in-app fundraising for approved nonprofits, which requires a Candid Seal that SEB does not have), so this is a web checkout regardless; the sheet keeps the listener in the app with a Done button and uninterrupted audio, and Apple Pay on the Web works in `SFSafariViewController` — the restriction is on `WKWebView`.

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

**`AppDelegate` must never implement `application(_:configurationForConnecting:options:)`.** That method takes precedence over the `UIApplicationSceneManifest` declared in `WXYC/iOS/Assets/Info.plist` (`:90-115`), which is what wires `WXYC.CarPlaySceneDelegate` (`:104`) for the CarPlay scene role. An app delegate that implements it — even to fall through to a default — silently breaks CarPlay scene creation, and nothing in the automated test suite would catch that failure mode on its own; `AppDelegateTests` guards it mechanically by asserting `responds(to:)` is `false` for that selector, but the constraint itself has to be honored by never adding the method in the first place.

`com.apple.developer.siri` is already granted in `WXYC/Entitlements/WXYC.entitlements`, so no capability work was needed to add the handler. `INIntentsSupported` (`[INPlayMediaIntent]`) is declared only in `WXYC/iOS/Assets/Info.plist` — the Share Extension and NowPlayingWidget have their own separate `INFOPLIST_FILE`s, and `WXYC/WXYC TV/WXYC-TV-Info.plist` / `WXYC/WatchXYC/WatchXYC-Info.plist` don't need it, so there's no inheritance to guard against.

## Widget Considerations

- Widget refresh budget: 40-70 updates/day
- Foreground refreshes don't count against budget
- Background refresh scheduled every 15 minutes

## App Store Previews

App Store screenshots and preview assets live in a separate project at `../app-store-previews`. Use that project when preparing assets for App Store publication.

## Minimum iOS Version

iOS 18.6 (based on SDK version in built app)
