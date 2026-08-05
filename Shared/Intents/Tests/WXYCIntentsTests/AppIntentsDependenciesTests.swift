//
//  AppIntentsDependenciesTests.swift
//  WXYCIntents
//
//  Verifies the #751 registration bootstrap. `AppIntentsDependenciesManifestTests`
//  is the completeness net: it reflects into `PlaycutEntityQuery`/
//  `ConcertEntityQuery` (the package's only two `@Dependency`-declaring types)
//  and asserts every `AppDependency<Value>` property-wrapper backing field
//  they declare is covered by `AppIntentsDependencies.dependencyManifest`, so
//  a future entity kind's `@Dependency` can't ship without a widget-safe
//  default. `WidgetSafeConcertsFetchingTests` covers the one widget-default
//  conformer with real branching logic; the other three
//  (`WidgetSafePlaycutReindexer`/`WidgetSafeConcertReindexer`/
//  `WidgetSafeAnalyticsService`) are pure no-ops with nothing to assert
//  beyond "conforms and compiles."
//
//  What this file deliberately does NOT do: call `entities(for:)` (or the
//  iOS 27 reindex handlers) on a `PlaycutEntityQuery`/`ConcertEntityQuery`
//  built via the bare `init()` the AppIntents runtime uses, even after
//  registering every dependency with `AppDependencyManager.shared`. Verified
//  empirically while writing this bootstrap: `@Dependency`'s wrappedValue
//  traps with "Dependency values can only be accessed inside of the intent
//  perform flow ... unless the value of the dependency is manually set prior
//  to access" even when `AppDependencyManager.shared.add(dependency:)` was
//  called immediately beforehand in the same test -- matching the documented
//  AppIntents behavior for `AppIntent.perform()` (which needs
//  `resolveAndPerform()`, not a direct call, for the same reason;
//  https://developer.apple.com/forums/thread/788837). `EntityQuery` has no
//  `resolveAndPerform()`-equivalent escape hatch, so there is no supported
//  way to drive real `@Dependency` resolution from a unit test for these
//  types. AC4's "widget process can resolve queries without trapping" is
//  therefore a documented manual check, not an automated one: launch the
//  NowPlayingWidget extension on a simulator/device (Xcode's Debug >
//  Attach to Process by PID, or add the widget and watch Console for a
//  crash) and confirm no `AppDependency ... was not initialized` trap.
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
    @Test("dependencyManifest covers every @Dependency property PlaycutEntityQuery/ConcertEntityQuery declare")
    func manifestCoversEveryDeclaredDependency() {
        let discovered = Self.dependencyTypes(reflecting: PlaycutEntityQuery())
            .union(Self.dependencyTypes(reflecting: ConcertEntityQuery()))
        let manifest = Set(AppIntentsDependencies.dependencyManifest.map(ObjectIdentifier.init))

        #expect(
            discovered == manifest,
            "A @Dependency-consumed type changed on an EntityQuery without a matching update to AppIntentsDependencies.dependencyManifest (#751) -- the widget bootstrap can no longer be assumed complete."
        )
    }

    /// Reflects into `value`'s stored properties and collects every child
    /// whose dynamic type is an `AppDependency<...>` property-wrapper
    /// instance -- the backing storage Swift synthesizes for a `@Dependency`
    /// property (surfaced as an underscore-prefixed field, e.g.
    /// `_historyStore`). Matches by the reflected type's own description
    /// rather than the label, the same "trust the runtime type, not the
    /// naming convention" idiom `WXYCAppShortcutsTests.reflectionContains`
    /// uses for AppIntents' other opaque storage.
    private static func dependencyTypes(reflecting value: Any) -> Set<ObjectIdentifier> {
        Set(
            Mirror(reflecting: value).children
                .filter { String(describing: type(of: $0.value)).hasPrefix("AppDependency<") }
                .map { ObjectIdentifier(type(of: $0.value)) }
        )
    }
}

@Suite("WidgetSafeConcertsFetching")
struct WidgetSafeConcertsFetchingTests {
    @Test("fetchConcerts resolves to an empty page rather than making a network request")
    func fetchConcertsResolvesEmpty() async throws {
        let fetcher = WidgetSafeConcertsFetching()

        let response = try await fetcher.fetchConcerts(curated: true, from: nil, to: nil, page: 1, limit: 50)

        #expect(response.concerts.isEmpty)
        #expect(response.pagination.hasMore == false)
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

    @Test("WidgetSafeAnalyticsService discards a captured event without throwing")
    func analyticsServiceDiscardsCapturedEvent() {
        WidgetSafeAnalyticsService().capture(SpotlightReindexRequested(kind: "single", rowCount: 1))
    }
}
