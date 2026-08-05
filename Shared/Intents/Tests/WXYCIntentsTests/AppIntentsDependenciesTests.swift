//
//  AppIntentsDependenciesTests.swift
//  WXYCIntents
//
//  Verifies the #751 registration bootstrap.
//
//  `AppIntentsDependenciesManifestTests` is the completeness net. It scans
//  every `.swift` file under `Sources/Intents` (located relative to this
//  file via `#filePath`) for `@Dependency` declarations and asserts the
//  discovered set of types matches `AppIntentsDependencySlot.allCases`
//  exactly. Chosen over reflecting into a fixed list of query instances
//  (this file's original approach, which an #751 review flagged as finding
//  B2): reflection can only ever see the specific `PlaycutEntityQuery()`/
//  `ConcertEntityQuery()` instances someone remembers to construct, and the
//  package ships roughly a dozen other query/intent types
//  (ArtistEntityQuery, VenueEntityQuery, ReleaseEntityQuery, ShowEntityQuery,
//  DJEntityQuery, LabelEntityQuery, ToursNearMeQuery,
//  AddConcertToCalendarQuery, ...). The ticket's stated motivation --
//  "so the next entity kind can't reintroduce the trap" -- names exactly the
//  shape a fixed instance list can't see: a *new* query type. Swift has no
//  runtime enumeration of struct conformers, so a text scan of the actual
//  source is the only way to see every `@Dependency` declaration without
//  maintaining a second hand-written list that could itself go stale (the
//  same class of risk finding B1 flagged for the manifest/registration
//  split -- see `AppIntentsDependencies.swift`).
//
//  `WidgetSafeConcertsFetchingTests` covers the one widget-default conformer
//  with real branching logic -- both methods throw (#751 review, finding
//  B3; see `WidgetSafeConcertsFetching.swift`'s header for why a
//  successful-empty `fetchConcerts` is unsafe). `WidgetSafeNoOpConformerTests`
//  covers the other three, which are pure no-ops with nothing to assert
//  beyond "conforms and compiles."
//
//  The `ReindexHandlerTests` extension at the bottom exercises
//  `registerForApp`/`registerForWidget` themselves -- the ticket's central
//  production code, otherwise uncalled by any test (#751 review, finding
//  B4). It deliberately stops at registration: an earlier version of this
//  suite also constructed a bare `PlaycutEntityQuery()` afterward and read
//  `entities(for:)`, on the theory that `AppDependency.wrappedValue` is
//  populated by an injection pass the AppIntents runtime performs on
//  instances it constructs, so the trap seen under a bare `swift test
//  --package-path Shared/Intents` run (no `ExtractAppIntentsMetadata`
//  processing) would be an artifact of that specific host, not a real
//  limit. That theory does not hold: the same test, run via `xcodebuild
//  test -scheme WXYC -only-testing:WXYCIntentsTests` against a real iOS
//  Simulator -- which *does* run `ExtractAppIntentsMetadata`/
//  `appintentsmetadataprocessor` over the built test bundle -- still
//  reported "Test crashed with signal trap" for that exact test node
//  (confirmed via `xcresulttool`). `AppDependencyManager.shared.add(...)`
//  having been called immediately beforehand does not change the outcome
//  in either host. Registration alone (what the tests below cover) never
//  crashed in any configuration tried; only a subsequent manually-triggered
//  `@Dependency` read did. `PlaycutEntityQueryReindexTests.swift` (elsewhere
//  in this target) uses the identical register-then-construct-then-read
//  shape but is gated behind `#if compiler(>=6.4)` (the Xcode 27 beta
//  toolchain), so it has never actually executed in this environment --
//  whether it passes there is an open question this finding raises, not
//  one this ticket resolves. AC4's "widget process can resolve queries
//  without trapping" therefore remains a documented manual check (see
//  `NowPlayingWidgetBundle.init()`), not an automated one.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts
import ConcertsTesting
import Foundation
import Playlist
import PlaylistTesting
import Testing
@testable import WXYCIntents

