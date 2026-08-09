//
//  Singletonia.swift
//  WXYC
//
//  Observable singleton holding shared app state.
//
//  Created by Jake Bromberg on 01/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AppServices
import Artwork
import Caching
import Concerts
import Core
import DebugPanel
import LikedSongs
import Logger
import MusicShareKit
import Observation
import Playback
import Playlist
import SwiftUI
import Wallpaper
import WXYCIntents

/// Shared app state for cross-scene access (main UI and CarPlay)
@MainActor
@Observable
final class Singletonia {
    static let shared = Singletonia()

    let nowPlayingInfoCenterManager: NowPlayingInfoCenterManager
    let handoffActivityManager: HandoffActivityManager
    // iOS is the only platform that opts into the `live-fs-topic` SSE stream:
    // track inserts and metadata updates arrive as push events while
    // foregrounded (see `setForegrounded(_:)`). The 300 s reconciliation
    // cadence is no longer hardcoded here — `PlaylistService` derives it from
    // the resolved `PlaylistAPIVersion` plus this opt-in (300 s only when the
    // version actually supports live updates; 30 s otherwise, e.g. under v1),
    // so a runtime version switch can never leave the poll interval or the
    // SSE subscription stale. See WXYC/wxyc-ios-64#269, #749.
    let playlistService = PlaylistService(liveUpdatesEnabled: true)
    let artworkService = MultisourceArtworkService()
    let artworkLoader: ArtworkLoader
    let widgetStateService: WidgetStateService
    let reviewRequestService = ReviewRequestService(minimumVersionForReview: "1.0")
    let spotlightDonationService = SpotlightDonationService(
        storage: UserDefaults.wxyc,
        indexer: CoreSpotlightEntityIndexer<PlaycutEntity>(indexName: SpotlightIndexName.playcuts)
    )

    /// The always-on concert Spotlight donor (OT-C8, #654) — the concert analogue
    /// of ``spotlightDonationService``. Bound to the same production storage
    /// (`UserDefaults.wxyc`, holding the reconcile id -> status snapshot) and the
    /// real `wxyc.concerts` index (`CoreSpotlightEntityIndexer<ConcertEntity>`).
    /// Driven from ``startConcertSpotlightDonation()`` on every On Tour window
    /// refresh.
    let concertSpotlightDonationService = ConcertSpotlightDonationService(
        storage: UserDefaults.wxyc,
        indexer: CoreSpotlightEntityIndexer<ConcertEntity>(indexName: SpotlightIndexName.concerts)
    )

    /// Owns the launch-empty-skip + no-op-refresh dedup that keeps the concert
    /// donation loop within the background-refresh budget (OT-C8). Its state is
    /// the reason the loop is one shared instance, not one per window emission.
    let concertSpotlightWindowObserver = ConcertSpotlightWindowObserver()

    /// The production On Tour window, held here (not per-scene) so
    /// ``startConcertSpotlightDonation()`` can observe it independently of whether
    /// the user ever opens the On Tour tab. `RootTabView` hands this same instance
    /// to `OnTourTabView` (falling back to it only when there's no `-marketing`
    /// fixture model), so opening the tab shows the already-loaded window rather
    /// than triggering a second fetch — `OnTourModel`'s single-flight `load()`
    /// coalesces the launch load with the tab's `.task` load.
    let onTourModel = OnTourModel(fetcher: ConcertsFetcher(tokenProvider: MusicShareKit.tokenProvider))

    let playcutHistoryStore = PlaycutHistoryStore()

    /// On-device liked songs (#492). A durable file store, not a cache — likes
    /// are user-curated canonical data with a never-evict contract (see
    /// docs/plans/492-liked-songs.md decision #6). `AppSupportFileStorage`
    /// (Core's `FileStorage` seam) needs no module qualification since
    /// `LikedSongs` and `Concerts` both consume the same Core definition
    /// (WXYC/wxyc-ios-64#557). Routed through `makeLikedStorage()` so a
    /// `-marketing` recording gets an in-memory store instead (see the
    /// `-marketing` section below).
    let likedSongsStore = LikedSongsStore(storage: Singletonia.makeLikedStorage())

    /// Concerts the listener dismissed ("Not interested") from the On Tour For You
    /// shelf. Same durable-file rationale as the likes store — user curation, not a
    /// re-derivable cache — so it goes through the same Core `FileStorage` seam.
    /// Routed through `makeDismissedConcertsStorage()` so a `-marketing` recording
    /// gets an in-memory store instead (see the `-marketing` section below) — the
    /// same treatment `likedSongsStore` gets, so a recording can never touch (or
    /// need to reset) a real `dismissed-concerts.json`.
    let dismissedConcertsStore = DismissedConcertsStore(storage: Singletonia.makeDismissedConcertsStorage())

    /// Feature-flag source for the On Tour For You shelf's similar-tier noise cap
    /// (#493), read through the `FeatureFlagProvider` protocol so the shelf never
    /// links PostHog directly and can be exercised with a mock. PostHog-backed in
    /// production; the shelf falls back to a local default when it is offline.
    let featureFlagProvider: any FeatureFlagProvider = PostHogFeatureFlagProvider.shared

    let themeConfiguration = ThemeConfiguration()
    let themePickerState = ThemePickerState()

    /// Show/retire state for the Box Office ticket discovery CTA. Held here — not
    /// per scene — because two sibling scenes share it: `PlaylistView` reads
    /// `shouldShow` and records the dismiss, while `PlaycutDetailView` records the
    /// real-ticket view that retires it. One instance keeps both on the same keys.
    let ticketFeatureCTAPersistence = TicketFeatureCTAPersistence()

