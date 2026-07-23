# Code Generation

`Shared/WXYCAPIModels` is a vendored SwiftPM package of Swift types generated from `wxyc-shared`'s `api.yaml` (the org's OpenAPI 3.0 contract; see the org-level `CLAUDE.md`'s "API Contract" section). It exists so a schema change on the backend — a renamed field, a changed type, a new required property — fails a Swift build or test instead of silently corrupting a hand-maintained decode struct at runtime.

## What's vendored, and what isn't

The package holds only `Models/` and `Infrastructure/` from the generator's output (252 files as of the #412 Phase 0 stand-up): the `Codable` model structs plus the support types they depend on (`JSONValue`, `CaseIterableDefaultsLast`, `NumericRule`, `CodableHelper`, ISO-8601 date formatting). `APIs/` — the generated endpoint clients — is intentionally dropped; this app already has its own networking layer (`AppServices`, `MusicShareKit`) and has no use for generated request/response plumbing, only the wire types.

`Package.swift` declares the target as a plain library:

```swift
// swift-tools-version:6.2
import PackageDescription
let package = Package(
    name: "WXYCAPIModels",
    platforms: [.iOS("18.4"), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "WXYCAPIModels", targets: ["WXYCAPIModels"])],
    targets: [.target(name: "WXYCAPIModels", path: "Sources/WXYCAPIModels")]
)
```

SwiftPM resolves it as a transitive local-package dependency of any package that lists it, the same way `AnalyticsMacros` resolves through `Analytics` — no `project.pbxproj` edit is needed when a new package starts depending on it.

## Which surfaces actually use it

Standing up the package (Phase 0) doesn't by itself change any runtime behavior. Two things currently consume it, and they take different strategies:

- **Metadata album proxy (runtime).** `PlaycutMetadataService.fetchAlbumAndStreaming` (`Shared/Metadata/Sources/Metadata/PlaycutMetadataService.swift`) decodes the `/proxy/metadata/album` response directly into the generated `WXYCAPIModels.AlbumMetadataResponse`, replacing a hand-maintained private decode struct. This is a flat, non-polymorphic response shape, so a straight swap to the generated type was safe: a field rename/removal upstream now fails the build instead of silently dropping data at decode time.
- **V2 flowsheet track entry (test-only parity guard, not a runtime swap).** The flowsheet's runtime decoder stays hand-written; see below.

No other surface imports `WXYCAPIModels` yet. Adopting it elsewhere is a case-by-case call — see "Adding a new consumer."

## Where the pin comes from: `contract-version.json`

`Shared/WXYCAPIModels/contract-version.json` pins the vendored tree to an exact `wxyc-shared` commit and the `api.yaml` version it shipped:

```json
{
  "wxycSharedTag": "52644722abd3b32c6e7acd3b82323d681a506bf0",
  "wxycSharedSha": "52644722abd3b32c6e7acd3b82323d681a506bf0",
  "apiYamlVersion": "1.21.0"
}
```

