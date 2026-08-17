# Configuration, Signing & Extensions

## Configuration

App configuration (PostHog API key, API base URL, request-o-matic URL, donation destination) is managed by `AppConfiguration` in the AppServices package. Values are hardcoded as defaults and fetched from the backend `/config` endpoint at launch. The `AppConfig` type itself is the generated `WXYCAPIModels.AppConfig`, re-exported by AppServices via a scoped `@_exported import` (#915) — its field set and doc comments come from `api.yaml`, and contract drift is a build error rather than silent skew. Confidential API credentials (Discogs, Spotify) are no longer embedded in the app; those calls are proxied through Backend-Service behind anonymous device session auth.

### The launch fetch

`Singletonia.fetchConfiguration()` calls `AppConfiguration.config()` **before** its secrets retry loop and stores the result in `Singletonia.appConfig`, an `@Observable` property views read. Order matters: the loop is 4-attempt exponential backoff for the *authenticated* `/config/secrets` endpoint and returns outright when secrets never arrive, so a `/config` call appended after it would be skipped in exactly the cold-launch/no-auth case that matters most. `/config` is unauthenticated and must not be gated on auth.

The fetch happens once per launch. That is the right cadence for an endpoint served `Cache-Control: public, max-age=3600` — which also means every remote value here is a **deploy-time** switch with up to an hour of propagation delay, not an instant one.

`AppConfiguration.cached` is per-*instance*, and `fetchConfiguration()` builds a local `AppConfiguration()`, so the fetched value must be stored on `Singletonia` rather than read back off the actor.

### Donation fields

| Field | Backend-Service env var (EC2) | Absent value |
|---|---|---|
| `donateUrl` | `DONATE_URL` | `""` (not `null`) |
| `donateEnabled` | `DONATE_ENABLED` | `false` |

Both are **optional** in Swift. Non-optional properties would make `JSONDecoder.decode` throw against any backend that doesn't serve them yet, and `config()` catches a decode error by returning `defaults` wholesale — silently discarding the remote PostHog key and `apiBaseUrl` too. A backend rollback, a stale cached response, or shipping iOS ahead of Backend-Service all trigger that path, so `AppConfigurationTests` pins the missing-field decode.

`DonateRowModel` (`WXYC/iOS/Views/Station/DonateRowModel.swift`) resolves both into what the Station tab's Donate row renders:

- **Visibility** is `donateEnabled ?? false`. `nil` means "the backend doesn't serve the field" — the live state until Backend-Service PR#2115 deploys — and the row is a solicitation, so absence resolves dark; it renders only when the backend says `true` explicitly. `AppConfiguration.defaults` pins `donateEnabled: false` too, so every failure path agrees with the default rather than depending on it. Lighting up is three steps, in order: merge + deploy Backend-Service PR#2115 (it emits both donate fields and registers `DONATE_ENABLED` in `set-ec2-env-var.yml`'s allowlist — until then the runbook variable doesn't exist), set `DONATE_ENABLED` to lowercase `true` — the reader compares strictly — via that workflow (the light-up platform is EC2, not Railway), then flip the `defaults` literal in the next regular release so offline launches show the row too.
- **Destination** is the fetched `donateUrl` when it yields an http(s) URL, else the compile-time `RadioStation.WXYC.donateURL` (`https://wxyc.org/donate`); `defaults` carries no `donateUrl`, so there is no middle rung. `""`, a scheme-relative string, and `mailto:`/`javascript:` all count as absent, because `SFSafariViewController` traps on anything that isn't http(s).

The row opens its destination in an `SFSafariViewController` sheet, not `openURL`. Donations must be collected outside the app (App Store Review Guideline 3.2.1(vi) reserves in-app fundraising for approved nonprofits, which requires a Candid Seal that SEB does not have), so this is a web checkout regardless; the sheet keeps the listener in the app with a Done button and uninterrupted audio, and Apple Pay on the Web works in `SFSafariViewController` — the restriction is on `WKWebView`.

## Sentry Debug Symbols (dSYM upload)

Sentry symbolicates Release stacks **server-side**, from dSYMs uploaded at build time by the `Upload Debug Symbols to Sentry` build phase on the WXYC target. The phase is a one-line `exec` of `scripts/upload-debug-symbols.sh`; the logic lives in the script so it can be regression-tested (`scripts/tests/test-upload-debug-symbols.sh`) instead of edited blind inside `project.pbxproj`.

Without that upload, Sentry has addresses and no function names, and everything downstream of a symbolicated stack — grouping rules, fingerprints, the innermost-in-app-frame heuristics — silently stops working. Nothing in the build says so, which is why the script's failure behavior depends on where it runs:

| | sentry-cli missing | no credentials | upload rejected |
|---|---|---|---|
| **Local** (`CI` unset) | `warning:`, build continues | `warning:`, build continues | `warning:`, build continues |
| **CI**, shipping build | `error:`, build fails | `error:`, build fails | `error:`, build fails |
| **CI**, non-shipping build | n/a — never attempted | n/a — never attempted | n/a — never attempted |

A dev Mac must not be blocked by a tool nobody installed. A CI archive is the opposite case: it ships. Two exemptions sit on top of that:

- **A build with no dSYMs** skips everywhere.
- **A CI build that can't ship** skips too. "Shipping" is `ACTION=install` (an archive) or any non-`Debug` `CONFIGURATION`; a build with neither setting present counts as shipping, since a spurious CI failure is loud and a skipped upload is not.

The second exemption is load-bearing and easy to get wrong: **the presence of dSYMs is not the discriminator.** WXYC builds Debug with `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`, so a plain simulator build populates `DWARF_DSYM_FOLDER_PATH` exactly like an archive does. A strict-whenever-dSYMs-exist rule would demand a Sentry token from every Xcode Cloud test workflow and fail the ones that don't have one. Locally, Debug builds still upload as they always have — Sentry does symbolicate simulator events from dev machines.

`CI` is read as a tri-state, not a presence check: `false`, `0`, `no`, `off`, and empty all mean local. Xcode Cloud sets `CI=TRUE`.

### Local setup

Install `sentry-cli` (`brew install getsentry/tools/sentry-cli`, or `ci_scripts/install-sentry-cli.sh` for the pinned version) and put an auth token in a `.sentryclirc` at the repo root:

```ini
[auth]
token=<your token>
```

`.sentryclirc` is gitignored and must stay that way. The script also accepts `SENTRY_AUTH_TOKEN` in the environment, or a `~/.sentryclirc`.

### Xcode Cloud setup

Xcode Cloud runners ship no `sentry-cli` and, because `.sentryclirc` is gitignored, no credentials either. `ci_scripts/ci_post_clone.sh` supplies both by calling `ci_scripts/install-sentry-cli.sh`, which:

- installs a **pinned** `sentry-cli` (the version is a constant at the top of that script — bump it deliberately, never float latest) into `.ci-tools/bin/` inside the checkout. Checkout-local rather than system-wide: the upstream installer falls back to `sudo -k` when its target isn't writable, which on a non-interactive runner hangs or fails without a prompt.
- writes `SENTRY_AUTH_TOKEN` to `~/.sentryclirc` at mode 600, never overwriting an existing file. Xcode Cloud environment variables are documented as reaching custom build scripts; whether one reaches a run-script phase nested inside `xcodebuild` is a thinner guarantee, and a config file on disk is one `sentry-cli` reads regardless of how it was invoked.

The one thing that is **not** in this repo is the token itself. It has to be added by hand, once, in App Store Connect:

1. Mint an **organization auth token** (the `sntrys_…` kind) at https://sentry.io/settings/wxyc/auth-tokens/. Its scope is fixed at `org:ci` / `project:releases` — enough to upload debug files, not enough to administer the project, which is exactly what an upload credential should be. Don't substitute a personal user token: those carry the minting user's full access and die with their account.
2. In App Store Connect → Xcode Cloud → the workflow → **Environment**, add `SENTRY_AUTH_TOKEN` with **Secret** checked so it is redacted from build logs.
3. Add it to every workflow whose `xcodebuild` action is `archive`. Build- and test-only workflows don't need it.

An archive workflow missing the token fails in `ci_post_clone` (that script passes `--require-auth` when `CI_XCODEBUILD_ACTION` is `archive`, so the failure lands at minute zero rather than twenty minutes into the build). If it somehow gets past that, the build phase fails the archive anyway. Both are deliberate: the previous behavior was a `warning:` in a green build, and an archive shipping without symbols is not something anyone notices until they need a crash report weeks later.

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