    /// A shared On Tour show link that has arrived but not yet been opened (#537).
    /// Set by ``startObservingConcertOpen()`` when a `wxyc.org/shows/<id>` (or
    /// `wxyc://concert/<id>`) link posts a `ConcertOpenMessage`; `RootTabView`
    /// flips to the On Tour tab in response and `OnTourTabView` runs the
    /// resolution ladder, then clears it via ``consumePendingConcertLink()``.
    private(set) var pendingConcertLink: PendingConcertLink?

    /// A shared or Spotlight-donated playcut link that has arrived but not yet
    /// been opened (#434). Set by ``startObservingPlaycutOpen()`` when a
    /// Spotlight/Siri tap (`OpenPlaycut`) or a `wxyc://playcut/<id>` link posts
    /// a `PlaycutOpenMessage`; `RootTabView` flips to the Now Playing tab in
    /// response and `PlaylistView` scrolls its timeline to the matching row,
    /// then clears it via ``consumePendingPlaycutLink()``.
    private(set) var pendingPlaycutLink: PendingPlaycutLink?

    /// A venue request from an `OpenVenue` Siri/Spotlight intent that has
    /// arrived but not yet been opened (OT-C4). Set by
    /// ``startObservingVenueOpen()`` when `OpenVenue.perform()` posts a
    /// `VenueOpenMessage`; `RootTabView` flips to the On Tour tab in response
    /// and `OnTourTabView` narrows its venue filter to just this venue, then
    /// clears it via ``consumePendingVenueLink()``.
    private(set) var pendingVenueLink: PendingVenueLink?

    /// Marketing-driven tab route. Set only during a `-marketing` recording; nil
    /// in production. A small release-compiled optional, mirroring
    /// ``pendingConcertLink`` — `RootTabView` maps it to its private `Page`.
    private(set) var marketingRoute: MarketingRoute?

    /// Bumped to request `OnTourTabView` dismiss any presented concert detail,
    /// independent of ``marketingRoute``. Two `.onChange` handlers reacting to
    /// the same `marketingRoute` write have no SwiftUI-guaranteed relative order
    /// across sibling views, so `-marketing`'s "close the cover, then switch
    /// tabs" sequencing uses this separate signal — with an explicit gap before
    /// the route change — instead of relying on that unordered simultaneity.
    private(set) var marketingDismissOnTourDetailToken = 0

    /// Token for the app-lifetime `ConcertOpenMessage` observer. Held so the
    /// registration stays idempotent — one observer for the app's lifetime.
    @ObservationIgnored private var concertOpenObservation: (any NSObjectProtocol)?

    /// Token for the app-lifetime `PlaycutOpenMessage` observer. Held so the
    /// registration stays idempotent — one observer for the app's lifetime.
    @ObservationIgnored private var playcutOpenObservation: (any NSObjectProtocol)?

    /// Token for the app-lifetime `VenueOpenMessage` observer. Held so the
    /// registration stays idempotent — one observer for the app's lifetime.
    @ObservationIgnored private var venueOpenObservation: (any NSObjectProtocol)?

    #if DEBUG
    /// Fixture-backed On Tour model for the `-marketing` recording, built once in
    /// `init` when `-marketing` is present. Nil otherwise.
    private var _marketingOnTourModel: OnTourModel?

    /// The `-marketing` recording's concert-detail target id — the On Tour
    /// fixture entry the storyboard opens (the one carrying `artistBio`). Set
    /// once in `init` from the same fixture `_marketingOnTourModel` is built
    /// from, so a future edit to that fixture (e.g. reordering or renumbering
    /// its entries) can't silently desync from a hardcoded literal id.
    private var _marketingHeroConcertID: Int?

    /// The For You seed debug knobs `-marketing` overrode in `init`, captured so
    /// a completed recording can restore them instead of leaving
    /// `stationCapOverride` — a `UserDefaults`-persisted knob — stuck forcing the
    /// station tier on for later non-`-marketing` launches on the same
    /// simulator. Nil once restored (or when nothing was overridden).
    private var marketingForYouSeedOverrideBackup: (seedLovedEnabled: Bool, stationCapOverride: Int)?
    #endif

    /// The `-marketing` On Tour model, or nil (production → live endpoint).
    /// Release always returns nil, so `RootTabView` needs no compile-time branch.
    var marketingOnTourModel: OnTourModel? {
        #if DEBUG
        _marketingOnTourModel
        #else
        nil
        #endif
    }

    /// The `-marketing` recording's concert-detail target id, or nil (production
    /// / no id resolved). Release always returns nil, mirroring
    /// ``marketingOnTourModel``, so `MarketingModeController` needs no
    /// compile-time branch.
    var marketingHeroConcertID: Int? {
        #if DEBUG
        _marketingHeroConcertID
        #else
        nil
        #endif
    }

    private var nowPlayingObservationTask: Task<Void, Never>?
    private var playbackStateTask: Task<Void, Never>?
    private var spotlightDonationTask: Task<Void, Never>?
    private var spotlightMetadataEnrichmentTask: Task<Void, Never>?
    private var concertSpotlightDonationTask: Task<Void, Never>?
    private var likedSongsHealingTask: Task<Void, Never>?