@Suite("AppIntentsDependencies manifest")
struct AppIntentsDependenciesManifestTests {
    @Test("every @Dependency declaration under Sources/Intents is covered by AppIntentsDependencySlot")
    func everyDeclaredDependencyIsCoveredByTheManifest() throws {
        let declared = try Self.declaredDependencyTypeNames()
        #expect(!declared.isEmpty, "source scan found zero @Dependency declarations -- the #filePath-relative walk to Sources/Intents likely broke")

        let manifest = Set(AppIntentsDependencySlot.allCases.map(Self.sourceTypeName(for:)))
        #expect(
            declared == manifest,
            "declared @Dependency types \(declared.sorted()) don't match AppIntentsDependencySlot's \(manifest.sorted()) -- a new entity kind's @Dependency can silently go unregistered in the widget process (#751)."
        )
    }

    /// Scans every `.swift` file in `Sources/Intents` for the `@Dependency`
    /// attribute immediately followed by `var name: Type`, and returns the
    /// set of distinct (`any `-stripped) type names found. A declaration
    /// whose attribute and `var` line aren't adjacent (none currently are --
    /// see `PlaycutEntityQuery.swift`/`ConcertEntityQuery.swift`) would slip
    /// past this regex; that's an accepted, narrow gap enforced by this same
    /// test staying meaningful only as long as the existing declaration
    /// style holds.
    private static func declaredDependencyTypeNames() throws -> Set<String> {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // this file -> WXYCIntentsTests/
            .deletingLastPathComponent() // -> Tests/
            .deletingLastPathComponent() // -> Intents/ (package root)
            .appendingPathComponent("Sources/Intents", isDirectory: true)

        let files = try FileManager.default.contentsOfDirectory(at: sourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        let pattern = /@Dependency\s*\n\s*(?:public |private |internal )?var\s+\w+\s*:\s*([^\n]+)/

        var found: Set<String> = []
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for match in contents.matches(of: pattern) {
                let rawType = match.output.1.trimmingCharacters(in: .whitespaces)
                found.insert(Self.stripAny(rawType))
            }
        }
        return found
    }

    /// `AppIntentsDependencySlot.dependencyType` normalized to the same
    /// source-text form the scan above produces: strip the
    /// `AppDependency<...>` wrapper, then strip a leading `any `.
    private static func sourceTypeName(for slot: AppIntentsDependencySlot) -> String {
        let described = String(describing: slot.dependencyType) // e.g. "AppDependency<PlaycutHistoryStore>"
        let prefix = "AppDependency<"
        guard described.hasPrefix(prefix), described.hasSuffix(">") else { return described }
        return Self.stripAny(String(described.dropFirst(prefix.count).dropLast()))
    }

    private static func stripAny(_ typeName: String) -> String {
        typeName.hasPrefix("any ") ? String(typeName.dropFirst(4)) : typeName
    }
}

@Suite("WidgetSafeConcertsFetching")
struct WidgetSafeConcertsFetchingTests {
    @Test("fetchConcerts throws rather than reporting a false-successful empty page")
    func fetchConcertsThrows() async {
        let fetcher = WidgetSafeConcertsFetching()

        await #expect(throws: (any Error).self) {
            try await fetcher.fetchConcerts(curated: true, from: nil, to: nil, page: 1, limit: 50)
        }
    }

    @Test("fetchConcert(id:) throws rather than making a network request")
    func fetchConcertThrows() async {
        let fetcher = WidgetSafeConcertsFetching()

        await #expect(throws: (any Error).self) {
            try await fetcher.fetchConcert(id: 1)
        }
    }
}

@Suite("Widget-safe no-op conformers")
struct WidgetSafeNoOpConformerTests {
    @Test("WidgetSafePlaycutReindexer discards a donation without throwing")
    func playcutReindexerDiscardsDonation() async throws {
        let playcut = Playcut.stub(id: 1, artistName: "Juana Molina")
        try await WidgetSafePlaycutReindexer().donate([PlaycutEntity(playcut: playcut)])
    }

    @Test("WidgetSafeConcertReindexer discards a donation without throwing")
    func concertReindexerDiscardsDonation() async throws {
        try await WidgetSafeConcertReindexer().donate([.stub()])
    }

    @Test("WidgetSafeAnalyticsService logs a captured event without throwing")
    func analyticsServiceLogsCapturedEvent() {
        WidgetSafeAnalyticsService().capture(SpotlightReindexRequested(kind: "single", rowCount: 1))
    }
}

// MARK: - Bootstrap registration (shared AppDependencyManager serialization)

// Nested under `ReindexHandlerTests` (`ReindexHandlerTests.swift`), not a
// standalone `.serialized` suite of its own: `AppDependencyManager.shared` is
// a process-global registry keyed by dependency type, and the F3 reindex
// suites in this same target register the same `any AnalyticsService`/
// `PlaycutHistoryStore` types. `ReindexHandlerTests`'s `.serialized` trait
// governs its whole descendant tree, so nesting here closes the same race
// those suites' own doc comments describe, without inventing a second
// registration mechanism.
//
// Deliberately stops at registration rather than also reading a
// `@Dependency` property afterward -- see the file header for why.
extension ReindexHandlerTests {

@Suite("AppIntentsDependencies bootstrap (#751)")
struct AppIntentsDependenciesBootstrapTests {
    @Test("registerForWidget registers every dependency slot without throwing")
    func registerForWidgetCompletes() {
        AppIntentsDependencies.registerForWidget(playcutHistoryStore: PlaycutEntityQueryTests.makeHistoryStore())
    }

    @Test("registerForApp registers every dependency slot without throwing")
    func registerForAppCompletes() {
        AppIntentsDependencies.registerForApp(
            playcutHistoryStore: PlaycutEntityQueryTests.makeHistoryStore(),
            playcutReindexer: WidgetSafePlaycutReindexer(),
            concertReindexer: WidgetSafeConcertReindexer(),
            concertsFetching: WidgetSafeConcertsFetching(),
            analytics: WidgetSafeAnalyticsService()
        )
    }
}

}
