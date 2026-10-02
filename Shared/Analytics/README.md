# Analytics

Structured analytics for the WXYC apps. Events are value types conforming to `AnalyticsEvent`; the concrete sink is `StructuredPostHogAnalytics` (forwards to PostHog and stamps `build_type`). Tests use `MockStructuredAnalytics` from the `AnalyticsTesting` product.

## Error-event schema (canonical)

Every reporter path emits the **same** PostHog event so a single insight or alert filter matches every build. The event name is always `error`, and the message lives under the `error` property key.

| Property | Type | Source | Always present |
|----------|------|--------|----------------|
| `error` | String | `error.localizedDescription` | yes |
| `context` | String | caller-supplied "where/why" string | yes |
| `code` | Int | `(error as NSError).code` | when non-nil |
| `domain` | String | `(error as NSError).domain` | when non-nil |
| `category` | String | `Logger.Category.rawValue` | when non-nil |
| `build_type` | String | `WXYC_BUILD_TYPE` Info.plist key | yes (stamped by `StructuredPostHogAnalytics`) |
| *caller extras* | String | `additionalData` | when provided |

Structural keys (`error`/`context`/`code`/`domain`/`category`) win over any colliding `additionalData` key — see `ErrorEvent.properties`.

The schema is defined once in [`ErrorEvent`](Sources/Analytics/Events/ErrorEvents.swift). Do not hand-roll the property dictionary — construct an `ErrorEvent` and `capture` it, or call `AnalyticsService.captureError(_:context:...)`.

### Reporter paths

Both concrete `ErrorReporter`s route through `ErrorEvent`, so their property keys are identical:

- **iOS** — `CompositeErrorReporter` (local log + PostHog `ErrorEvent` + Sentry). Wired in `WXYCApp.init()`.
- **watchOS** — `PostHogErrorReporter` (local log + PostHog `ErrorEvent`; no Sentry on watch). Wired in `WatchXYC.init()`.
- **tvOS** — `PostHogErrorReporter`, for the same reason. Wired in `WXYCTVApp.init()`.

`ErrorReporting.shared` defaults to a no-op, so an entry point that does not install a reporter discards every error the shared packages report. A new platform target has to wire one.

Historical note: `PostHogErrorReporter` previously emitted the message under a `description` key. Older builds still in the wild carry that key; queries that must include pre-migration data should coalesce `error` and `description` until those builds age out.

## Platform labels

The PostHog SDK labels iOS, iPadOS, macOS and tvOS events with `$os`, `$os_name`, `$os_version` and `$device_type` on its own. It has no watchOS branch for any of the four, so `AnalyticsBootstrap.start` stamps them on every watch event through a before-send hook (`$os_name = watchOS`, `$device_type = Wearable`). The hook is installed on the config before `setup` runs, which is what lets it reach the lifecycle events `setup` captures itself.

| Platform | `$os_name` | `$device_type` | Labeled by |
|----------|------------|----------------|------------|
| iPhone | `iOS` | `Mobile` | SDK |
| iPad | `iPadOS` | `Tablet` | SDK |
| Mac | `macOS` | `Desktop` | SDK |
| Apple TV | `tvOS` | `TV` | SDK |
| Apple Watch | `watchOS` | `Wearable` | `AnalyticsBootstrap` |

The Apple TV row is read from the SDK source, not from observed events: as of 2026-10-01 no tvOS build that reports has shipped.

Watch events from 3.1 and earlier carry none of these, and 3.2.x watch builds carry the OS keys but no `$device_type`. To count the watch across every build, filter on `$app_namespace = org.wxyc.iphoneapp.watchkitapp` instead.

A watch `app_launch` is not evidence that anyone opened the watch app. Over the 120 days to 2026-10-01, 255 of 1,161 watch launches followed a phone `play` from the same IP address by under two minutes, against 3 or 4 when the same match is run at a shifted time. That is the signature of watchOS opening an audio app's watch companion by itself when the phone starts playing. Count watch `play` events to measure watch listening.