    /// Carries foreground transitions to `playlistService` in arrival order.
    /// Not a cancellable task like its neighbours above — see
    /// ``setScenePhase(_:)`` for why the ordering matters. Assigned in `init`
    /// rather than here because it captures `playlistService`.
    private let foregroundRelay: LatestValueRelay<Bool>

    #if DEBUG
    /// Dev-only: posts a lock-screen alert when the on-air artist has an upcoming
    /// show. Retained as a stored property (not a task-local) because the
    /// scheduler it owns is the `UNUserNotificationCenter` delegate, which the
    /// center holds *weakly* — a task-only capture would let it deallocate and
    /// silently stop presenting foreground banners.
    private let tourAlertCoordinator = TourAlertCoordinator(
        scheduler: UserNotificationTourAlertScheduler(),
        // Honor the "Mock ticket on first item" debug toggle so the same
        // affordance that fakes the Box Office ticket also drives a test
        // notification for each new now-playing artist. The playcut handed in is
        // always the on-air row, so — unlike the row-scoped
        // `DebugUpcomingShowResolver` — no `firstPlaycutID` check is needed.
        resolveUpcomingShow: { playcut in
            if let embedded = playcut.upcomingShow { return embedded }
            return OnTourShowsDebugState.shared.mockFirstItemEnabled
                ? DebugUpcomingShowResolver.mockShow(for: playcut)
                : nil
        }
    )
    private var tourNotificationTask: Task<Void, Never>?
    #endif

    private init() {
        // F3 (#427) / #751: register every AppIntents `@Dependency` type
        // WXYCIntents declares before anything else runs, so all of them are
        // in place before any intent/query the AppIntents runtime might
        // construct — including PlaycutEntityQuery's `@Dependency`-backed
        // production `entities(for:)` and iOS 27 reindex handlers — can run.
        // `@Dependency`'s wrappedValue traps if its type was never
        // registered, so this must precede every other line here.
        // `playcutHistoryStore` is already initialized at this point: stored
        // properties with default-value expressions (like this one, declared
        // above) are set before a class's custom `init()` body runs.
        //
        // Routed through `AppIntentsDependencies.registerForApp` (one call,
        // not five inline `AppDependencyManager.shared.add` calls) so the
        // NowPlayingWidget extension — which also links WXYCIntents but never
        // runs `Singletonia` — has the same bootstrap to register its own
        // widget-safe defaults against instead of silently omitting one; see
        // `NowPlayingWidgetBundle.init()` and #751.
        AppIntentsDependencies.registerForApp(
            playcutHistoryStore: self.playcutHistoryStore,
            // #445: the iOS 27 reindex handlers report `SpotlightReindexRequested`
            // through the same `@Dependency` seam as `playcutReindexer`.
            // #758 replaced the two per-kind indexer structs with one generic
            // `CoreSpotlightEntityIndexer<Entity>`; the registration shape here
            // is still #751's single call.
            playcutReindexer: CoreSpotlightEntityIndexer<PlaycutEntity>(
                indexName: SpotlightIndexName.playcuts
            ),
            // OT-F3 (#622): same registration shape as the playcut reindex
            // seam above, for `ConcertEntityQuery`'s reindex handlers.
            concertReindexer: CoreSpotlightEntityIndexer<ConcertEntity>(
                indexName: SpotlightIndexName.concerts
            ),
            // Authenticated the same way `AppIntentServices.concertsFetcher()`
            // (WXYC/iOS/Intents.swift) authenticates `ToursNearMe`.
            concertsFetching: ConcertsFetcher(tokenProvider: MusicShareKit.tokenProvider),
            analytics: StructuredPostHogAnalytics.shared
        )

        self.widgetStateService = WidgetStateService(
            playbackController: AudioPlayerController.shared,
            playlistService: playlistService
        )
        self.artworkLoader = ArtworkLoader(service: artworkService)

        // Draining starts here, before any scene phase can arrive, so there is
        // no window in which foreground state is accepted and then dropped.
        self.foregroundRelay = LatestValueRelay { [playlistService] isForegrounded in
            await playlistService.setForegrounded(isForegrounded)
        }

        let screenWidth = UIScreen.main.bounds.size.width
        nowPlayingInfoCenterManager = NowPlayingInfoCenterManager(
            boundsSize: CGSize(width: screenWidth, height: screenWidth)
        )
        handoffActivityManager = HandoffActivityManager()

        // Configure artwork cache to use half-screen-width scaled HEIF images.
        // Artwork is displayed at ~40% of screen width in playlist rows, so half-screen
        // resolution is more than sufficient. This cuts per-image memory from ~5.5MB to ~1.4MB.
        ArtworkCacheConfiguration.targetWidth = screenWidth * UIScreen.main.scale / 2

        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: artworkService
        )
        startNowPlayingObservation(nowPlayingService: nowPlayingService)
        startPlaybackStateObservation()
        startSpotlightDonation()
        startSpotlightMetadataEnrichmentReDonation()
        startConcertSpotlightDonation()
        startPlaycutHistory()
        startLikedSongsHealing()

        #if DEBUG
        // Dev-only: post a lock-screen alert when the on-air artist is on tour.
        startTourNotificationObservation()

