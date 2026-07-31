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
    private static let cacheKey = PlaylistCacheKey.playlist
    private static let cacheLifespan: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - Live updates (SSE)

    /// The `live-fs-topic` SSE source, or `nil` when live updates aren't enabled
    /// for this instance (the default — watchOS/tvOS/widgets stay poll-only).
    /// When present, `PlaylistService` opens a subscription while foregrounded
    /// and applies `insert`/`update` events between reconciliation polls. See
    /// WXYC/wxyc-ios-64#269.
    private let liveEventSource: (any LiveFsEventSource)?

    /// The running SSE consume loop, or `nil` when backgrounded / not enabled.
    private var liveUpdatesTask: Task<Void, Never>?

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
    init(
        fetcher: PlaylistFetcherProtocol = PlaylistFetcher(),
        interval: TimeInterval = 30,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist,
        liveEventSource: (any LiveFsEventSource)?
    ) {
        self.fetcher = fetcher
        self.interval = interval
        self.cacheCoordinator = cacheCoordinator
        self.liveEventSource = liveEventSource

        // Start loading cached playlist immediately.
        // Observers will await this task before receiving their first value.
        cacheLoadTask = Task { [self] in
            await self.loadCachedPlaylist()
        }
    }

    /// Creates a `PlaylistService`.
    ///
    /// - Parameter liveUpdatesEnabled: When `true`, the service opens a
    ///   `live-fs-topic` SSE subscription while foregrounded (see
    ///   ``setForegrounded(_:)``) and applies `insert`/`update` events between
    ///   reconciliation polls, so a caller should pair it with a long `interval`
    ///   (e.g. 300 s). Defaults to `false`, preserving the poll-only behavior
    ///   for watchOS/tvOS/widgets. Only the iOS app enables it.
    public init(
        fetcher: PlaylistFetcherProtocol = PlaylistFetcher(),
        interval: TimeInterval = 30,
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
    ///
    /// - Parameter version: The API version to switch to.
    public func switchAPIVersion(to version: PlaylistAPIVersion) async {
        Log(.info, category: .network, "Switching playlist API to \(version.rawValue)")
            
        // Cancel any existing fetch task
        cancelFetchTask()
            
        // Create new fetcher with the specified version
        fetcher = PlaylistFetcher(apiVersion: version)
                
        // Clear current playlist to show loading state
        currentPlaylist = .empty
        broadcast(.empty)
            
        // Fetch fresh data with new API version (this will overwrite the cache)
        _ = await fetchAndCachePlaylist()
                
        // Restart fetch loop if we have observers
        if !continuations.isEmpty {
            ensureFetchTaskRunning()
        }
    }

    /// Opens or closes the `live-fs-topic` SSE subscription in response to the
    /// app's foreground state.
    ///
    /// Called from the iOS scene-phase handler: `true` on `.active`, `false` on
    /// `.inactive`/`.background`. A no-op when live updates aren't enabled for
    /// this instance (watchOS/tvOS/widgets), so those platforms keep their
    /// poll-only behavior untouched. While foregrounded the service applies
    /// `insert`/`update` events as they arrive; the periodic `interval` poll
    /// stays running underneath as a reconciliation backstop.
    public func setForegrounded(_ foregrounded: Bool) {
        guard liveEventSource != nil else { return }
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
        guard liveEventSource != nil, isForegrounded, liveUpdatesTask == nil else { return }
        liveUpdatesTask = Task { await self.consumeLiveEvents() }
    }

    /// Consumes the SSE stream while foregrounded, reconnecting with exponential
    /// backoff (capped at ``maxReconnectBackoff``) when the connection drops.
    ///
    /// Each ``LiveFsEventSource/connect()`` models one connection attempt whose
    /// stream finishes when the socket ends; this loop reopens it. The backoff
    /// resets to ``minReconnectBackoff`` as soon as a connection delivers an
    /// event, and grows only when an attempt produced nothing (a hard failure,
    /// distinct from a healthy connection that simply closed).
    private func consumeLiveEvents() async {
        guard let source = liveEventSource else { return }

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

    /// Inserts or replaces a playcut by `id`, then caches and broadcasts.
    ///
    /// The `playcuts` array order is irrelevant — `Playlist.entries` re-sorts by
    /// `chronOrderID` — so an insert simply appends. An identical replay is a
    /// no-op so it doesn't churn observers or the cache.
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
