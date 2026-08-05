//
//  AppIntentsDependencies.swift
//  Intents
//
//  Single registration bootstrap for every `@Dependency`-backed type this
//  package's AppIntents surface declares (#751). `@Dependency`'s wrappedValue
//  traps if its type was never registered with `AppDependencyManager`, and
//  WXYCIntents links into two processes -- the app and the NowPlayingWidget
//  extension -- each of which must register every type before the AppIntents
//  runtime can construct a `PlaycutEntityQuery`/`ConcertEntityQuery` in that
//  process. `Singletonia` never runs in the widget's `.appex` process, so
//  without this the widget process would hit an unregistered dependency the
//  first time it resolved one of those queries.
//
//  `AppIntentsDependencySlot` is the single source of truth both bootstrap
//  entry points and the completeness test key off: `dependencyType` and the
//  per-slot registration switches in `registerForApp`/`registerForWidget`
//  all switch over the same `CaseIterable` enum exhaustively (no `default:`
//  case), so adding a slot is a compile error in every one of those switches
//  until it's handled -- the manifest `AppIntentsDependenciesManifestTests`
//  checks against and what the bootstrap functions actually register cannot
//  drift apart (#751 review, finding B1: a hand-maintained manifest array and
//  a hand-maintained registration body are two lists that can silently go
//  out of sync under green tests).
//
//  `registerForApp(...)` wires Singletonia's real, capability-bearing
//  implementations -- Singletonia stays the composition root, this just
//  gives it one call instead of five inline `AppDependencyManager.shared.add`
//  calls. `registerForWidget(...)` wires read-only/no-op defaults that
//  resolve to safe-empty results instead: the widget never reindexes
//  Spotlight, fetches concerts, or reports analytics on its own, so trading
//  a crash for a quiet no-op there is a deliberate, encoded choice, not an
//  oversight -- see #751's "decision already made" note.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import Caching
import Concerts
import Foundation
import Playlist

/// One slot per `@Dependency` type this package's AppIntents surface
/// declares. See the file header for why every switch over this enum's
/// cases must stay exhaustive (no `default:`).
enum AppIntentsDependencySlot: CaseIterable {
    case playcutHistoryStore
    case playcutReindexer
    case analytics
    case concertReindexer
    case concertsFetching

    /// The `AppDependency<Value>` property-wrapper backing-storage metatype
    /// this slot corresponds to. `AppIntentsDependenciesManifestTests`
    /// derives a source-form type name from this (stripping the
    /// `AppDependency<...>` wrapper) and compares it against every
    /// `@Dependency` declaration found by scanning `Sources/Intents`.
    var dependencyType: Any.Type {
        switch self {
        case .playcutHistoryStore: AppDependency<PlaycutHistoryStore>.self
        case .playcutReindexer: AppDependency<any PlaycutReindexer>.self
        case .analytics: AppDependency<any AnalyticsService>.self
        case .concertReindexer: AppDependency<any ConcertReindexer>.self
        case .concertsFetching: AppDependency<any ConcertsFetching>.self
        }
    }
}

public enum AppIntentsDependencies {
    /// Registers Singletonia's real implementations. Called once from
    /// `Singletonia.init()`, before any intent or entity query the AppIntents
    /// runtime might construct in the app process can run.
    public static func registerForApp(
        playcutHistoryStore: PlaycutHistoryStore,
        playcutReindexer: any PlaycutReindexer,
        concertReindexer: any ConcertReindexer,
        concertsFetching: any ConcertsFetching,
        analytics: any AnalyticsService
    ) {
        for slot in AppIntentsDependencySlot.allCases {
            switch slot {
            case .playcutHistoryStore:
                AppDependencyManager.shared.add(dependency: playcutHistoryStore)
            case .playcutReindexer:
                AppDependencyManager.shared.add(dependency: playcutReindexer)
            case .analytics:
                AppDependencyManager.shared.add(dependency: analytics)
            case .concertReindexer:
                AppDependencyManager.shared.add(dependency: concertReindexer)
            case .concertsFetching:
                AppDependencyManager.shared.add(dependency: concertsFetching)
            }
        }
    }

    /// Registers widget-safe defaults. Called once from
    /// `NowPlayingWidgetBundle.init()`, the widget extension's own process
    /// entry point -- `Singletonia` never runs there.
    ///
    /// - Parameter playcutHistoryStore: Defaults to an in-memory-backed store
    ///   (`CacheCoordinator(cache: InMemoryCache())`) that nothing ever
    ///   writes to, expressing "deliberately empty" rather than "just
    ///   happens to be empty": a disk-backed default would still resolve
    ///   every read to nothing (the widget process never calls
    ///   `start(observing:)`/`ingest(_:)`), but would also create a
    ///   `playcut-history` directory in the appex's own container and spawn
    ///   a purge task on every widget launch for a store nothing populates
    ///   (#751 review, non-blocking finding). Overridable so a test can
    ///   inject its own isolated store -- see
    ///   `AppIntentsDependenciesBootstrapTests` in `ReindexHandlerTests.swift`.
    public static func registerForWidget(
        playcutHistoryStore: PlaycutHistoryStore = PlaycutHistoryStore(
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
        )
    ) {
        for slot in AppIntentsDependencySlot.allCases {
            switch slot {
            case .playcutHistoryStore:
                AppDependencyManager.shared.add(dependency: playcutHistoryStore)
            case .playcutReindexer:
                AppDependencyManager.shared.add(dependency: WidgetSafePlaycutReindexer() as any PlaycutReindexer)
            case .analytics:
                AppDependencyManager.shared.add(dependency: WidgetSafeAnalyticsService() as any AnalyticsService)
            case .concertReindexer:
                AppDependencyManager.shared.add(dependency: WidgetSafeConcertReindexer() as any ConcertReindexer)
            case .concertsFetching:
                AppDependencyManager.shared.add(dependency: WidgetSafeConcertsFetching() as any ConcertsFetching)
            }
        }
    }

    /// Every `AppDependency<Value>` property-wrapper backing-storage metatype
    /// this package declares, derived from `AppIntentsDependencySlot` rather
    /// than hand-listed here a second time (#751 review, finding B1).
    static var dependencyManifest: [Any.Type] {
        AppIntentsDependencySlot.allCases.map(\.dependencyType)
    }
}