        // UI-test isolation + determinism: `-uiTestResetForYou` clears the
        // dismissed-shows set AND forces the For You loved seed on (via the
        // runtime-only `seedForcedForTesting`, NOT the persisted toggle — so the
        // test can't leave the seed stuck on for later manual launches), so the
        // dismiss UI test sees a deterministic shelf regardless of any likes
        // persisted on the simulator.
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetForYou") {
            dismissedConcertsStore.resetState()
            // Neutralize the two *persisted* debug knobs a prior manual session may
            // have left on this simulator, so the forced loved seed is the shelf's
            // ONLY source. A leaked `stationCapOverride` (or `seedLovedEnabled`)
            // could otherwise compose a different shelf and let the dismiss test
            // pass on a station card while the loved-seed path is silently dead.
            let seedState = OnTourForYouSeedDebugState.shared
            seedState.seedLovedEnabled = false
            seedState.stationCapOverride = 0
            seedState.seedForcedForTesting = true
        }

        // `-marketing`: deterministic On Tour fixtures for the App Store preview
        // recording (no live `/concerts` traffic). Drives the "Heard on WXYC"
        // shelf's station-recommended tier — the only tier the canned fixtures can
        // feed, since they carry no `headliningArtistId` for the loved tier to
        // match — so the shelf renders header-only cards with no dependency on a
        // like.
        // `dismissedConcertsStore` is already routed to an in-memory backing
        // above under `-marketing`, so it starts empty on its own — no reset
        // needed, and (unlike a reset) nothing here can touch a real listener's
        // persisted "Not interested" list.
        if ProcessInfo.processInfo.arguments.contains("-marketing") {
            let seedState = OnTourForYouSeedDebugState.shared
            // `stationCapOverride`/`seedLovedEnabled` are UserDefaults-persisted
            // knobs (the debug panel's own affordance), so overriding them here
            // would otherwise stick past this recording and force the station
            // tier on for a later, non-`-marketing` launch on the same
            // simulator. Back up whatever was there before overriding, and
            // restore it once the recording finishes
            // (`restoreForYouSeedOverridesAfterMarketingRecording()`).
            marketingForYouSeedOverrideBackup = (seedState.seedLovedEnabled, seedState.stationCapOverride)
            seedState.seedLovedEnabled = false       // neutralize any leak from a prior manual session
            seedState.stationCapOverride = 5         // positive forces the station tier on
            // seedForcedForTesting is runtime-only and defaults false; leave it
            // false so no synthetic loved card is fabricated — the station tier
            // is the shelf's sole source for this recording.
            _marketingOnTourModel = OnTourModel(fetcher: PreviewConcertsFetcher())
            _marketingHeroConcertID = Concert.previewList.first?.id
        }
        #endif
    }

    private func startNowPlayingObservation(nowPlayingService: NowPlayingService) {
        nowPlayingObservationTask = Task { [weak self] in
            do {
                for try await item in nowPlayingService {
                    guard !Task.isCancelled else { break }
                    self?.nowPlayingInfoCenterManager.handleNowPlayingItem(item)
                }
            } catch {
                Log(.error, "NowPlaying observation error: \(error)")
            }
        }
    }

    /// Feeds the Spotlight content index on every playlist tick.
    ///
    /// Subscribes to `PlaylistService.updates()` (a multi-observer broadcast)
    /// rather than `NowPlayingService`. NowPlayingService would work too, but
    /// its iterator awaits `artworkService.fetchArtwork` for every yield —
    /// artwork the donation path never uses (Spotlight surfaces the URL, not
    /// the decoded image). Feeding from the playlist stream directly avoids
    /// a duplicate artwork-fetch pipeline on every tick.
    ///
    /// Per tick this observer runs BOTH donation paths: `donateCurrentPlaycut`
    /// for elevated-priority surfacing of the on-air track (deduped against
    /// the last donated playcut inside the actor so metadata re-broadcasts
    /// don't burn XPC), and `donateBatch` — the shared batch entry point that
    /// feeds both the `wxyc.playcuts` and `wxyc.artists` indexes from the same
    /// window — so a long-running foreground session (the case where the user
    /// never lets iOS run `BGAppRefresh`) still rebuilds the recent-50-row
    /// window and the derived artist rows. The playcut batch is
    /// watermark-idempotent so post-first-fetch ticks short-circuit at the
    /// `chronOrderID > watermark` filter.
    ///
    /// The service references are captured strongly here on purpose: the
    /// task's lifetime is bound to `Singletonia.shared` (a static let), so
    /// there is no cycle to break and `[weak self]` would be misleading.
    private func startSpotlightDonation() {
        spotlightDonationTask = Task { [spotlightDonationService, playlistService] in
            for await playlist in playlistService.updates() {
                guard !Task.isCancelled else { break }
                if let currentPlaycut = playlist.playcuts.first {
                    await spotlightDonationService.donateCurrentPlaycut(currentPlaycut)
                }
                await spotlightDonationService.donateBatch(from: playlist.playcuts)
            }
        }
    }

    #if DEBUG
    /// Dev-only: post a lock-screen alert when the on-air artist has an embedded
    /// upcoming show while the stream is playing (once per show per session).
    ///
    /// Subscribes to `playlistService.updates()` rather than `NowPlayingService`
    /// for the same reason `startSpotlightDonation()` does: the now-playing
    /// iterator awaits an artwork fetch per yield that this feature never uses.
    /// `isPlaying` is read synchronously off the main-actor player at each tick,
    /// so the alert only fires while the stream is actually playing.
    ///
    /// `tourAlertCoordinator` is captured strongly on purpose — its lifetime is
    /// bound to `Singletonia.shared` (a static let), so there is no cycle.
    private func startTourNotificationObservation() {
        tourNotificationTask = Task { [tourAlertCoordinator, playlistService] in
            for await playlist in playlistService.updates() {
                guard !Task.isCancelled else { break }
                await tourAlertCoordinator.ingest(
                    playcut: playlist.playcuts.first,
                    isPlaying: AudioPlayerController.shared.isPlaying
                )
            }
        }
    }
    #endif

    /// Re-donates a single playcut to Spotlight when its `metadata_status`
    /// lands in a terminal enriched state (issue #443).
    ///
    /// Separate task from `startSpotlightDonation()` because it subscribes to
    /// a different `PlaylistService` stream (`terminalMetadataTransitions()`,
    /// not `updates()`) with its own per-subscriber diff state. Gating on
    /// "was this row donated before" happens inside
    /// `SpotlightDonationService.handleMetadataEnrichment(for:)`, so this
    /// task only has to forward transitions.
    ///
    /// The service references are captured strongly here on purpose, same
    /// rationale as `startSpotlightDonation()`: the task's lifetime is bound
    /// to `Singletonia.shared` (a static let), so there is no cycle to break.
    private func startSpotlightMetadataEnrichmentReDonation() {
        spotlightMetadataEnrichmentTask = Task { [spotlightDonationService, playlistService] in
            await spotlightDonationService.observeMetadataEnrichment(from: playlistService)
        }
    }

    /// Feeds the `wxyc.concerts` Spotlight index on every On Tour window refresh
    /// (OT-C8, #654) — the live caller that makes the concert Spotlight pipeline
    /// non-dormant. The concert analogue of ``startSpotlightDonation()``.
    ///
    /// Observes `onTourModel.allConcerts` via `Observations` (which re-emits only
    /// when the window is reassigned — a load or refresh, not a trivial repaint)
    /// and hands each window to
    /// `ConcertSpotlightWindowObserver.donate(window:reconciler:inputs:)`, which
    /// skips only the not-loaded-yet empty window before calling `reconcile`
    /// (`reconcile` itself dedups an unchanged window against its persisted
    /// snapshot). The on-device inputs (liked artists, station cap, dismissed
    /// set) are gathered fresh per emission; because `reconcile` re-tiers a
    /// concert only when its identity or status changes, an inputs-only change
    /// takes effect on the next window change rather than instantly (see
    /// `ConcertSpotlightReconcileInputs`).
    ///
    /// Kicks off one launch load of `onTourModel` so the window populates — and
    /// the first donation happens — even if the user never opens the On Tour tab,
    /// satisfying the "on launch the curated window is donated" acceptance
    /// criterion. `OnTourModel`'s single-flight `load()` coalesces this with the
    /// tab's own `.task` load, so the two never double-fetch. Skipped under
    /// `-marketing`, where the tab drives a fixture model and the production
    /// window must never hit the network.
    ///
    /// The task is stored on `Singletonia.shared` and captures `self` strongly,
    /// forming a self → task → self cycle — but `Singletonia.shared` is a
    /// process-lifetime `static let` that is never released, so there is nothing
    /// to break (the same immortal-singleton rationale as
    /// ``startSpotlightDonation()``). Capturing `self` — rather than a `weak self`
    /// that could never actually go nil here — keeps the per-emission
    /// ``currentConcertSpotlightInputs`` read direct.
    private func startConcertSpotlightDonation() {
        concertSpotlightDonationTask = Task { [self] in
            let windows = Observations { self.onTourModel.allConcerts }
            for await window in windows {
                guard !Task.isCancelled else { break }
                await concertSpotlightWindowObserver.donate(
                    window: window,
                    reconciler: concertSpotlightDonationService,
                    inputs: currentConcertSpotlightInputs
                )
            }
        }

        guard !ProcessInfo.processInfo.arguments.contains("-marketing") else { return }
        Task { [onTourModel] in await onTourModel.load() }
    }

    /// The on-device inputs `ConcertSpotlightDonationService.reconcile` needs
    /// beyond the window — the **single source** both the live donation loop and
    /// `OnTourTabView` (its For You shelf, its OT-Q2 debug reconcile/inspect
    /// triggers) read, so the tier resolution can't drift between the visible
    /// shelf and the donated index. Uses raw (non-debug-seeded) liked artists,
    /// deliberately: the For You shelf's loved-seed debug toggle is a UI-only fake
    /// that must never leak a synthetic like into the real Spotlight index.
    var currentConcertSpotlightInputs: ConcertSpotlightReconcileInputs {
        ConcertSpotlightReconcileInputs(
            likedArtists: currentLikedArtists,
            stationCap: currentConcertSpotlightStationCap,
            dismissedConcertIDs: dismissedConcertsStore.ids
        )
    }

    /// The listener's id-bearing liked artists, projected from the likes store.
    /// The store is newest-first, so the engine's first-id-wins de-duplication
    /// keeps the most recently-liked display name for a repeated artist id. The
    /// single source `OnTourTabView.likedArtists` also reads.
    var currentLikedArtists: [LikedArtist] {
        likedSongsStore.songs.compactMap { song in
            song.artistId.map { LikedArtist(id: $0, name: song.artistName) }
        }
    }

    /// PostHog key for the On Tour For You station-recommended tier cap. The
    /// single canonical definition; `OnTourTabView` reads the resolved cap via
    /// ``currentConcertSpotlightStationCap`` rather than re-reading the key. Local
    /// default 0 (tier off) until PostHog raises it (WXYC/wxyc-ios-64#551).
    private static let onTourStationCapFlagKey = "on_tour_for_you_station_cap"

    /// The station-recommended tier cap the For You shelf and `reconcile` should
    /// use: a positive DEBUG seed override takes precedence over the PostHog flag.
    /// The single source `OnTourTabView`'s shelf and debug triggers also read.
    var currentConcertSpotlightStationCap: Int {
        let flagStationCap = featureFlagProvider.integerValue(forKey: Self.onTourStationCapFlagKey, default: 0)
        #if DEBUG
        let override = OnTourForYouSeedDebugState.shared.stationCapOverride
        return override > 0 ? override : flagStationCap
        #else
        return flagStationCap
        #endif
    }

    /// Feeds the persistent playcut history on every playlist tick.
    ///
    /// The store owns its subscription loop (the `WidgetStateService.start()`
    /// precedent), so unlike the sibling observation tasks there is nothing
    /// long-lived to store or cancel here: this fire-and-forget task exists
    /// only because `start(observing:)` is actor-isolated and `init` cannot
    /// await it. The captures are intentionally strong — both services live
    /// as long as `Singletonia.shared`.
    private func startPlaycutHistory() {
        Task { [playcutHistoryStore, playlistService] in
            await playcutHistoryStore.start(observing: playlistService)
        }
    }

    /// Heals name-only likes on every playlist tick.
    ///
    /// Subscribes to `PlaylistService.updates()` (a multi-observer broadcast),
    /// the same insertion pattern as `startSpotlightDonation()`. Each tick's
    /// id-bearing playcuts stamp catalog artist ids onto liked rows whose like
    /// predates the id being on the wire (free-text plays, the v1 API path) —
    /// what makes those likes eligible for the For You shelf (#493). `heal` is
    /// cheap (a dictionary pass over ~KB of snapshots) and saves only when
    /// something changed.
    ///
    /// The captures are intentionally strong: the task's lifetime is bound to
    /// `Singletonia.shared` (a static let), so there is no cycle to break and
    /// `[weak self]` would be misleading.
    private func startLikedSongsHealing() {
        likedSongsHealingTask = Task { [likedSongsStore, playlistService] in
            for await playlist in playlistService.updates() {
                guard !Task.isCancelled else { break }
                likedSongsStore.heal(from: playlist.playcuts)
            }
        }
    }

    /// Fan `AudioPlayerController.isPlaying` transitions out to both
    /// MPNowPlayingInfoCenter and the Handoff activity.
    ///
    /// The NowPlayingInfoCenter side is required so the system promotes WXYC
    /// to the active Now Playing app on macOS / Mac Catalyst — without an
    /// explicit playbackState, Control Center stays empty and media keys are
    /// routed to other apps. The Handoff side keeps the cross-device Handoff
    /// banner advertised only while this device is actually playing.
    private func startPlaybackStateObservation() {
        playbackStateTask = Task { [weak self] in
            // Dedupe: Observations re-yields on every tracked-property change, but isPlaying
            // collapses several player states (loading, stalled, error) to one Bool, so most
            // transitions repeat the previous value. Each MPNowPlayingInfoCenter write is an
            // IPC round-trip to mediaserverd, so skipping no-ops matters.
            var last: Bool?
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            for await isPlaying in observations {
                guard !Task.isCancelled else { break }
                guard isPlaying != last else { continue }
                last = isPlaying
                self?.nowPlayingInfoCenterManager.setPlaybackState(isPlaying: isPlaying)
                self?.handoffActivityManager.setPlaybackState(isPlaying: isPlaying)
            }
        }
    }

    /// Route a scene phase to the services that care about it.
    ///
    /// Called on every scene-phase change and from each window's `.onAppear`,
    /// which passes the phase it is appearing into rather than assuming
    /// `.active` — a window can appear into an already-backgrounded scene
    /// (multi-window, CarPlay scene connection, background launch), and no
    /// further phase *change* would follow to correct a wrong guess.
    ///
    /// The two consumers deliberately read the phase differently, because they
    /// are answering different questions:
    ///
    /// - **Widget reloads** are budgeted (roughly 40-70 timeline reloads a day)
    ///   and only pay off while the app is actually frontmost, so they stop at
    ///   `.inactive`. An unfocused iPad Split View pane or a non-frontmost
    ///   Catalyst window can sit `.inactive` for hours, and every live-fs event
    ///   arriving in that window would otherwise spend budget on a widget
    ///   nobody is looking at.
    /// - **The live-fs SSE subscription** must survive `.inactive`, which fires
    ///   for Control Center, notification banners and the app switcher with the
    ///   app still on screen. Tearing it down there left it down, because no
    ///   further phase change was coming to bring it back.
    ///
    /// Foreground state reaches `playlistService` through a relay rather than a
    /// fresh `Task` per call. The scene-phase handler and `.onAppear` are
    /// independent producers, so a rapid pair has no guaranteed arrival order
    /// between unstructured tasks. Arriving inverted latches
    /// `isForegrounded = false` on a service whose app is on screen, and since
    /// nothing re-checks the flag afterwards the SSE subscription stays down
    /// for the rest of the session. The relay fixes the order synchronously, on
    /// the MainActor, before any suspension can shuffle it — and, because only
    /// the newest push describes the world, drops any it overtakes, so a burst
    /// costs one subscription decision instead of one per phase.
    func setScenePhase(_ phase: ScenePhase) {
        let routing = Self.foregroundRouting(for: phase)
        widgetStateService.setForegrounded(routing.widgetsForegrounded)

        // The service ignores this when live updates aren't enabled, so it's a
        // no-op on any non-iOS PlaylistService instance (#269).
        switch routing.playlistVisibility {
        case .onScreen:
            foregroundRelay.send(true)
        case .offScreen:
            foregroundRelay.send(false)
        case .noChange:
            break
        }
    }

    /// How one scene phase routes to the two consumers that disagree about it.
    ///
    /// Factored out as a pure function because `setScenePhase(_:)` itself is not
    /// reachable from a test without standing up the whole graph — the same
    /// approach `likedStorage(isMarketing:)` takes. The disagreement is the part
    /// worth pinning: collapsing these two back into one `Bool` is what spent
    /// widget budget on an app nobody was looking at.
    struct ForegroundRouting: Equatable {
        /// Widget timeline reloads are budgeted, so they run only while the app
        /// is genuinely frontmost.
        let widgetsForegrounded: Bool
        /// The live-fs subscription closes only on a phase that proves the app
        /// left the screen.
        let playlistVisibility: ForegroundVisibility
    }

    static func foregroundRouting(for phase: ScenePhase) -> ForegroundRouting {
        ForegroundRouting(
            widgetsForegrounded: phase == .active,
            playlistVisibility: ForegroundVisibility(entering: phase)
        )
    }

    /// Start the widget state service to observe playback and playlist updates
    func startWidgetStateService() {
        widgetStateService.start()
    }

    // MARK: - Configuration

    /// Fetches secrets from the backend and upgrades services that depend on them.
    ///
    /// Call this early in the app lifecycle. The artwork service starts with cache + URL
    /// fetcher only; once secrets arrive with Discogs credentials, the Discogs API fallback
    /// is added to the fetcher chain. Requires device session auth.
    ///
    /// Retries with exponential backoff on failure because a transient timeout would
    /// otherwise leave the Discogs fallback disabled for the entire session, causing
    /// all artwork lookups to fail for v1 API entries (which have no inline artworkURL).
    func fetchConfiguration() async {
        let appConfiguration = AppConfiguration()
        let maxAttempts = 4
        var delay: Duration = .seconds(5)

        for attempt in 1...maxAttempts {
            guard let secrets = await appConfiguration.fetchSecrets(tokenProvider: MusicShareKit.tokenProvider) else {
                Log(.info, "Secrets fetch attempt \(attempt)/\(maxAttempts) failed")

                guard attempt < maxAttempts else {
                    Log(.warning, "No secrets available after \(maxAttempts) attempts — Discogs fallback disabled")
                    return
                }

                try? await Task.sleep(for: delay)
                delay *= 3
                continue
            }

            if !secrets.discogsApiKey.isEmpty, !secrets.discogsApiSecret.isEmpty {
                let discogs = DiscogsArtworkService(
                    key: secrets.discogsApiKey,
                    secret: secrets.discogsApiSecret
                )
                await artworkService.addFetcher(discogs)
                artworkLoader.retryFailures()
                Log(.info, "Artwork service upgraded with Discogs fallback (attempt \(attempt))")
            }
            return
        }
    }

    // MARK: - Review Request Tracking

    private var playbackObservationTask: Task<Void, Never>?
    private var requestSentObservationTask: Task<Void, Never>?

    /// Start observing playback state to track user engagement for review requests.
    func startReviewRequestTracking() {
        startObservingPlaybackState()
        startObservingRequestSent()
    }

    private func startObservingPlaybackState() {
        playbackObservationTask?.cancel()

        playbackObservationTask = Task { [weak self] in
            guard let self else { return }

            var wasPlaying = AudioPlayerController.shared.isPlaying

            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            for await isPlaying in observations {
                guard !Task.isCancelled else { break }

                // Track when playback starts (transition from not playing to playing)
                if isPlaying && !wasPlaying {
                    self.reviewRequestService.recordPlaybackStarted()
                }
                wasPlaying = isPlaying
            }
        }
    }

    private func startObservingRequestSent() {
        requestSentObservationTask?.cancel()

        requestSentObservationTask = Task { [weak self] in
            guard let self else { return }

            for await _ in NotificationCenter.default.messages(of: RequestServiceSubject.shared, for: RequestSentMessage.self) {
                guard !Task.isCancelled else { break }
                self.reviewRequestService.recordRequestSent()
            }
        }
    }

    // MARK: - Deep-link routing (#537)

    /// Begins observing shared On Tour show links, so a tapped
    /// `wxyc.org/shows/<id>` (or `wxyc://concert/<id>`) fills ``pendingConcertLink``.
    ///
    /// Registered synchronously (not through an `async` sequence) from the root
    /// view's `.onAppear`, which runs before the launch link is delivered — so a
    /// cold launch straight into a shared link can't post the `ConcertOpenMessage`
    /// before the observer exists. Idempotent: the observer lives for the app's
    /// lifetime, so a re-appearance doesn't stack a second one.
    func startObservingConcertOpen() {
        guard concertOpenObservation == nil else { return }
        concertOpenObservation = NotificationCenter.default.addMainActorObserver(
            for: ConcertOpenMessage.self
        ) { [weak self] message in
            self?.pendingConcertLink = PendingConcertLink(
                id: message.concertID,
                source: message.source.rawValue
            )
        }
    }

    /// Clears the pending link once the On Tour tab has consumed it, so dismissing
    /// the opened show (or a re-appearance) doesn't re-trigger the resolution.
    func consumePendingConcertLink() {
        pendingConcertLink = nil
    }

    /// Begins observing playcut deep links, so a Spotlight/Siri tap
    /// (`OpenPlaycut`) or a tapped `wxyc://playcut/<id>` link fills
    /// ``pendingPlaycutLink`` (#434).
    ///
    /// Registered synchronously from the root view's `.onAppear`, mirroring
    /// ``startObservingConcertOpen()`` — see that method's doc comment for why
    /// this can't wait for an `async` sequence. Idempotent: the observer lives
    /// for the app's lifetime, so a re-appearance doesn't stack a second one.
    func startObservingPlaycutOpen() {
        guard playcutOpenObservation == nil else { return }
        playcutOpenObservation = NotificationCenter.default.addMainActorObserver(
            for: PlaycutOpenMessage.self
        ) { [weak self] message in
            self?.pendingPlaycutLink = PendingPlaycutLink(id: message.playcutID.value)
        }
    }

    /// Clears the pending link once `PlaylistView` has consumed it, so a
    /// re-appearance doesn't re-trigger the scroll.
    func consumePendingPlaycutLink() {
        pendingPlaycutLink = nil
    }

    /// Begins observing `OpenVenue` intent requests, so a Siri/Spotlight tap
    /// on a venue fills ``pendingVenueLink`` (OT-C4).
    ///
    /// Registered synchronously from the root view's `.onAppear`, mirroring
    /// ``startObservingConcertOpen()`` — see that method's doc comment for why
    /// this can't wait for an `async` sequence. Idempotent: the observer lives
    /// for the app's lifetime, so a re-appearance doesn't stack a second one.
    func startObservingVenueOpen() {
        guard venueOpenObservation == nil else { return }
        venueOpenObservation = NotificationCenter.default.addMainActorObserver(
            for: VenueOpenMessage.self
        ) { [weak self] message in
            self?.pendingVenueLink = PendingVenueLink(id: message.venueID)
        }
    }

    /// Clears the pending link once the On Tour tab has consumed it, so a
    /// re-appearance doesn't re-apply the venue filter.
    func consumePendingVenueLink() {
        pendingVenueLink = nil
    }

    // MARK: - Marketing recording (`-marketing`)

    /// Sets the marketing-driven tab route; `RootTabView` reacts via `.onChange`.
    func setMarketingRoute(_ route: MarketingRoute?) {
        marketingRoute = route
    }

    /// Requests `OnTourTabView` dismiss any presented concert detail. Called by
    /// `MarketingModeController` before switching away from the On Tour tab, as
    /// a signal separate from ``setMarketingRoute(_:)`` — see
    /// ``marketingDismissOnTourDetailToken``.
    func requestMarketingOnTourDetailDismissal() {
        marketingDismissOnTourDetailToken += 1
    }

    /// Restores the For You seed debug knobs `-marketing` overrode in `init`, so
    /// a completed recording doesn't leave `stationCapOverride` (a persisted
    /// `UserDefaults` knob) stuck forcing the station tier on for a later,
    /// non-`-marketing` launch on the same simulator. Called once by
    /// `MarketingModeController` after the storyboard finishes. A no-op in
    /// Release, or when nothing was overridden.
    func restoreForYouSeedOverridesAfterMarketingRecording() {
        #if DEBUG
        guard let backup = marketingForYouSeedOverrideBackup else { return }
        let seedState = OnTourForYouSeedDebugState.shared
        seedState.seedLovedEnabled = backup.seedLovedEnabled
        seedState.stationCapOverride = backup.stationCapOverride
        marketingForYouSeedOverrideBackup = nil
        #endif
    }

    /// Chooses the likes-store backing. Under `-marketing` (DEBUG only) returns an
    /// in-memory store so seeded likes never touch `liked-songs.json`; production
    /// always gets the durable Application Support file. Static so it's callable
    /// from the `likedSongsStore` property initializer, which runs before `self`
    /// exists.
    private static func makeLikedStorage() -> any FileStorage {
        likedStorage(isMarketing: ProcessInfo.processInfo.arguments.contains("-marketing"))
    }

    /// The pure storage-selection decision, factored out of `makeLikedStorage()`
    /// so it's unit-testable without depending on `ProcessInfo` launch arguments
    /// or `MarketingModeController.isEnabled` (a cached `static let` that a host
    /// unit test can neither set nor reset).
    static func likedStorage(isMarketing: Bool) -> any FileStorage {
        #if DEBUG
        if isMarketing {
            return MarketingFileStorage()
        }
        #endif
        return AppSupportFileStorage(filename: "liked-songs.json")
    }

    /// Chooses the dismissed-concerts-store backing. Under `-marketing` (DEBUG
    /// only) returns an in-memory store so a recording can never read or
    /// overwrite `dismissed-concerts.json`; production always gets the durable
    /// Application Support file. Static so it's callable from the
    /// `dismissedConcertsStore` property initializer, which runs before `self`
    /// exists.
    private static func makeDismissedConcertsStorage() -> any FileStorage {
        dismissedConcertsStorage(isMarketing: ProcessInfo.processInfo.arguments.contains("-marketing"))
    }

    /// The pure storage-selection decision, factored out of
    /// `makeDismissedConcertsStorage()` so it's unit-testable the same way
    /// ``likedStorage(isMarketing:)`` is.
    static func dismissedConcertsStorage(isMarketing: Bool) -> any FileStorage {
        #if DEBUG
        if isMarketing {
            return MarketingFileStorage()
        }
        #endif
        return AppSupportFileStorage(filename: "dismissed-concerts.json")
    }
}
