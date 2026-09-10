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

    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var fetchTask: Task<Void, Never>?
    private let cacheCoordinator: CacheCoordinator
    private static let cacheLifespan: TimeInterval = 15 * 60 // 15 minutes

    /// The cache key this service reads and writes. A single constant since
    /// the v1 path was removed (#262) — the two versions persisted
    /// `chronOrderID` at incompatible scales and could never share an entry.
    private var cacheKey: String { PlaylistCacheKey.playlist }

    // MARK: - Live updates (SSE)

    /// Poll cadence used only as a reconciliation backstop when SSE live
    /// updates are actually wired in (the caller opted in). Defensible only
    /// because inserts/updates already arrive over the push channel while
    /// foregrounded — see `setForegrounded(_:)`. Keying this off the caller's
    /// opt-in rather than applying it unconditionally matters:
    /// `WXYC/WatchXYC/PlaylistPage.swift` and `PlayerPage.swift` consume
    /// `updates()` as their only refresh path and never opt into SSE, so an
    /// unconditional 300 s would silently make the watch up to 5 minutes
    /// stale.
    private static let liveUpdatesReconciliationInterval: TimeInterval = 300

    /// Poll cadence when no push channel backs freshness — i.e. when the
    /// caller didn't opt into live updates (watchOS/tvOS/widgets/intents).
    private static let pollOnlyInterval: TimeInterval = 30

    /// The installed `live-fs-topic` SSE source, or `nil` when the caller never
    /// opted in. This is what
    /// `setForegrounded`/`ensureLiveUpdatesRunning`/`consumeLiveEvents` read.
    ///
    /// A `let`: it used to be re-derived on every version change, since v1 had
    /// no push channel and a switch had to install or tear down the source to
    /// match. With one API version (#262) the caller's opt-in is fixed at
    /// `init` and nothing can change it afterwards.
    /// See WXYC/wxyc-ios-64#269, #749.
    private let activeLiveEventSource: (any LiveFsEventSource)?

    /// The running SSE consume loop, or `nil` when backgrounded / not enabled.
    private var liveUpdatesTask: Task<Void, Never>?

    /// Identifies the current consume loop, so a loop that exits after being
    /// superseded can tell whether `liveUpdatesTask` still refers to it before
    /// clearing it. See the `defer` in `consumeLiveEvents(generation:)`. Same
    /// bump-capture-compare idiom as `AudioPlayerController`'s
    /// `sessionActivationGeneration`; a third site should hoist a shared
    /// helper into Core rather than fork the pattern again.
    private var liveUpdatesGeneration = 0

    /// The app's current foreground state. The SSE subscription is opened only
    /// while foregrounded and torn down on background — a long-lived socket in
    /// the background is wasteful and the OS reclaims it anyway.
    private var isForegrounded = false

    /// Reconnect backoff bounds for the SSE consume loop.
    private static let minReconnectBackoff: Duration = .seconds(1)
    private static let maxReconnectBackoff: Duration = .seconds(30)

    /// Collection of continuations for broadcasting to multiple observers
    private var continuations: [UUID: AsyncStream<Playlist>.Continuation] = [:]
    
    /// Whether ``currentPlaylist`` is yet a trustworthy answer to "do we have real data?".
    ///
    /// The empty-fetch guard in ``ingest(_:)`` and the first-yield decision in
    /// ``addContinuation(_:for:)`` both read `currentPlaylist` to make that judgement, and
    /// an unloaded `currentPlaylist` is indistinguishable from a genuinely empty one. This
    /// is the bit that tells them apart.
    private enum CacheBaseline {
        /// No cache load has started. `init` leaves the service here — the load begins on
        /// first use instead (WXYC/wxyc-ios-64#964), so constructing a `PlaylistService`
        /// starts no work.
        case unloaded

        /// A load is in flight. The task is held so concurrent first-callers share one
        /// load rather than each starting their own, and so a caller that supersedes the
        /// load can cancel it instead of merely dropping its handle.
        case loading(Task<Void, Never>)

        /// `currentPlaylist` is authoritative. Reached by a finished load.
        case established
    }

    /// The cache-load state machine. One field rather than a `Task?` plus a `Bool`,
    /// because the pair could encode "settled without ever loading" only by convention,
    /// and the fast path that reads it is a correctness gate rather than an optimization:
    /// once the baseline is ``CacheBaseline/established``, a load that started anyway
    /// would publish stale rows over a deliberate clear. Making that a `case` puts it
    /// beyond the reach of a future reader deleting a redundant-looking `if`.
    ///
    /// Actor-isolated, unlike the `nonisolated(unsafe)` task field it replaces: that
    /// annotation existed only because `init` is nonisolated in an actor and had to write
    /// the field from there. With the write moved onto the actor, the check-then-set in
    /// ``waitForCacheLoad()`` is race-free by construction.
    private var cacheBaseline: CacheBaseline = .unloaded

    /// Designated initializer. Takes the live-updates source directly so tests
    /// can inject a scripted `MockLiveFsEventSource`; app code uses the
    /// `liveUpdatesEnabled` convenience initializer below instead.
    ///
    /// - Parameters:
    ///   - fetcher: Fetcher to use. When `nil` (the default), a live-network
    ///     `PlaylistFetcher` is built.
    ///   - interval: A test-supplied poll interval override. When `nil` (the
    ///     default), the interval is derived from the resolved wiring — see
    ///     ``liveUpdatesReconciliationInterval`` / ``pollOnlyInterval``.
    init(
        fetcher: PlaylistFetcherProtocol? = nil,
        interval: TimeInterval? = nil,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist,
        liveEventSource: (any LiveFsEventSource)?
    ) {
        self.fetcher = fetcher ?? PlaylistFetcher()
        self.cacheCoordinator = cacheCoordinator

        let liveUpdatesActive = liveEventSource != nil
        self.activeLiveEventSource = liveEventSource
        self.interval = interval ?? (
            liveUpdatesActive ? Self.liveUpdatesReconciliationInterval : Self.pollOnlyInterval
        )

        // Deliberately no cache-load Task here: an actor's `init` should start no work
        // (WXYC/wxyc-ios-64#964). The load begins on first use instead — see
        // `waitForCacheLoad()`.
        //
        // The compiler holds this, not just this comment: `cacheBaseline` is
        // actor-isolated, so starting the load from here is "cannot access property
        // 'cacheBaseline' here in nonisolated initializer" rather than a silent
        // regression. That is what the old `nonisolated(unsafe)` on the task field was
        // buying — the ability to write it from `init` — and dropping it is what closes
        // the door.
        //
        // That makes construction start nothing, not that it costs nothing: building the
        // derived fetcher still constructs a data source. What this buys is that a
        // `PlaylistService` nobody uses — the `PlaylistServiceEnvironment` fallback
        // SwiftUI builds on every correctly-injecting launch — now sits inert rather
        // than reading the disk cache and decoding a `Playlist`.
    }

    /// Creates a `PlaylistService`.
    ///
    /// - Parameters:
    ///   - liveUpdatesEnabled: When `true`, the caller opts into a
    ///     `live-fs-topic` SSE subscription while foregrounded (see
    ///     ``setForegrounded(_:)``). Defaults to `false`, preserving the
    ///     poll-only behavior for watchOS/tvOS/widgets. Only the iOS app
    ///     enables it. The poll interval follows the same opt-in — see
    ///     ``liveUpdatesReconciliationInterval`` / ``pollOnlyInterval`` — so
    ///     callers no longer pass it explicitly to get the long
    ///     reconciliation cadence.
    public init(
        fetcher: PlaylistFetcherProtocol? = nil,
        interval: TimeInterval? = nil,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist,
        liveUpdatesEnabled: Bool = false
    ) {
        self.init(
            fetcher: fetcher,
            interval: interval,
            cacheCoordinator: cacheCoordinator,
            liveEventSource: liveUpdatesEnabled ? FlowsheetLiveEventSource() : nil
        )
    }

    /// Starts the cache load if it has not started, without waiting for it.
    ///
    /// For callers that are about to do something slow and unrelated — a network fetch —
    /// and want the disk read overlapping it rather than queued behind it. The awaiting
    /// form is ``waitForCacheLoad()``; both go through the same memoized task, so a kick
    /// followed by a wait loads exactly once.
    private func startCacheLoadIfNeeded() {
        guard case .unloaded = cacheBaseline else { return }
        cacheBaseline = .loading(Task { await self.loadCachedPlaylist() })
    }

    /// Load cached playlist if available and not expired.
    /// Started lazily on first use — see ``waitForCacheLoad()``.
    private func loadCachedPlaylist() async {
        defer { cacheBaseline = .established }

        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: cacheKey)

            // A caller that cleared `currentPlaylist` while this read was in flight is
            // relying on the clear standing: publishing rows fetched before it would put
            // stale content on screen over a deliberate reset. Cancellation is how such a
            // caller says so, and this is where it is observed — the cache read itself is
            // not cancellable, so cancelling alone would stop nothing.
            //
            // Checked after the read rather than before it. A read that runs anyway costs
            // one wasted disk hit on a path that only a version switch reaches; moving
            // the check earlier would buy that back and lose the guarantee, since the
            // cancellation usually lands while the read is already in flight.
            guard !Task.isCancelled else {
                Log(.info, category: .network, "Discarding a cached playlist loaded across an API version switch")
                return
            }

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
            let _: Playlist = try await cacheCoordinator.value(for: cacheKey)
            return false
        } catch {
            return true
        }
    }
    
    /// Waits for the initial cache load to complete, starting it first if this is the
    /// first caller to need it.
    ///
    /// The single memoized entry point to the load: it starts on first use rather than at
    /// initialization, and concurrent first-callers share one load. Race-free by
    /// construction — the read and the write below happen on the actor with no suspension
    /// between them, so two callers landing on the same turn cannot both start one.
    public func waitForCacheLoad() async {
        switch cacheBaseline {
        case .established:
            return
        case .loading(let task):
            await task.value
        case .unloaded:
            let task = Task { await self.loadCachedPlaylist() }
            cacheBaseline = .loading(task)
            await task.value
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

    /// Cumulative count of fetch failures observed by the currently-active
    /// fetcher, for debug-panel observability (WXYC/wxyc-ios-64#267).
    ///
    /// Every thrown error (network timeout, server error, decode failure) is
    /// swallowed by `PlaylistFetcherProtocol.fetchPlaylist()` into an empty
    /// playlist with no signal in its return value, and the broadcast-empty
    /// guard in `ingest(_:)` — correctly — keeps the last good playlist on
    /// screen through a transient failure. That combination means a sustained
    /// failure (decoder drift, a bad deploy) looks identical from the UI to a
    /// quiet night with nothing playing. This counter is the missing signal:
    /// it does not change fetch or broadcast behavior, only makes failures
    /// observable.
    ///
    /// Delegates to `fetcher.fetchErrorCount` rather than keeping an
    /// independent tally, so the count is scoped to the fetcher instance that
    /// produced it.
    public func fetchErrorCount() -> Int {
        fetcher.fetchErrorCount
    }
    
    /// Fetch playlist and cache it, always fetching fresh data (ignores cache).
    /// Used for background refresh to ensure we always get the latest data.
    ///
    /// Important: This method does NOT replace valid data with empty playlists.
    /// If the fetch fails (returning `.empty`), existing cached data is preserved.
    public func fetchAndCachePlaylist() async -> Playlist {
        // Kick the cache load without waiting, so the disk read overlaps the network fetch
        // below rather than queueing behind it at `ingest(_:)`'s barrier. This is the
        // background-refresh path, whose BGAppRefresh budget is shared with a Spotlight
        // batch — `init` used to buy this overlap for free by starting the load eagerly.
        // A no-op once the baseline is settled, so a deliberate `.established` is never
        // undone by a redundant reload.
        startCacheLoadIfNeeded()

        let playlist = await fetcher.fetchPlaylist()

        if await ingest(playlist) {
            // "Accepted", not "cached": `ingest(_:)` takes a content-empty playlist into
            // the in-memory feed without persisting it. Its own log line above says which.
            Log(.info, category: .network, "Accepted fetched playlist with \(playlist.entries.count) entries \(playlist.entries)")
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
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: cacheKey)
            Log(.info, category: .network, "Returning cached playlist with \(cachedPlaylist.entries.count) entries")
            return cachedPlaylist
        } catch {
            // Cache miss or expired - fetch from network
            Log(.info, category: .network, "Cache miss, fetching fresh playlist")
            let playlist = await fetcher.fetchPlaylist()

            // Cache the result for future use
            await cacheCoordinator.set(value: playlist, for: cacheKey, lifespan: Self.cacheLifespan)

            Log(.info, category: .network, "Fetched and cached new playlist with \(playlist.entries.count) entries")
            return playlist
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
        let pollInterval: TimeInterval
        let liveUpdatesActive: Bool

        /// Whether a live-updates consume loop is currently held. Distinct
        /// from ``liveUpdatesActive``, which reports whether a source is
        /// *wired in*: this reports whether a loop is actually running against
        /// it. `ensureLiveUpdatesRunning()` assigns `liveUpdatesTask`
        /// synchronously, before the task body runs, so observing this field
        /// needs no timing tolerance at all.
        let hasLiveUpdatesTask: Bool

        /// Whether the cached-playlist load has been started (or settled). `false` means
        /// the service has done no cache work at all — the state `init` must leave it in
        /// (WXYC/wxyc-ios-64#964).
        ///
        /// Reported for the same reason as ``hasLiveUpdatesTask``: the baseline is
        /// assigned synchronously, before the load's task body runs, so a test asserting
        /// that construction started nothing needs no timing tolerance. Sleeping for "long
        /// enough that an eager load would have finished" instead would pass on a loaded
        /// machine whether or not the regression was present.
        let cacheLoadStarted: Bool
    }

    /// Returns the service's currently-resolved wiring — the poll interval,
    /// whether an SSE subscription is wired in (the caller opted in), and
    /// whether a consume loop is currently held.
    func wiringSnapshot() -> WiringSnapshot {
        WiringSnapshot(
            pollInterval: interval,
            liveUpdatesActive: activeLiveEventSource != nil,
            hasLiveUpdatesTask: liveUpdatesTask != nil,
            cacheLoadStarted: {
                if case .unloaded = cacheBaseline { return false }
                return true
            }()
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
    /// `ensureLiveUpdatesRunning()` is reachable only from here, a wrong value
    /// is never re-checked and live updates stay down for the session. The iOS caller therefore delivers
    /// through an ordered relay (`Core.LatestValueRelay`); a new caller that
    /// reaches this method directly is unprotected.
    ///
    /// Tracks `isForegrounded` unconditionally — even when the caller never
    /// opted into live updates. `ensureLiveUpdatesRunning()` already guards on
    /// `activeLiveEventSource` being non-nil, and cancelling a nil task is
    /// harmless, so no outer guard is needed here. While foregrounded the service applies
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

        // Start the poll loop before waiting on anything, so the first network fetch of
        // the session overlaps the disk read instead of queueing behind it. Safe because
        // `ingest(_:)` awaits the same barrier: a fetch that lands first still can't
        // broadcast ahead of the cached baseline.
        ensureFetchTaskRunning()

        // Wait for the initial cache load before deciding whether to yield, starting it
        // if this is the first subscriber ever. This prevents a race where observers
        // subscribe before the cache is loaded and see an empty playlist until the
        // network fetch completes.
        if case .established = cacheBaseline {
            // The load already ran, and broadcast, before this subscriber existed, so its
            // baseline has to be handed over explicitly.
            if !currentPlaylist.isContentEmpty {
                continuation.yield(currentPlaylist)
            }
        } else {
            // No yield on this branch: awaiting the load *is* the delivery.
            // `loadCachedPlaylist()` broadcasts to every registered continuation and this
            // one is registered above, so yielding here as well would hand the first
            // subscriber the same playlist twice. The two are ordered, not racing —
            // `loadCachedPlaylist` broadcasts and settles the baseline with no suspension
            // between them, so observing a non-`.established` baseline here proves the
            // broadcast has not happened yet and that this continuation will be registered
            // in time to receive it.
            //
            // Deferring the load (WXYC/wxyc-ios-64#964) is what made the duplicate matter:
            // the first subscriber now always arrives before the load rather than after
            // it, so what used to be a rare race would be every launch.
            // `WidgetStateService` would spend a reload against the widget refresh budget
            // on it, and `NowPlayingService` would re-fetch artwork and re-emit a
            // now-playing item.
            await waitForCacheLoad()
        }
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
            let incoming = playcut.retainingOrderingKey(of: playcuts[index])
            guard playcuts[index] != incoming else { return }
            playcuts[index] = incoming
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
        await cacheCoordinator.set(value: updated, for: cacheKey, lifespan: Self.cacheLifespan)
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
    /// A content-empty playlist is never written to the cache, even in the one case where
    /// it *is* accepted in memory — see the write below.
    ///
    /// - Returns: `true` when the playlist was accepted, `false` when ignored as an empty
    ///   replacement for valid data. Callers may log additional context either way.
    private func ingest(_ playlist: Playlist) async -> Bool {
        // The guard below reads `currentPlaylist`, so the cache load has to have
        // happened first — an unloaded `currentPlaylist` is `.empty`, which makes the
        // guard mistake a failed fetch for the session's first real data.
        //
        // Most callers already cleared this barrier: `startFetching()` runs only from
        // `ensureFetchTaskRunning()` behind `addContinuation(_:for:)`, and
        // `applyLiveEvent(.refetch)` runs inside `consumeLiveEvents`, which awaits it
        // at the top. The uncovered path is a bare `fetchAndCachePlaylist()` in a
        // process where nothing ever subscribed — `BackgroundRefreshController`'s
        // `.backgroundTask(.appRefresh(_:))` on a background launch, which builds no
        // views. Awaiting here rather than in that one caller keeps the precondition
        // attached to the code that depends on it; for everyone else the baseline is
        // already settled and this is a no-op that never suspends.
        //
        // What the barrier settles is *when* `currentPlaylist` can be trusted, not
        // *that* it holds content. On that same background-refresh path the cached entry
        // has normally outlived the 15-minute `cacheLifespan` — BGAppRefresh fires far
        // less often — so the load finds nothing, logs, and settles the baseline with
        // `currentPlaylist` still `.empty`. Keeping the cache safe in that case is the
        // write's job below, not the barrier's.
        await waitForCacheLoad()

        // Gate on content emptiness, not `== .empty`: a successful fetch now always
        // carries an `onAir` value, so a content-empty payload no longer equals the
        // `.empty` sentinel and would otherwise slip past this guard and clear the
        // visible feed. See `Playlist.isContentEmpty`.
        guard !playlist.isContentEmpty || currentPlaylist.isContentEmpty else { return false }

        // A content-empty playlist reaching this line has been accepted in memory — the
        // guard above just did — but it is never persisted.
        //
        // `PlaylistFetcherProtocol.fetchPlaylist()` folds every failure (timeout, 5xx,
        // decode drift) into a content-empty return, so the payload itself carries no
        // evidence of which of the two it is, and the asymmetry decides it: an *absent*
        // entry sends `fetchPlaylist()` — the widget's read — to the network, while a
        // freshly written empty one is served to it as a hit for the full
        // `cacheLifespan`. Persisting it bets 15 minutes of a blank widget against
        // saving one request during a genuinely off-air stretch, which a station running
        // a continuous flowsheet essentially never has. When the station really is off
        // air the in-memory path is untouched: the payload is still broadcast to every
        // observer below, so the feed and the `onAir` banner update as they always did —
        // only the widget's copy is left to be re-fetched rather than read.
        //
        // Deliberately not conditioned on what the cache load found. `CacheCoordinator`
        // reports an expired entry as `noCachedResult` *and removes it*, so "expired"
        // degrades to "absent" by the next refresh; a rule that distinguished them would
        // cover the first background refresh after expiry and fail open on the second.
        if playlist.isContentEmpty {
            Log(.info, category: .network, "Accepting a content-empty playlist in memory but not caching it - a failed fetch is indistinguishable from a genuinely empty one")
        } else {
            await cacheCoordinator.set(value: playlist, for: cacheKey, lifespan: Self.cacheLifespan)
        }

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

private extension Playcut {
    /// This row as `upsertPlaycut` should store it: every field incoming, but
    /// keeping `stored`'s packed ordering key when this row's own derivation
    /// fell back to the bare id.
    ///
    /// `FlowsheetEntry.show_id` is optional, so an SSE `update` payload that
    /// omits it — a Backend projection regression, a partial deploy — decodes
    /// cleanly and re-derives the key as the bare-id fallback
    /// (`chronOrderID == id`; see
    /// `FlowsheetConverter.chronOrderID(showID:playOrder:id:)`). Replacing the
    /// stored row wholesale would sink the on-air song to the bottom of the
    /// feed mid-play. The stored key came from a payload that DID carry the
    /// composite, so it stays authoritative; the reverse direction (stored
    /// bare, incoming packed) is an upgrade and is taken as-is.
    func retainingOrderingKey(of stored: Playcut) -> Playcut {
        guard chronOrderID == id, stored.chronOrderID != stored.id else { return self }
        return Playcut(
            id: id,
            hour: hour,
            chronOrderID: stored.chronOrderID,
            timeCreated: timeCreated,
            songTitle: songTitle,
            labelName: labelName,
            artistName: artistName,
            releaseTitle: releaseTitle,
            rotation: rotation,
            artworkURL: artworkURL,
            discogsURL: discogsURL,
            releaseYear: releaseYear,
            spotifyURL: spotifyURL,
            appleMusicURL: appleMusicURL,
            youtubeMusicURL: youtubeMusicURL,
            bandcampURL: bandcampURL,
            soundcloudURL: soundcloudURL,
            artistBio: artistBio,
            artistWikipediaURL: artistWikipediaURL,
            genres: genres,
            styles: styles,
            artistId: artistId,
            upcomingShow: upcomingShow,
            criticReviews: criticReviews,
            metadataStatus: metadataStatus,
            discogsUnavailable: discogsUnavailable,
            discogsUnavailableNote: discogsUnavailableNote
        )
    }
}
