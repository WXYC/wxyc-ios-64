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
import AppIntents
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
    let playlistService = PlaylistService()
    let artworkService = MultisourceArtworkService()
    let artworkLoader: ArtworkLoader
    let widgetStateService: WidgetStateService
    let reviewRequestService = ReviewRequestService(minimumVersionForReview: "1.0")
    let spotlightDonationService = SpotlightDonationService(
        storage: UserDefaults.wxyc,
        indexer: CoreSpotlightIndexer()
    )
    let playcutHistoryStore = PlaycutHistoryStore()

    /// On-device liked songs (#492). A durable file store, not a cache — likes
    /// are user-curated canonical data with a never-evict contract (see
    /// docs/plans/492-liked-songs.md decision #6). `AppSupportFileStorage` is
    /// module-qualified because `Concerts` exports a same-named seam. Routed
    /// through `makeLikedStorage()` so a `-marketing` recording gets an
    /// in-memory store instead (see the `-marketing` section below).
    let likedSongsStore = LikedSongsStore(storage: Singletonia.makeLikedStorage())

    /// Concerts the listener dismissed ("Not interested") from the On Tour For You
    /// shelf. Same durable-file rationale as the likes store — user curation, not a
    /// re-derivable cache — so it goes through the Concerts `FileStorage` seam.
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
    private var nowPlayingPlaybackStateTask: Task<Void, Never>?
    private var spotlightDonationTask: Task<Void, Never>?
    private var spotlightMetadataEnrichmentTask: Task<Void, Never>?
    private var likedSongsHealingTask: Task<Void, Never>?

    private init() {
        // F3 (#427): register PlaycutHistoryStore and the Spotlight reindex
        // seam before anything else runs, so both are in place before any
        // intent/query the AppIntents runtime might construct — including
        // PlaycutEntityQuery's `@Dependency`-backed production `entities(for:)`
        // and iOS 27 reindex handlers — can run. `@Dependency`'s wrappedValue
        // traps if its type was never registered, so this must precede every
        // other line here. `playcutHistoryStore` is already initialized at
        // this point: stored properties with default-value expressions (like
        // this one, declared above) are set before a class's custom `init()`
        // body runs.
        AppDependencyManager.shared.add(dependency: self.playcutHistoryStore)
        let playcutReindexer: any PlaycutReindexer = CoreSpotlightIndexer()
        AppDependencyManager.shared.add(dependency: playcutReindexer)
        // #445: the iOS 27 reindex handlers report `SpotlightReindexRequested`
        // through this same `@Dependency` seam.
        let reindexAnalytics: any AnalyticsService = StructuredPostHogAnalytics.shared
        AppDependencyManager.shared.add(dependency: reindexAnalytics)

        self.widgetStateService = WidgetStateService(
            playbackController: AudioPlayerController.shared,
            playlistService: playlistService
        )
        self.artworkLoader = ArtworkLoader(service: artworkService)

        let screenWidth = UIScreen.main.bounds.size.width
        nowPlayingInfoCenterManager = NowPlayingInfoCenterManager(
            boundsSize: CGSize(width: screenWidth, height: screenWidth)
        )

        // Configure artwork cache to use half-screen-width scaled HEIF images.
        // Artwork is displayed at ~40% of screen width in playlist rows, so half-screen
        // resolution is more than sufficient. This cuts per-image memory from ~5.5MB to ~1.4MB.
        ArtworkCacheConfiguration.targetWidth = screenWidth * UIScreen.main.scale / 2

        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: artworkService
        )
        startNowPlayingObservation(nowPlayingService: nowPlayingService)
        startNowPlayingPlaybackStateObservation()
        startSpotlightDonation()
        startSpotlightMetadataEnrichmentReDonation()
        startPlaycutHistory()
        startLikedSongsHealing()

        #if DEBUG
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

    /// Mirror AudioPlayerController.isPlaying into MPNowPlayingInfoCenter.
    ///
    /// Required so the system promotes WXYC to the active Now Playing app on
    /// macOS / Mac Catalyst — without an explicit playbackState, Control Center
    /// stays empty and media keys are routed to other apps.
    private func startNowPlayingPlaybackStateObservation() {
        nowPlayingPlaybackStateTask = Task { [weak self] in
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
            }
        }
    }

    /// Update the foreground state (called when scene phase changes)
    func setForegrounded(_ foregrounded: Bool) {
        widgetStateService.setForegrounded(foregrounded)
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
            guard let authService = MusicShareKit.authService,
                  let secrets = await appConfiguration.fetchSecrets(tokenProvider: authService) else {
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
    private static func makeLikedStorage() -> any LikedSongs.FileStorage {
        likedStorage(isMarketing: ProcessInfo.processInfo.arguments.contains("-marketing"))
    }

    /// The pure storage-selection decision, factored out of `makeLikedStorage()`
    /// so it's unit-testable without depending on `ProcessInfo` launch arguments
    /// or `MarketingModeController.isEnabled` (a cached `static let` that a host
    /// unit test can neither set nor reset).
    static func likedStorage(isMarketing: Bool) -> any LikedSongs.FileStorage {
        #if DEBUG
        if isMarketing {
            return MarketingLikedStorage()
        }
        #endif
        return LikedSongs.AppSupportFileStorage(filename: "liked-songs.json")
    }

    /// Chooses the dismissed-concerts-store backing. Under `-marketing` (DEBUG
    /// only) returns an in-memory store so a recording can never read or
    /// overwrite `dismissed-concerts.json`; production always gets the durable
    /// Application Support file. Static so it's callable from the
    /// `dismissedConcertsStore` property initializer, which runs before `self`
    /// exists.
    private static func makeDismissedConcertsStorage() -> any Concerts.FileStorage {
        dismissedConcertsStorage(isMarketing: ProcessInfo.processInfo.arguments.contains("-marketing"))
    }

    /// The pure storage-selection decision, factored out of
    /// `makeDismissedConcertsStorage()` so it's unit-testable the same way
    /// ``likedStorage(isMarketing:)`` is.
    static func dismissedConcertsStorage(isMarketing: Bool) -> any Concerts.FileStorage {
        #if DEBUG
        if isMarketing {
            return MarketingDismissedConcertsStorage()
        }
        #endif
        return Concerts.AppSupportFileStorage(filename: "dismissed-concerts.json")
    }
}
