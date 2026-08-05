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
//  `registerForApp(...)` wires Singletonia's real, capability-bearing
//  implementations -- Singletonia stays the composition root, this just
//  gives it one call instead of five inline `AppDependencyManager.shared.add`
//  calls. `registerForWidget(...)` wires read-only/no-op defaults that
//  resolve to safe-empty results instead: the widget never reindexes
//  Spotlight, fetches concerts, or reports analytics on its own, so trading
//  a crash for a quiet no-op there is a deliberate, encoded choice, not an
//  oversight -- see #751's "decision already made" note.
//
//  `dependencyManifest` is the completeness net: `AppIntentsDependenciesManifestTests`
//  reflects over every EntityQuery known to declare `@Dependency` properties
//  and asserts the discovered set matches this list exactly, so a future
//  entity kind's `@Dependency` can't reintroduce the trap by shipping without
//  a widget-safe default.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import Concerts
import Foundation
import Playlist

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
        AppDependencyManager.shared.add(dependency: playcutHistoryStore)
        AppDependencyManager.shared.add(dependency: playcutReindexer)
        AppDependencyManager.shared.add(dependency: concertReindexer)
        AppDependencyManager.shared.add(dependency: concertsFetching)
        AppDependencyManager.shared.add(dependency: analytics)
    }

    /// Registers widget-safe defaults. Called once from
    /// `NowPlayingWidgetBundle.init()`, the widget extension's own process
    /// entry point -- `Singletonia` never runs there.
    ///
    /// - Parameter playcutHistoryStore: Defaults to a fresh, disk-backed
    ///   store the widget process never feeds (`start(observing:)`/`ingest(_:)`
    ///   are app-only calls), so reads come back empty rather than trapping.
    ///   Overridable so a test can inject an in-memory-backed store instead
    ///   of touching the real `playcut-history` disk cache -- the same
    ///   isolation `PlaycutEntityQueryTests.makeHistoryStore()` uses.
    public static func registerForWidget(playcutHistoryStore: PlaycutHistoryStore = PlaycutHistoryStore()) {
        AppDependencyManager.shared.add(dependency: playcutHistoryStore)
        AppDependencyManager.shared.add(dependency: WidgetSafePlaycutReindexer() as any PlaycutReindexer)
        AppDependencyManager.shared.add(dependency: WidgetSafeConcertReindexer() as any ConcertReindexer)
        AppDependencyManager.shared.add(dependency: WidgetSafeConcertsFetching() as any ConcertsFetching)
        AppDependencyManager.shared.add(dependency: WidgetSafeAnalyticsService() as any AnalyticsService)
    }

    /// Every `AppDependency<Value>` property-wrapper backing-storage metatype
    /// this package's `@Dependency` properties declare: `PlaycutEntityQuery`'s
    /// `historyStore`/`reindexer`/`analytics` and `ConcertEntityQuery`'s
    /// `reindexer`/`concertsFetching`/`analytics`. Five entries, not six --
    /// `analytics` is one `any AnalyticsService` type shared by both queries.
    static let dependencyManifest: [Any.Type] = [
        AppDependency<PlaycutHistoryStore>.self,
        AppDependency<any PlaycutReindexer>.self,
        AppDependency<any AnalyticsService>.self,
        AppDependency<any ConcertReindexer>.self,
        AppDependency<any ConcertsFetching>.self,
    ]
}
