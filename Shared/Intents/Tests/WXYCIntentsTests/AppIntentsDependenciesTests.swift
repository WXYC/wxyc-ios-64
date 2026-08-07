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

    /// Scans every `.swift` file under `Sources/Intents` for the `@Dependency`
    /// attribute followed by `var name: Type`, and returns the set of distinct
    /// (`any `-stripped) type names found.
    ///
    /// The walk is recursive and the separator is `\s+` rather than
    /// `\s*\n\s*`, so neither a future `Sources/Intents/<Subdir>/` nor the
    /// single-line `@Dependency var x: Y` spelling can slip a declaration past
    /// the completeness check. Both used to: the directory listing was flat
    /// and the pattern required a newline, so a declaration in either shape
    /// would leave this test green while the widget process regained exactly
    /// the unregistered-`@Dependency` trap #751 exists to prevent. The
    /// remaining gap is narrow and deliberate -- an attribute and its `var`
    /// separated by a comment, or a type name spanning a line break, still
    /// escape.
    private static func declaredDependencyTypeNames() throws -> Set<String> {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // this file -> WXYCIntentsTests/
            .deletingLastPathComponent() // -> Tests/
            .deletingLastPathComponent() // -> Intents/ (package root)
            .appendingPathComponent("Sources/Intents", isDirectory: true)

        guard let walker = FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil) else {
            Issue.record("Couldn't enumerate \(sourcesDirectory.path) -- the completeness check would pass vacuously.")
            return []
        }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }

        let pattern = /@Dependency\s+(?:public |private |internal )?var\s+\w+\s*:\s*([^\n]+)/

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
    /// `AppDependency<...>` wrapper, strip a leading `any `, then rewrite the
    /// runtime's spelling of a parameterized existential back to source form.
    private static func sourceTypeName(for slot: AppIntentsDependencySlot) -> String {
        let described = String(describing: slot.dependencyType) // e.g. "AppDependency<PlaycutHistoryStore>"
        let prefix = "AppDependency<"
        guard described.hasPrefix(prefix), described.hasSuffix(">") else { return described }
        return Self.stripSameTypeConstraints(Self.stripAny(String(described.dropFirst(prefix.count).dropLast())))
    }

    private static func stripAny(_ typeName: String) -> String {
        typeName.hasPrefix("any ") ? String(typeName.dropFirst(4)) : typeName
    }

    /// Rewrites the runtime spelling of a parameterized existential's generic
    /// arguments into the source spelling.
    ///
    /// `String(describing: (any SpotlightReindexer<PlaycutEntity>).self)` does
    /// not round-trip: the runtime renders the primary associated type as the
    /// same-type constraint it desugars to —
    /// `SpotlightReindexer<Self.SpotlightReindexer.Source == PlaycutEntity>` —
    /// while the source text this is compared against says
    /// `SpotlightReindexer<PlaycutEntity>`. Dropping each `Self.Proto.Assoc == `
    /// prefix reconciles them.
    ///
    /// This only started mattering when #758 replaced the two per-kind reindexer
    /// protocols with one generic `SpotlightReindexer<Source>`: every slot's
    /// type was a plain existential before, so the two spellings happened to
    /// agree and nothing here had to normalize. Merging #751 and #758 is what
    /// surfaced it — neither branch alone could.
    private static func stripSameTypeConstraints(_ typeName: String) -> String {
        // Extended `#/.../#` delimiters: a bare `/.../` literal may not end in
        // a space, and this pattern's trailing space is load-bearing.
        typeName.replacing(#/Self\.\w+\.\w+ == /#, with: "")
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
    @Test("WidgetSafeSpotlightReindexer discards a playcut donation without throwing")
    func playcutReindexerDiscardsDonation() async throws {
        let playcut = Playcut.stub(id: 1, artistName: "Juana Molina")
        try await WidgetSafeSpotlightReindexer<PlaycutEntity>().donate([PlaycutEntity(playcut: playcut)])
    }

    // Both kinds stay covered even though one generic type now serves both:
    // the registration switch in `registerForWidget` instantiates it twice, at
    // two different `Source` types, and a wrong type argument at either slot is
    // what these two tests catch.
    @Test("WidgetSafeSpotlightReindexer discards a concert donation without throwing")
    func concertReindexerDiscardsDonation() async throws {
        try await WidgetSafeSpotlightReindexer<Concert>().donate([.stub()])
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
            playcutReindexer: WidgetSafeSpotlightReindexer<PlaycutEntity>(),
            concertReindexer: WidgetSafeSpotlightReindexer<Concert>(),
            concertsFetching: WidgetSafeConcertsFetching(),
            analytics: WidgetSafeAnalyticsService()
        )
    }
}

}