`wxycSharedSha` is what the regen/verify scripts actually read; `wxycSharedTag` and `apiYamlVersion` are for humans scanning the diff. The vendored `Sources/WXYCAPIModels` tree should always be the exact output of running codegen against this pinned commit — never hand-edited (see "The generated-file header exception" below for how that's enforced).

## Regenerating: `scripts/regenerate-api-types.sh`

Regeneration — bumping the pin and re-running codegen — is **the update path** whenever `api.yaml` changes upstream. Do not hand-edit a file under `Shared/WXYCAPIModels/Sources/WXYCAPIModels`; the next regen will silently blow the edit away, and `verify-api-types.sh` (below) exists specifically to catch anyone who tries.

The script clones `wxyc-shared` at the commit pinned in `contract-version.json` into a gitignored scratch dir, runs its `generate:swift` codegen target (the swift6 generator added in `wxyc-shared#250`), and rsyncs the generated `Models/` and `Infrastructure/` directories over the vendored package. `APIs/` is excluded on every run, matching the "models-only" package described above.

```bash
# Update the contract: bump contract-version.json's wxycSharedTag / wxycSharedSha /
# apiYamlVersion to the new wxyc-shared commit first, then:
scripts/regenerate-api-types.sh

# Iterating locally without a full re-clone each time:
scripts/regenerate-api-types.sh --keep-work-dir

# Point at a fork or a different remote:
scripts/regenerate-api-types.sh --remote git@github.com:someone/wxyc-shared.git
```

Requires `git`, `npm`/`node`, `java` (the OpenAPI generator runs on the JVM via `openapi-generator-cli`), and `rsync` on `PATH`. After it runs, review the diff under `Shared/WXYCAPIModels/Sources/WXYCAPIModels` like any other generated-code bump, then build (`xcodebuild -scheme WXYC ...`, see `docs/build-test.md`) and run the affected test targets before committing.

## Verifying: `scripts/verify-api-types.sh`

`verify-api-types.sh` is the drift check: it regenerates into a temporary scratch directory (never touching the committed tree) and diffs that output against `Shared/WXYCAPIModels/Sources/WXYCAPIModels` with `git diff --no-index --exit-code`. It fails loudly — with the diff on stdout — on any of:

- a hand-edit to a generated file,
- a `contract-version.json` bump that wasn't followed by a regen, or
- an upstream `api.yaml` change that never made it into this repo.

```bash
scripts/verify-api-types.sh

# Against a fork/different remote (forwarded to regenerate-api-types.sh):
scripts/verify-api-types.sh --remote git@github.com:someone/wxyc-shared.git
```

Exit code 0 means the committed tree matches a fresh regen from the pinned contract. This isn't wired into CI yet — run it manually after touching `contract-version.json` or before trusting that the vendored tree is current.

## Drift guards-of-record

Two mechanisms, not one, protect against upstream contract drift reaching this app silently:

1. **The compiler**, for the flat, non-polymorphic surfaces that decode straight into a generated type (currently just `AlbumMetadataResponse`). A renamed/removed/retyped field is a build error at the call site, not a silent runtime miss.
2. **`FlowsheetContractParityTests`** (`Shared/Playlist/Tests/PlaylistTests/FlowsheetContractParityTests.swift`), for the flowsheet, where the runtime decoder is intentionally *not* the generated type (see below). This is the guard-of-record for that surface.

## Why the V2 flowsheet decoder is hand-written, not generated

`api.yaml` models a flowsheet entry as a polymorphic `oneOf` family. The app instead decodes every variant into one flat, tolerant `FlowsheetEntry` (`Shared/Playlist/Sources/Playlist/V2/FlowsheetEntry.swift`) with degrade-don't-throw resilience that a plain-`Codable` generated struct can't express:

- `FlowsheetResponse`'s tri-state `on_air` decoded by *key presence* (absent → unknown, explicit `null` → automation, an object with `dj_name` → that DJ) — something `Codable` alone can't distinguish.
- `TolerantConcert` swallowing a malformed embedded `upcoming_show` rather than failing the whole decode.
- Forward-compatible `metadataStatus` handling for unknown enum values.
- An `entry_type` → `message` fallback for older response shapes.

Swapping in the generated `WXYCAPIModels.FlowsheetV2TrackEntry` at runtime would make any one malformed embedded field *throw*, failing the entire `FlowsheetResponse` decode and freezing now-playing — the class of bug tracked as #229. So the flowsheet's drift protection is a contract test, not a runtime type swap: `FlowsheetContractParityTests` decodes the same fixture row through both the generated struct and the app's tolerant struct, and asserts that `FlowsheetV2TrackEntry.CodingKeys.allCases` (codegen-derived, since the enum is `CaseIterable`) equals the union of two hand-maintained sets:

- `consumedWireFields` — every wire field the app actually reads (wired into `FlowsheetEntry` and, from there, into `Playcut` via `FlowsheetConverter`).
- `knownUnconsumedWireFields` — fields the generated type declares that the listener app deliberately does not decode yet (as of this writing: `segue`, `rotation_bin` — DJ-tooling/rotation-scheduling signals the listener has no use for; `on_streaming`, `track_position` — plausible future features not yet built).

When `api.yaml` adds, renames, or removes a track-entry field, the regenerated `CodingKeys` set no longer equals `consumed ∪ knownUnconsumed`, and the test fails. A human then decides whether to wire the new field into `FlowsheetEntry`/`FlowsheetConverter` and move it into `consumedWireFields`, or to acknowledge it as intentionally unused in `knownUnconsumedWireFields`. Either way, the tolerant decoder itself is never narrowed to match the generated model — do not "fix" a parity-test failure by making `FlowsheetEntry` stricter.

`WXYCAPIModels` is imported by the `PlaylistTests` target for this purpose only; the shipping `FlowsheetEntry`/`FlowsheetResponse` decoder does not import it.

## Adding a new consumer

When a new surface wants to decode a backend response:

- If the response is a flat, non-polymorphic shape (like `AlbumMetadataResponse`), prefer decoding straight into the generated `WXYCAPIModels` type — that's what makes the compiler a drift guard for it.
- If the response is polymorphic, has fields that need degrade-don't-throw tolerance, or otherwise needs bespoke decode logic, follow the flowsheet's pattern: keep a hand-written decoder, and add a parity test (or extend `FlowsheetContractParityTests`'s pattern in a new suite) that decodes a golden fixture through both the generated type and the hand-written one, asserting the field sets stay reconciled.

## The generated-file header exception

Every file under `Shared/WXYCAPIModels/Sources/WXYCAPIModels` carries the OpenAPI generator's own header instead of the project's standard header described in `docs/file-headers.md`:

```swift
//
// AlbumMetadataResponse.swift
//
// Generated by openapi-generator
// https://openapi-generator.tech
//
```

This is a **documented, intentional exception**, not an oversight: these files are regenerated wholesale by `scripts/regenerate-api-types.sh`, so a project-standard "Created by" / description header would be discarded (or worse, drift out of sync) on every regen, and there is no per-file author or description to write — the file is a mechanical projection of `api.yaml`. The `scripts/hooks/header-check.sh` pre-commit hook checks for a `Created by` line and, when it's missing, prints a warning and skips the file rather than failing the commit — so vendored files under `WXYCAPIModels` pass through cleanly without special-casing the hook itself.

Do not add a standard WXYC header to a generated file by hand; the next `regenerate-api-types.sh` run will overwrite it anyway, and `verify-api-types.sh` will flag the file as drifted in the meantime.
