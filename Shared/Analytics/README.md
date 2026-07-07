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

Historical note: `PostHogErrorReporter` previously emitted the message under a `description` key. Older builds still in the wild carry that key; queries that must include pre-migration data should coalesce `error` and `description` until those builds age out.
