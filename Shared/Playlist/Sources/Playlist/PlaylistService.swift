//
//  PlaylistService.swift
//  Playlist
//
//  Main service for fetching and caching playlists with periodic updates and multi-observer
//  broadcasting via AsyncStream. Provides cache-aware fetching for widgets and extensions.
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Logger
import Caching

public final actor PlaylistService: Sendable {
    private var fetcher: PlaylistFetcherProtocol

    /// Builds the fetcher for a given version. `switchAPIVersion(to:)` rebuilds
    /// through this rather than hard-coding `PlaylistFetcher(apiVersion:)`, so a
    /// caller that injected a double at `init` keeps it across a version switch
    /// instead of silently having it replaced by a live-network fetcher.
    ///
    /// When no fetcher was injected, this is the real
    /// `PlaylistFetcher(apiVersion:)` and production behavior is unchanged.
    private let fetcherFactory: @Sendable (PlaylistAPIVersion) -> PlaylistFetcherProtocol

    private var interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var fetchTask: Task<Void, Never>?
    private let cacheCoordinator: CacheCoordinator
    private static let cacheKey = PlaylistCacheKey.playlist
    private static let cacheLifespan: TimeInterval = 15 * 60 // 15 minutes

    /// The resolved playlist API version this instance is currently wired
    /// for. Set once at `init` (from the `apiVersion` argument, or
    /// `PlaylistAPIVersion.loadActive()` when omitted) and reassigned by
    /// `switchAPIVersion(to:)`.
    private var apiVersion: PlaylistAPIVersion

    /// A test-supplied poll interval, or `nil` to derive it from the wiring
    /// (see ``liveUpdatesReconciliationInterval`` / ``pollOnlyInterval``).
    /// `switchAPIVersion(to:)` must never stomp an explicit override — tests
    /// that pin an `interval` expect it to stay pinned across a version
    /// switch.
    private let intervalOverride: TimeInterval?

    // MARK: - Live updates (SSE)

    /// Poll cadence used only as a reconciliation backstop when SSE live
    /// updates are actually wired in (`apiVersion.supportsLiveUpdates &&`
    /// caller opted in). Defensible only because inserts/updates already
    /// arrive over the push channel while foregrounded — see
    /// `setForegrounded(_:)`. Keying this off the *resolved wiring*, not the
    /// API version alone, matters: `WXYC/WatchXYC/PlaylistPage.swift` and
    /// `PlayerPage.swift` consume `updates()` as their only refresh path and
    /// never opt into SSE, so a version-keyed 300 s would silently make the
    /// watch up to 5 minutes stale once `PlaylistAPIVersion.defaultVersion`
    /// flips to `.v2`.
    private static let liveUpdatesReconciliationInterval: TimeInterval = 300

    /// Poll cadence when no push channel backs freshness: v1 always (it has
    /// no SSE channel — see `PlaylistAPIVersion.supportsLiveUpdates`), and v2
    /// when the caller didn't opt into live updates (watchOS/tvOS/widgets/
    /// intents).
    private static let pollOnlyInterval: TimeInterval = 30

    /// The caller's immutable live-updates opt-in — the `liveEventSource`
    /// passed at `init` (directly, or via `FlowsheetLiveEventSource()` when
    /// `liveUpdatesEnabled: true`), or `nil` when the caller never opted in.
    /// Unlike ``activeLiveEventSource``, this never changes: it's the ceiling
    /// `switchAPIVersion(to:)` re-derives the active source from on every
    /// version change.
    private let liveEventSourceIfEnabled: (any LiveFsEventSource)?

    /// The currently-installed `live-fs-topic` SSE source — `liveEventSourceIfEnabled`
    /// when the resolved `apiVersion` supports live updates, `nil` otherwise
    /// (including when the caller never opted in). This is what
    /// `setForegrounded`/`ensureLiveUpdatesRunning`/`consumeLiveEvents` read;
    /// re-derived by `init` and by `switchAPIVersion(to:)` on every version
    /// change. See WXYC/wxyc-ios-64#269, #749.
    private var activeLiveEventSource: (any LiveFsEventSource)?

    /// The running SSE consume loop, or `nil` when backgrounded / not enabled.
    private var liveUpdatesTask: Task<Void, Never>?

    /// Identifies the current consume loop, so a loop that exits after being
    /// superseded can tell whether `liveUpdatesTask` still refers to it before
    /// clearing it. See the `defer` in `consumeLiveEvents(generation:)`. Same
    /// bump-capture-compare idiom as `AudioPlayerController`'s
    /// `sessionActivationGeneration`; a third site should hoist a shared
    /// helper into Core rather than fork the pattern again.
    private var liveUpdatesGeneration = 0

    /// True while `switchAPIVersion(to:)` is between tearing down the old
    /// wiring and installing the new one. `ensureLiveUpdatesRunning()` refuses
    /// to start a loop while set, because any loop started in that window
    /// would bind the *pre-switch* source (`consumeLiveEvents` captures it
    /// once, at the top) and then outlive the switch. Only ever mutated
    /// synchronously on the actor, so a reentrant call parked on one of
    /// `switchAPIVersion`'s awaits always observes the current value.
    private var isSwitchingAPIVersion = false

    /// The app's current foreground state. The SSE subscription is opened only
    /// while foregrounded and torn down on background — a long-lived socket in
    /// the background is wasteful and the OS reclaims it anyway.
    private var isForegrounded = false

    /// Reconnect backoff bounds for the SSE consume loop.
    private static let minReconnectBackoff: Duration = .seconds(1)
    private static let maxReconnectBackoff: Duration = .seconds(30)

    /// Collection of continuations for broadcasting to multiple observers
    private var continuations: [UUID: AsyncStream<Playlist>.Continuation] = [:]
    
    /// Task that loads the initial cached playlist. Awaited before first yield to prevent
    /// race conditions where observers subscribe before cache is loaded.
    /// 
    /// Note: This is marked `nonisolated(unsafe)` because it's assigned once during `init`
    /// (which is nonisolated in actors) and only read afterwards. This is safe because:
    /// 1. The write happens before any async work can read it
    /// 2. Task is a reference type and the reference itself doesn't change after init
    private nonisolated(unsafe) var cacheLoadTask: Task<Void, Never>?
    
    /// Whether the initial cache load has completed. Used to avoid awaiting the task
    /// on subsequent subscriptions.
    private var cacheLoaded = false

    /// Designated initializer. Takes the live-updates source directly so tests
    /// can inject a scripted `MockLiveFsEventSource`; app code uses the
    /// `liveUpdatesEnabled` convenience initializer below instead.
    ///
    /// - Parameters:
    ///   - fetcher: Fetcher to use. When `nil` (the default), one is built
    ///     from the single `resolvedVersion` below — never from a second,
    ///     independent `PlaylistAPIVersion.loadActive()` call. That matters
    ///     because the version comes from a PostHog flag snapshot that loads
    ///     asynchronously at launch: two independent reads could disagree at
    ///     cold start, wiring the service for one version while the fetcher
    ///     pulls another. Note this only couples the *derived* fetcher to
    ///     `apiVersion`: pass a `PlaylistFetcher(apiVersion:)` built against a
    ///     different version here and the two will disagree by construction,
    ///     so callers injecting a real fetcher should pass a matching
    ///     `apiVersion`. An injected fetcher is also kept for the lifetime of
    ///     the service — `switchAPIVersion(to:)` rebuilds only the derived one.
    ///   - interval: A test-supplied poll interval override. When `nil` (the
    ///     default), the interval is derived from the resolved wiring — see
    ///     ``liveUpdatesReconciliationInterval`` / ``pollOnlyInterval``.
    ///   - apiVersion: The API version to resolve against. When `nil` (the
    ///     default), resolves via `PlaylistAPIVersion.loadActive()`.
    init(
        fetcher: PlaylistFetcherProtocol? = nil,
        interval: TimeInterval? = nil,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist,
        liveEventSource: (any LiveFsEventSource)?,
        apiVersion: PlaylistAPIVersion? = nil
    ) {
        let resolvedVersion = apiVersion ?? PlaylistAPIVersion.loadActive()
        self.apiVersion = resolvedVersion
        // An injected fetcher is a deliberate test double: keep returning it
        // so `switchAPIVersion(to:)` can't swap it out for a live-network one.
        if let fetcher {
            self.fetcherFactory = { _ in fetcher }
            self.fetcher = fetcher
        } else {
            self.fetcherFactory = { PlaylistFetcher(apiVersion: $0) }
            self.fetcher = PlaylistFetcher(apiVersion: resolvedVersion)
        }
        self.intervalOverride = interval
        self.cacheCoordinator = cacheCoordinator
        self.liveEventSourceIfEnabled = liveEventSource

        let liveUpdatesActive = resolvedVersion.supportsLiveUpdates && liveEventSource != nil
        self.activeLiveEventSource = liveUpdatesActive ? liveEventSource : nil
        self.interval = interval ?? (
            liveUpdatesActive ? Self.liveUpdatesReconciliationInterval : Self.pollOnlyInterval
        )

        // Start loading cached playlist immediately.
        // Observers will await this task before receiving their first value.
        cacheLoadTask = Task { [self] in
            await self.loadCachedPlaylist()
        }
    }

    /// Creates a `PlaylistService`.
    ///
    /// - Parameters:
    ///   - liveUpdatesEnabled: When `true`, the caller opts into a
    ///     `live-fs-topic` SSE subscription while foregrounded (see
    ///     ``setForegrounded(_:)``). Whether a subscription is actually
    ///     wired up is a conjunction of this opt-in *and* the resolved
    ///     `apiVersion` supporting live updates
    ///     (``PlaylistAPIVersion/supportsLiveUpdates``) — v1 has no push
    ///     channel, so opting in has no effect there. Defaults to `false`,
    ///     preserving the poll-only behavior for watchOS/tvOS/widgets. Only
    ///     the iOS app enables it. The poll interval follows the same
    ///     conjunction — see ``liveUpdatesReconciliationInterval`` /
    ///     ``pollOnlyInterval`` — so callers no longer pass it explicitly to
    ///     get the long reconciliation cadence.
    ///   - apiVersion: The API version to resolve against. When `nil` (the
    ///     default), resolves via `PlaylistAPIVersion.loadActive()`. Public
    ///     — mirroring the already-public `PlaylistFetcher(apiVersion:)` —
    ///     so a test can force a version through this production-shaped
    ///     initializer without mutating the shared `UserDefaults.wxyc` app
    ///     group, which is process-global and would make parallel test
    ///     suites order-dependent.
    public init(
        fetcher: PlaylistFetcherProtocol? = nil,
        interval: TimeInterval? = nil,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist,
        liveUpdatesEnabled: Bool = false,
        apiVersion: PlaylistAPIVersion? = nil
    ) {
        self.init(
            fetcher: fetcher,
            interval: interval,
            cacheCoordinator: cacheCoordinator,
            liveEventSource: liveUpdatesEnabled ? FlowsheetLiveEventSource() : nil,
            apiVersion: apiVersion
        )
    }

    /// Load cached playlist if available and not expired.
    /// Called once at initialization.
    private func loadCachedPlaylist() async {
        defer { cacheLoaded = true }
        
        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            currentPlaylist = cachedPlaylist
            // Broadcast cached data to any existing observers
            broadcast(cachedPlaylist)
            Log(.info, category: .network, "Loaded cached playlist with \(cachedPlaylist.entries.count) entries")
        } catch {
            Log(.info, category: .network, "No valid cached playlist available")
        }
    }
    
    /// Check if the cached playlist has expired or doesn't exist.
    /// Used to determine if a foreground refresh is needed.
    public func isCacheExpired() async -> Bool {
        do {
            // Attempt to read from cache - this will throw if expired or missing
            let _: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            return false
        } catch {
            return true
        }
    }
    
    /// Waits for the initial cache load to complete.
    ///
    /// The service automatically loads cached data at initialization.
    /// This method allows callers to await that operation's completion.
    public func waitForCacheLoad() async {
        if !cacheLoaded {
            await cacheLoadTask?.value
        }
    }
    
    /// Returns the number of entries in the current playlist.
    /// Used for checking if the playlist has loaded.
    public func currentEntryCount() async -> Int {
        await waitForCacheLoad()
        return currentPlaylist.entries.count
    }

    /// The current in-memory playlist snapshot (after the initial cache load).
    /// Cheaper than `fetchPlaylist()` when a caller only needs to read
    /// already-loaded state — no cache/network round trip — and, unlike
    /// `currentEntryCount()`, exposes the actual playlist so a caller can check
    /// for a specific entry type (e.g. a playcut, not just any entry).
    public func currentPlaylistSnapshot() async -> Playlist {
        await waitForCacheLoad()
        return currentPlaylist
    }
    
    /// Fetch playlist and cache it, always fetching fresh data (ignores cache).
    /// Used for background refresh to ensure we always get the latest data.
    ///
    /// Important: This method does NOT replace valid data with empty playlists.
    /// If the fetch fails (returning `.empty`), existing cached data is preserved.
    public func fetchAndCachePlaylist() async -> Playlist {
        let playlist = await fetcher.fetchPlaylist()

        if await ingest(playlist) {
            Log(.info, category: .network, "Fetched and cached playlist with \(playlist.entries.count) entries \(playlist.entries)")
        } else {
            Log(.warning, category: .network, "Ignoring empty playlist from background refresh - keeping existing data with \(currentPlaylist.entries.count) entries")
        }

        // Return the fetched playlist (may be empty), but in-memory state is preserved
        return playlist
    }

    /// Direct fetch method for widgets and extensions that need immediate data.
    /// First checks the cache, and if cache is empty or expired, fetches from network.
    /// This method is designed for widget timeline providers that have strict time constraints.
    public func fetchPlaylist() async -> Playlist {
        // Try to get cached playlist first
        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            Log(.info, category: .network, "Returning cached playlist with \(cachedPlaylist.entries.count) entries")
            return cachedPlaylist
        } catch {
            // Cache miss or expired - fetch from network
            Log(.info, category: .network, "Cache miss, fetching fresh playlist")
            let playlist = await fetcher.fetchPlaylist()

            // Cache the result for future use
            await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

            Log(.info, category: .network, "Fetched and cached new playlist with \(playlist.entries.count) entries")
            return playlist
        }
    }
            
    /// Switches to a different API version and immediately fetches fresh data.
    /// Clears the current playlist and cache before fetching to ensure clean data.
    /// Also re-derives the SSE subscription and poll interval from the new
    /// version, per the same `apiVersion.supportsLiveUpdates && callerOptedIn`
    /// conjunction `init` applies — a runtime switch must not leave either one
    /// stale (WXYC/wxyc-ios-64#749).
    ///
    /// - Parameter version: The API version to switch to.
    public func switchAPIVersion(to version: PlaylistAPIVersion) async {
        Log(.info, category: .network, "Switching playlist API to \(version.rawValue)")

        // Latch before the first await so every reentrant call parked below
        // sees it. Cleared just before the rebuild's own ensure calls.
        isSwitchingAPIVersion = true

        // Cancel the live-updates loop and await its completion BEFORE
        // touching `activeLiveEventSource`/`currentPlaylist` below.
        // `consumeLiveEvents` binds its `source` once at the top of the
        // loop, so nilling the property alone would not stop an in-flight
        // consume — only cancellation does, and we must wait for the loop to
        // actually observe it and return so a straggler `upsertPlaycut` from
        // the old source can't broadcast after `currentPlaylist` resets below.
        //
        // Awaiting `.value` suspends this actor method, so other calls run on
        // reentrant turns while we're parked — `setForegrounded(_:)` in
        // particular, which mutates `liveUpdatesTask`. Without a guard, its
        // `(false)` then `(true)` pair would nil the field and then start a
        // fresh loop bound to the *pre-switch* source (`consumeLiveEvents`
        // captures it once, at the top), and the clear below would drop that
        // loop's handle — orphaning it with nothing able to cancel it, not
        // backgrounding and not a later switch.
        //
        // `isSwitchingAPIVersion` is what prevents that: it spans this whole
        // method and `ensureLiveUpdatesRunning()` refuses to start under it,
        // so across the await `liveUpdatesTask` can only go to nil, never to
        // a new task. The conditional clear below is therefore provably
        // equivalent to an unconditional `= nil` today — it is kept as
        // defense-in-depth in case the latch is ever narrowed, NOT as the
        // mechanism that closes the orphan. Don't remove the latch on the
        // strength of the conditional; that reintroduces the bug.
        let cancelledLiveUpdates = liveUpdatesTask
        cancelledLiveUpdates?.cancel()
        await cancelledLiveUpdates?.value
        if liveUpdatesTask == cancelledLiveUpdates {
            liveUpdatesTask = nil
        }

        // Everything from here to the `fetchAndCachePlaylist()` await is one
        // synchronous actor turn, so no reentrant call can observe half-swapped
        // wiring. `cancelFetchTask()` in particular must stay below the await
        // above: hoisted above it, a new `updates()` subscriber landing in the
        // window would restart `startFetching()` against the *old* fetcher, and
        // the restart at the bottom would then no-op because a task exists —
        // leaving the previous version's payload on screen until the loop's
        // next tick, which on the new interval can be five minutes away.
        cancelFetchTask()

        apiVersion = version

        // Rebuild the fetcher for the new version, preserving an injected
        // double (see `fetcherFactory`).
        fetcher = fetcherFactory(version)

        // Re-derive the SSE wiring and poll interval from the new version,
        // exactly as `init` does.
        let liveUpdatesActive = version.supportsLiveUpdates && liveEventSourceIfEnabled != nil
        activeLiveEventSource = liveUpdatesActive ? liveEventSourceIfEnabled : nil
        interval = intervalOverride ?? (
            liveUpdatesActive ? Self.liveUpdatesReconciliationInterval : Self.pollOnlyInterval
        )

        // Clear current playlist to show loading state
        currentPlaylist = .empty
        broadcast(.empty)

        // Fetch fresh data with new API version (this will overwrite the cache)
        _ = await fetchAndCachePlaylist()

        // New wiring is fully installed — reentrant calls may start loops again.
        isSwitchingAPIVersion = false

        // Restart fetch loop if we have observers
        if !continuations.isEmpty {
            ensureFetchTaskRunning()
        }

        // Restart the live-updates loop against the newly-derived source if
        // we're still foregrounded (a no-op when the new version doesn't
        // support live updates, since `ensureLiveUpdatesRunning` guards on
        // `activeLiveEventSource != nil`).
        if isForegrounded {
            ensureLiveUpdatesRunning()
        }
    }

    /// A snapshot of the service's currently-resolved wiring, for tests that
    /// need to observe the derived interval/subscription state without
    /// relaxing visibility on the individual fields.
    ///
    /// Deliberately `internal`, not `public`: its only consumers are this
    /// module's own tests, which reach it via `@testable import Playlist` —
    /// the same route the designated initializer above relies on. Making it
    /// `public` would commit the module to typed fields as permanent API for
    /// a test-only seam.
    struct WiringSnapshot: Sendable, Equatable {
        let apiVersion: PlaylistAPIVersion
        let pollInterval: TimeInterval
        let liveUpdatesActive: Bool

        /// Whether a live-updates consume loop is currently held. Distinct
        /// from ``liveUpdatesActive``, which reports whether a source is
        /// *wired in*: this reports whether a loop is actually running against
        /// it. The pair is what makes the `switchAPIVersion` reentrancy guard
        /// testable without waiting on the loop to reach `connect()` —
        /// `ensureLiveUpdatesRunning()` assigns `liveUpdatesTask`
        /// synchronously, before the task body runs, so observing this field
        /// needs no timing tolerance at all.
        let hasLiveUpdatesTask: Bool

        /// Whether a ``switchAPIVersion(to:)`` is currently in flight. Lets a
        /// test wait for the switch to have latched before driving reentrant
        /// calls at it, instead of racing an unstructured `Task`'s start.
        let isSwitchingAPIVersion: Bool
    }

    /// Returns the service's currently-resolved wiring — the API version,
    /// poll interval, whether an SSE subscription is wired in
    /// (``PlaylistAPIVersion/supportsLiveUpdates`` and the caller opted in),
    /// and whether a consume loop is currently held.
    func wiringSnapshot() -> WiringSnapshot {
        WiringSnapshot(
            apiVersion: apiVersion,
            pollInterval: interval,
            liveUpdatesActive: activeLiveEventSource != nil,
            hasLiveUpdatesTask: liveUpdatesTask != nil,
            isSwitchingAPIVersion: isSwitchingAPIVersion
        )
    }

    /// Opens or closes the `live-fs-topic` SSE subscription in response to the
    /// app's foreground state.
    ///
    /// Called from the iOS app for `.active` (`true`) and `.background`
    /// (`false`) only — never for `.inactive`, which fires with the app still
    /// on screen (see `Core.ForegroundVisibility` for that story). The app's
    /// single scene-phase producer routes through
    /// `Singletonia.setScenePhase(_:)`, which classifies the phase once.
    ///
    /// Call order carries meaning and this method does not defend itself:
    /// inverted arrival latches `isForegrounded` against reality, and since
    /// `ensureLiveUpdatesRunning()` is reachable only from here and from
    /// `switchAPIVersion(to:)`, a wrong value is never re-checked and live
    /// updates stay down for the session. The iOS caller therefore delivers
    /// through an ordered relay (`Core.LatestValueRelay`); a new caller that
    /// reaches this method directly is unprotected.
    ///
    /// Tracks `isForegrounded` unconditionally —
    /// even when live updates aren't wired in for this instance right now
    /// (v1, or the caller never opted in) — so a later `switchAPIVersion(to:)`
    /// that DOES wire one in knows whether to start it immediately.
    /// `ensureLiveUpdatesRunning()` already guards on `activeLiveEventSource`
    /// being non-nil, and cancelling a nil task is harmless, so no outer
    /// guard is needed here. While foregrounded the service applies
    /// `insert`/`update` events as they arrive; the periodic `interval` poll
    /// stays running underneath as a reconciliation backstop.
    public func setForegrounded(_ foregrounded: Bool) {
        isForegrounded = foregrounded
        if foregrounded {
            ensureLiveUpdatesRunning()
        } else {
            liveUpdatesTask?.cancel()
            liveUpdatesTask = nil
        }
    }

    /// Returns an AsyncStream that yields playlist updates.
    /// If a cached playlist exists, it's yielded immediately.
    /// Otherwise, observers wait for the first fetch to complete.
    /// Multiple observers each receive their own stream of updates.
    public nonisolated func updates() -> AsyncStream<Playlist> {
        let id = UUID()
                
        return AsyncStream { continuation in
            let setupTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                
                await self.addContinuation(continuation, for: id)
            }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                setupTask.cancel()
                
                guard let self else { return }
        
                Task {
                    await self.removeContinuation(for: id)
                }
            }
        }
    }
        
    private func addContinuation(_ continuation: AsyncStream<Playlist>.Continuation, for id: UUID) async {
        continuations[id] = continuation
        
        // Wait for initial cache load to complete before deciding whether to yield.
        // This prevents a race condition where observers subscribe before the cache
        // is loaded, causing them to see an empty playlist until the network fetch completes.
        if !cacheLoaded {
            await cacheLoadTask?.value
        }
        
        // Yield current cache immediately if non-empty
        if currentPlaylist != .empty {
            continuation.yield(currentPlaylist)
        }
        
        // Start fetching if not already running
        ensureFetchTaskRunning()
    }
    
    /// Playcuts whose `metadataStatus` transitions into a terminal enrichment
    /// state (``MetadataStatus/isTerminal``) — i.e. the prior recorded status
    /// for that `id` was non-terminal (or the row was previously unseen), and
    /// the current status is terminal.
    ///
    /// Diffed independently per subscriber against ``updates()``, so late
    /// subscribers see a transition the first time they observe a terminal
    /// status for a given playcut, even if an earlier subscriber already saw
    /// it. Consumers that need "only once, ever" (e.g. Spotlight
    /// re-donation) gate on their own already-donated state — see
    /// `SpotlightDonationService.handleMetadataEnrichment(for:)` (issue #443).
    ///
    /// The first snapshot only seeds the per-subscriber baseline and yields
    /// nothing: on a warm launch the cached window is already fully enriched,
    /// and yielding every terminal row against an empty diff map would
    /// re-donate the whole window at every launch. A row is emitted only on a
    /// genuine subsequent transition into a terminal state.
    ///
    /// Non-terminal transitions (`nil` -> `.pending`, `.pending` -> `.enriching`)
    /// are not yielded, nor are re-broadcasts of an already-terminal status, nor
    /// a change between two different terminal states (`.enrichedMatch` ->
    /// `.enrichedNoMatch`) — only a transition *into* terminal from a
    /// non-terminal (or unseen) prior state fires.
    ///
    /// The baseline map is pruned to the current window after each snapshot so
    /// it stays bounded by the playlist size rather than growing an entry per
    /// unique playcut id for the app's lifetime.
    public nonisolated func terminalMetadataTransitions() -> AsyncStream<Playcut> {
        AsyncStream { continuation in
            let task = Task {
                var previousStatusByID: [UInt64: MetadataStatus] = [:]
                var didSeedBaseline = false

                for await playlist in self.updates() {
                    for playcut in playlist.playcuts {
                        let previousStatus = previousStatusByID[playcut.id]
                        previousStatusByID[playcut.id] = playcut.metadataStatus

                        // The initial snapshot only establishes the baseline.
                        guard didSeedBaseline else { continue }

                        guard let status = playcut.metadataStatus, status.isTerminal else { continue }
                        // Fire only on a transition *into* terminal: the prior
                        // recorded state must be non-terminal (or unseen).
                        // Terminal -> terminal is a re-broadcast, not a landing.
                        guard !(previousStatus?.isTerminal ?? false) else { continue }

                        continuation.yield(playcut)
                    }

                    didSeedBaseline = true

                    // Prune ids no longer in the tracked window so the baseline
                    // map stays bounded by the playlist size, not app lifetime.
                    let currentIDs = Set(playlist.playcuts.map(\.id))
                    previousStatusByID = previousStatusByID.filter { currentIDs.contains($0.key) }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func removeContinuation(for id: UUID) {
        continuations.removeValue(forKey: id)
        
        // Stop fetching if no more observers
        if continuations.isEmpty {
            cancelFetchTask()
        }
    }

    /// Broadcast a playlist update to all observers
    private func broadcast(_ playlist: Playlist) {
        for continuation in continuations.values {
            continuation.yield(playlist)
        }
    }

    private func cancelFetchTask() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
        fetchTask?.cancel()
        liveUpdatesTask?.cancel()
    }

    /// Ensure the fetch task is running
    private func ensureFetchTaskRunning() {
        guard fetchTask == nil else { return }

        fetchTask = Task {
            await startFetching()
        }
    }

    // MARK: - Live updates (SSE)

    /// Ensure the live-updates consume loop is running (foregrounded + enabled).
    private func ensureLiveUpdatesRunning() {
        guard !isSwitchingAPIVersion else { return }
        guard activeLiveEventSource != nil, isForegrounded, liveUpdatesTask == nil else { return }
        liveUpdatesGeneration &+= 1
        let generation = liveUpdatesGeneration
        liveUpdatesTask = Task { await self.consumeLiveEvents(generation: generation) }
    }

    /// Consumes the SSE stream while foregrounded, reconnecting with exponential
    /// backoff (capped at ``maxReconnectBackoff``) when the connection drops.
    ///
    /// Each ``LiveFsEventSource/connect()`` models one connection attempt whose
    /// stream finishes when the socket ends; this loop reopens it. The backoff
    /// resets to ``minReconnectBackoff`` as soon as a connection delivers an
    /// event, and grows only when an attempt produced nothing (a hard failure,
    /// distinct from a healthy connection that simply closed).
    private func consumeLiveEvents(generation: Int) async {
        // Retire the field this loop occupies on *every* exit, not just the two
        // that cancel it from outside. `ensureLiveUpdatesRunning()` gates on
        // `liveUpdatesTask == nil`, so a loop that returns on its own — the
        // `guard` below, or the `while` terminating — would otherwise leave a
        // finished task parked in the field and the gate would refuse to start
        // another for the rest of the session.
        //
        // The generation check is what makes that safe: a cancelled loop can
        // run its `defer` *after* a newer one has already registered itself,
        // and clearing the field then would orphan the live loop and let a
        // third start alongside it.
        defer {
            if liveUpdatesGeneration == generation {
                liveUpdatesTask = nil
            }
        }

        guard let source = activeLiveEventSource else { return }

        // Splice events into the cache-loaded baseline, not the `.empty`
        // pre-load state a racing early event would otherwise be overwritten on.
        await waitForCacheLoad()

        var backoff = Self.minReconnectBackoff
        while !Task.isCancelled && isForegrounded {
            var sawEvent = false
            for await event in source.connect() {
                if Task.isCancelled { break }
                sawEvent = true
                backoff = Self.minReconnectBackoff
                await applyLiveEvent(event)
            }

            guard !Task.isCancelled, isForegrounded else { break }

            // Connection closed — wait, then reconnect. Grow the backoff only
            // when the attempt yielded nothing.
            try? await Task.sleep(for: backoff)
            if !sawEvent {
                backoff = min(backoff * 2, Self.maxReconnectBackoff)
            }
        }
    }

    /// Applies one decoded live event to the in-memory playlist.
    private func applyLiveEvent(_ event: LiveFsEvent) async {
        switch event {
        case .insert(let playcut), .update(let playcut):
            guard belongsInWindow(playcut) else { return }
            // Both reduce to an upsert-by-id: an insert appends a new row, an
            // update replaces the existing one (the payload is the full
            // post-enrichment row, so a replace is the merge). Upserting also
            // makes a duplicate insert or an out-of-order update idempotent.
            await upsertPlaycut(playcut)
        case .refetch:
            // A bulk state change makes targeted patches unreliable; fall back
            // to a full reconciliation fetch.
            _ = await fetchAndCachePlaylist()
        }
    }

    /// Whether a pushed row belongs in the live window, i.e. its id is at least
    /// the lowest id the window currently holds.
    ///
    /// `live-fs-topic` is not exclusively a live feed: it also carries
    /// Backend's catalog-wide enrichment backfill, whose rows are years old and
    /// whose ids sit millions below the live head (#780). Those rows are real
    /// and correctly decoded, but they are not part of what this window shows,
    /// and `upsertPlaycut` would append every one of them — unbounded, and
    /// persisted to the disk cache — until the next reconciliation poll
    /// replaced the playlist wholesale.
    ///
    /// The floor is derived from the window rather than a fixed id so it tracks
    /// the poll: a row already in the window always passes (its id can't be
    /// below the minimum), and a genuinely new row always passes (Backend
    /// assigns ids in chronological order, so it's above the head). An empty
    /// window carries no floor and accepts, since there is nothing to judge
    /// against and the next poll reconciles regardless.
    ///
    /// This is a client-side defense, not the fix: the backfill arguably
    /// shouldn't be on a topic named `live-fs-topic` at all.
    private func belongsInWindow(_ playcut: Playcut) -> Bool {
        guard let floor = currentPlaylist.playcuts.map(\.id).min() else { return true }
        return playcut.id >= floor
    }

    /// Inserts or replaces a playcut by `id`, then caches and broadcasts.
    ///
    /// An insert simply appends: nothing reads this array positionally.
    /// `Playlist.entries` re-sorts by `(chronOrderID, id)` for the timeline, and
    /// the now-playing surfaces read `Playlist.currentPlaycut`, which applies
    /// the same order rather than taking the head — see that property for why
    /// the two stopped coinciding once the key became composite (#839). An
    /// identical replay is a no-op so it doesn't churn observers or the cache.
    private func upsertPlaycut(_ playcut: Playcut) async {
        var playcuts = currentPlaylist.playcuts
        if let index = playcuts.firstIndex(where: { $0.id == playcut.id }) {
            guard playcuts[index] != playcut else { return }
            playcuts[index] = playcut
        } else {
            playcuts.append(playcut)
        }

        // Row inserts/updates never change who's on the air, so `onAir` (and the
        // non-track arrays) carry through untouched; the periodic poll refreshes
        // them on its own cadence.
        let updated = Playlist(
            playcuts: playcuts,
            breakpoints: currentPlaylist.breakpoints,
            talksets: currentPlaylist.talksets,
            showMarkers: currentPlaylist.showMarkers,
            onAir: currentPlaylist.onAir
        )

        currentPlaylist = updated
        await cacheCoordinator.set(value: updated, for: Self.cacheKey, lifespan: Self.cacheLifespan)
        broadcast(updated)
    }

    /// Single background fetch loop shared by all observers.
    ///
    /// Important: This method intentionally does NOT broadcast empty playlists when we already
    /// have valid data. This prevents transient network errors from clearing the UI. The fetcher
    /// returns `.empty` on any error (network timeout, server error, etc.), so without this
    /// protection, a temporary network issue would replace good cached data with nothing.
    private func startFetching() async {
        while !Task.isCancelled {
            let playlist = await fetcher.fetchPlaylist()

            let accepted = await ingest(playlist)
            if !accepted {
                Log(.warning, category: .network, "Ignoring empty playlist from fetch - keeping existing data with \(currentPlaylist.entries.count) entries")
            }

            guard !Task.isCancelled else { break }

            try? await Task.sleep(for: .seconds(interval))
        }
    }

    /// Cache and broadcast a freshly fetched playlist when it represents real data.
    ///
    /// Empty playlists are ignored when valid data already exists — the fetcher returns
    /// `.empty` on any error, and replacing valid data with empty would clear the UI.
    /// The broadcast gate compares content (#266), not identifiers, so metadata-enriched
    /// re-fetches with the same IDs do reach observers.
    ///
    /// - Returns: `true` when the playlist was cached, `false` when ignored as an empty
    ///   replacement for valid data. Callers may log additional context either way.
    private func ingest(_ playlist: Playlist) async -> Bool {
        // Gate on content emptiness, not `== .empty`: a successful fetch now always
        // carries an `onAir` value, so a content-empty payload no longer equals the
        // `.empty` sentinel and would otherwise slip past this guard and clear the
        // visible feed. See `Playlist.isContentEmpty`.
        guard !playlist.isContentEmpty || currentPlaylist.isContentEmpty else { return false }

        await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

        // Surface cancellation that occurred during the cache write so the surrounding
        // loop can exit before broadcasting stale work.
        guard !Task.isCancelled else { return true }

        if playlist != currentPlaylist {
            currentPlaylist = playlist
            broadcast(playlist)
        }

        return true
    }
}
