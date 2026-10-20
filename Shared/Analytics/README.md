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

## MetricKit diagnostics

On iOS, `MetricKitSubscriber` (started from `AppBootstrap.setUpAnalytics`) forwards each `MXHangDiagnostic` and `MXCrashDiagnostic` as a PostHog `$exception` event (`ExceptionEvent`) with `source = metrickit` and `diagnostic_kind` of `hang` or `crash`. A crash has `$exception_level` `fatal`; a hang has `error`, because the app may have recovered. `MetricKitDiagnosticMapper` builds the event from the diagnostic's JSON. The stack is the attributed thread's: for a crash that is the thread's full backtrace, and for a hang (a tree of samples) it is the most-sampled path. Other threads are not sent. Frames are oldest first, with the crash or hang site last. A hang stack already runs that way; a MetricKit crash stack runs the other way (its root frame is the crash site and its sub-frames walk out to dyld's `start`), so the mapper reverses a crash stack. Frames carry `platform: "apple"` (without it PostHog reads a frame that has `module` as Python and rejects the event), `instruction_addr`, `image_addr` (the address minus MetricKit's `offsetIntoBinaryTextSegment`, aligned down to the 4 KiB page, because a caller frame's return address otherwise lands one byte past the image base), `image_uuid` (MetricKit's `binaryUUID`), `module`, `package` and `in_app`. These follow posthog-ios's own crash processor, with two differences: posthog-ios sends no `image_uuid` on frames, and it sends `image_size` on debug images, which MetricKit cannot supply. The event also sends `$debug_images`, one `macho` entry per binary with the same page-aligned `image_addr` as its frames, so PostHog can match frames to uploaded dSYMs. The exception `value` holds only the failure kind or termination reason; the hang duration, the diagnostic's app version and build, and the payload's time range are separate properties (`hang_duration`, `diagnostic_app_version`, `diagnostic_app_build`, `diagnostic_period_start`, `diagnostic_period_end`). `JSONSerialization` rejects JSON nested more than 512 levels, so a stack deeper than about 254 frames is dropped at parse time and not sent. The mapper's 256-frame cap (which keeps the frames nearest the crash or hang site) is only a backstop that real payloads cannot reach. Frames are not symbolicated on device; symbolication is checked in ops step O5. Sentry's `enableMetricKit` stays off.

## Exception rate limit

`StructuredPostHogAnalytics.captureException` (the handled-error path, which `captureReportedError` also reaches) passes every error through an `ExceptionGate` before it calls PostHog, because PostHog's free plan stops accepting `$exception` events at 100K a month, org-wide, and the listener app has the largest install base of any WXYC surface. One device in a retry loop could otherwise exhaust the cap for every surface, servers included. The gate is the client form of the server contract in [wiki `patterns/error-tracking.md` §5](https://github.com/WXYC/wiki/blob/main/patterns/error-tracking.md#5-error-budget). Two gates run in order:

1. **Dedupe, 60 seconds.** An error whose key was admitted less than 60 seconds ago is dropped and costs no token. The key is the error's type plus its `$exception_fingerprint` property when it has one, otherwise its message (domain and code for an `NSError`) plus the `context` property. The table holds at most 1,000 keys; when full it drops expired keys, then the oldest.
2. **Token bucket, per launch.** Burst 20, refilling one token every 30 minutes (1,800 seconds), a steady-state ceiling of 48 a day. Twenty covers the distinct failures of a bad launch; 30 minutes holds a stuck device to 48 a day so the fleet's share of the cap stays small. The bucket lives in memory and starts full at every launch.

Dropped events are counted and logged as a warning at most once a minute. They are never sent. The gate reads an injected monotonic clock, so tests drive it by hand.

**Crashes bypass the gate on purpose.** MetricKit forwarding sends each crash and hang as an `ExceptionEvent` through `capture(_:)`, not `captureException`, and the OS delivers those in at most one payload a day. PostHog's own crash autocapture never touches `StructuredPostHogAnalytics`. A crash is the signal the cap exists to protect, so neither is limited. The plain `error` event (`ErrorEvent`) is product analytics, counted against the event allowance, and is not gated either.

## Exception privacy scrub

`AnalyticsBootstrap.start` installs a before-send hook on every platform that runs `ExceptionListScrub` over each event's properties. It removes the query and fragment from every URL inside every string leaf of `$exception_list` (`captureException`, MetricKit and crash autocapture all land there), because a URLSession error can carry the failing request URL in its description, `NSDebugDescriptionErrorKey` or `NSUnderlyingErrorKey` chain. Other properties are not rewritten. The URL rule is copied from the DJ app's `URLScrubbing` and `TelemetryPrivacyScrub` (wxyc-dj-ios), so both apps treat the field the same way.

## Platform labels

The PostHog SDK labels iOS, iPadOS, macOS and tvOS events with `$os`, `$os_name`, `$os_version` and `$device_type` on its own. It has no watchOS branch for any of the four, so `AnalyticsBootstrap.start` stamps them on every watch event through the same before-send hook (`$os_name = watchOS`, `$device_type = Wearable`). The hook is installed on the config before `setup` runs, which is what lets it reach the lifecycle events `setup` captures itself.

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
