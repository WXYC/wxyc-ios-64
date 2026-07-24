//
//  Intents.swift
//  WXYC
//
//  App Intent definitions for Siri and Shortcuts.
//
//  Created by Jake Bromberg on 06/12/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import AppServices
import Artwork
import Concerts
import LikedSongs
import Logger
import MusicShareKit
import Playlist
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WXYCIntents

@_exported import struct WXYCIntents.PlayWXYC
@_exported import struct WXYCIntents.PauseWXYC
@_exported import struct WXYCIntents.ToggleWXYC
@_exported import struct WXYCIntents.IntentError
@_exported import struct WXYCIntents.OpenPlaycut
@_exported import struct WXYCIntents.OpenConcert

// App-level service access for intents
// App Intents run in a separate process and cannot access the main app's
// SwiftUI environment, so they must create their own service instances.
enum AppIntentServices {
    @MainActor
    static func nowPlayingService() -> NowPlayingService {
        NowPlayingService(
            playlistService: PlaylistService(),
            artworkService: MultisourceArtworkService()
        )
    }

    /// Builds a concerts fetcher exactly the way the On Tour tab does
    /// (`OnTourTabView`), so `ToursNearMe` sees the same live curated window.
    static func concertsFetcher() -> any ConcertsFetching {
        ConcertsFetcher(tokenProvider: MusicShareKit.authService)
    }

    /// The listener's id-bearing liked artists, read fresh from the on-device
    /// likes store. Deliberately never reaches into `Singletonia.shared` --
    /// App Intents run in a separate process from the main app's SwiftUI
    /// environment (see the comment above), so this builds its own
    /// `LikedSongsStore` the same way `nowPlayingService()` builds its own
    /// `NowPlayingService`. Routes storage selection through
    /// `Singletonia.likedStorage(isMarketing:)` so a `-marketing` recording
    /// gets the same in-memory swap the main app does, rather than
    /// duplicating that decision here.
    @MainActor
    static func likedArtists() -> [LikedArtist] {
        let storage = Singletonia.likedStorage(isMarketing: ProcessInfo.processInfo.arguments.contains("-marketing"))
        let store = LikedSongsStore(storage: storage)
        return store.songs.compactMap { song in song.artistId.map { LikedArtist(id: $0, name: song.artistName) } }
    }
}

struct WhatsPlayingOnWXYC: AppIntent, InstanceDisplayRepresentable {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Find out what's playing on WXYC"
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "What’s Playing on WXYC?"
    
    public var displayRepresentation = DisplayRepresentation(
        title: Self.title,
        subtitle: nil,
        image: .init(named: "message.fill")
    )

    public init() { }
    public func perform() async throws -> some ReturnsValue<PlaycutEntity> & ProvidesDialog & ShowsSnippetView {
        let nowPlayingService = await AppIntentServices.nowPlayingService()

        // Get the first item from the now playing service
        var iterator = nowPlayingService.makeAsyncIterator()
        guard let nowPlayingItem = try await iterator.next() else {
            let error = IntentError(description: "Could not fetch now playing item for WhatsPlayingOnWXYC intent.")
            ErrorReporting.shared.report(error, context: "fetchPlaylist")
            throw error
        }

        StructuredPostHogAnalytics.shared.capture(WhatsPlayingOnWXYCIntent())
        let playcutEntity = PlaycutEntity(playcut: nowPlayingItem.playcut)
        let dialog = "\(nowPlayingItem.playcut.songTitle) by \(nowPlayingItem.playcut.artistName) is now playing on WXYC."
        return .result(
            value: playcutEntity,
            dialog: IntentDialog(stringLiteral: dialog),
            view: NowPlayingView(item: nowPlayingItem)
        )
    }

    struct NowPlayingView: View {
        let item: NowPlayingItem

        var body: some View {
            ZStack(alignment: .bottom) {
                if let artwork = item.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFit()
                }
                
                VStack(alignment: .leading) {
                    Text(item.playcut.artistName)
                        .font(.headline)
                        .foregroundStyle(.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.playcut.songTitle)
                        .font(.subheadline)
                        .foregroundStyle(.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}

/// Intent donated when a user taps a streaming service to add a song to their library.
/// This intent is donation-only and does not perform any action when executed.
struct AddedSongToLibrary: AppIntent {
    static let title: LocalizedStringResource = "Added Song to Library"
    static let description: IntentDescription = "Records when you add a song from WXYC to your music library"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Song Title")
    var songTitle: String

    @Parameter(title: "Artist")
    var artistName: String

    @Parameter(title: "Album")
    var albumName: String?
        
    @Parameter(title: "Streaming Service")
    var streamingService: String

    @Parameter(title: "Artwork", supportedContentTypes: [.jpeg, .png])
    var artwork: IntentFile?

    init() {}

    init(
        songTitle: String,
        artistName: String,
        albumName: String?,
        streamingService: String,
        artwork: UIImage?
    ) {
        self.songTitle = songTitle
        self.artistName = artistName
        self.albumName = albumName
        self.streamingService = streamingService

        if let artwork, let data = artwork.jpegData(compressionQuality: 0.8) {
            self.artwork = IntentFile(data: data, filename: "artwork.jpg", type: .jpeg)
        }
    }

    func perform() async throws -> some IntentResult {
        // This intent is donation-only; it doesn't perform any action
        .result()
    }
}

struct MakeARequest: AppIntent, InstanceDisplayRepresentable {
    public var displayRepresentation = DisplayRepresentation(
        title: Self.title,
        subtitle: nil,
        image: .init(systemName: "radio.fill")
    )
    
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Request a song on WXYC"
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "Request a song on WXYC"

    @Parameter(title: "Request", description: "What song would you like to request?")
    var request: String

    public init() {

    }

    public func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        try await RequestService.shared.sendRequest(message: request)
        return .result(
            value: "Done",
            dialog: "Request sent!"
        )
    }
}

/// "What WXYC artists are touring near me?" (OT-C2, WXYC/wxyc-ios-64#625): the
/// marquee On Tour Siri/Spotlight query. Narrows the fetched curated concert
/// window (`ConcertsFetching`, the same source `OnTourTabView` uses) to a
/// Siri-selected date window, then prefers the listener's on-device
/// liked-artist intersection over the plain date-filtered set -- see
/// `ToursNearMeQuery` (WXYCIntents) for the pure, unit-tested core this thin
/// wrapper drives. No taste signal ever reaches the network: the fetch
/// (`AppIntentServices.concertsFetcher()`) takes no liked-artist parameter,
/// and the intersection happens entirely in `ToursNearMeQuery.matchingConcerts`,
/// in memory, over the already-public `curated=true` window (the On Tour
/// privacy invariant, restated for Siri).
///
/// Renders the domain `Concert` list (not `ConcertEntity`, which is the
/// minimal Spotlight-identity shape from OT-F1 and doesn't yet carry
/// `imageURL`/`ctaURL`) in `ToursNearMeSnippetView` for the poster/date/venue
/// card, while the `ReturnsValue` result surfaces `[ConcertEntity]` -- the
/// structured Siri answer other shortcuts/automations can chain from.
///
/// Universal on the 18.6 floor: `perform()`'s declared result already
/// includes `ShowsSnippetView`, which has shipped since iOS 16, so every
/// listener gets the card, not just a spoken dialog -- the "static snippet"
/// degrade path the design doc allows for pre-26. The iOS-26-only addition is
/// the `SnippetIntent` conformance declared below this type: gated on the
/// *type* via a same-file `@available(iOS 26, *)` extension, never branched
/// inside `perform()`, matching the design doc's "gate the type, never
/// branch inline" rule. That conformance unlocks `ToursNearMe.reload()` for a
/// future in-snippet button (OT-C7's "Add to Calendar", not yet landed) to
/// refresh this card in place without leaving Siri; no such button exists
/// yet, so the conformance is inert today but costs nothing to carry.
struct ToursNearMe: AppIntent, InstanceDisplayRepresentable {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = IntentDescription("Find WXYC-played artists with upcoming Triangle-area shows")
    public static let isDiscoverable = true
    public static let openAppWhenRun = false
    public static let title: LocalizedStringResource = "What’s Touring Near Me?"

    public var displayRepresentation = DisplayRepresentation(
        title: Self.title,
        subtitle: nil,
        image: .init(systemName: "calendar")
    )

    @Parameter(title: "When")
    var dateWindow: TouringDateWindow

    public init() {
        self.dateWindow = .next7Days
    }

    public init(dateWindow: TouringDateWindow) {
        self.dateWindow = dateWindow
    }

    @MainActor
    public func perform() async throws -> some ReturnsValue<[ConcertEntity]> & ProvidesDialog & ShowsSnippetView {
        let today = Date()
        let likedArtists = AppIntentServices.likedArtists()

        let matched: [Concert]
        do {
            matched = try await ToursNearMeQuery.resolve(
                fetcher: AppIntentServices.concertsFetcher(),
                dateWindow: dateWindow.filterWindow,
                likedArtists: likedArtists,
                now: today
            )
        } catch {
            ErrorReporting.shared.report(error, context: "ToursNearMe.perform")
            return .result(
                value: [],
                dialog: "Couldn’t reach WXYC’s On Tour listings right now.",
                view: ToursNearMeSnippetView(concerts: [])
            )
        }

        StructuredPostHogAnalytics.shared.capture(
            ToursNearMeIntentAnswered(dateWindow: dateWindow.rawValue, resultCount: matched.count)
        )

        return .result(
            value: matched.compactMap(ConcertEntity.init(concert:)),
            dialog: Self.dialog(for: matched),
            view: ToursNearMeSnippetView(concerts: matched)
        )
    }

    /// Builds the spoken answer: names up to the first three matches, then
    /// summarizes the rest by count. Never names more than three artists --
    /// a spoken list longer than that stops being useful.
    private static func dialog(for concerts: [Concert]) -> IntentDialog {
        guard !concerts.isEmpty else {
            return "No WXYC artists have upcoming Triangle shows in that window right now."
        }
        let named = concerts.prefix(3).map(\.headlineName)
        let summary = named.joined(separator: ", ")
        let remaining = concerts.count - named.count
        guard remaining > 0 else {
            return IntentDialog(stringLiteral: "\(summary) \(concerts.count == 1 ? "is" : "are") touring near you.")
        }
        let moreWord = remaining == 1 ? "artist is" : "artists are"
        return IntentDialog(stringLiteral: "\(summary), and \(remaining) more \(moreWord) touring near you.")
    }
}

@available(iOS 26.0, *)
extension ToursNearMe: SnippetIntent { }

/// The interactive snippet card for ``ToursNearMe``: a poster/headliner/venue/
/// date row per matched concert, with a "Get Tickets" link
/// (``Concert/ctaURL``) when the concert carries one. Shown on every OS floor
/// this app ships (`ShowsSnippetView` predates the `SnippetIntent` gating
/// above), so this view itself has no availability gate.
struct ToursNearMeSnippetView: View {
    let concerts: [Concert]

    var body: some View {
        if concerts.isEmpty {
            ContentUnavailableView(
                "No Shows Found",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No WXYC artists have upcoming Triangle shows in that window right now.")
            )
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(concerts) { concert in
                    ToursNearMeConcertRow(concert: concert)
                }
            }
            .padding()
        }
    }
}

private struct ToursNearMeConcertRow: View {
    let concert: Concert

    private static let dateFormat = Date.FormatStyle(timeZone: TimeZone(identifier: "America/New_York") ?? .gmt)
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ToursNearMePosterThumbnail(imageURL: concert.imageURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(concert.headlineName)
                    .font(.headline)
                    .foregroundStyle(.foreground)

                Text("\(concert.venue.name) — \(concert.venue.city), \(concert.venue.state)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(concert.startsOn.formatted(Self.dateFormat))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let ctaURL = concert.ctaURL {
                    Link("Get Tickets", destination: ctaURL)
                        .font(.subheadline)
                        .bold()
                }
            }
        }
    }
}

private struct ToursNearMePosterThumbnail: View {
    let imageURL: URL?

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
            } else {
                Image(systemName: "music.mic")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
                    .background(.secondary.opacity(0.2))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct WXYCAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsPlayingOnWXYC(),
            phrases: [
                "What’s playing on \(.applicationName)?",
                "What was the last song on \(.applicationName)",
            ],
            shortTitle: "What’s playing on WXYC?",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: PlayWXYC(),
            phrases: ["Play \(.applicationName)"],
            shortTitle: "Play WXYC",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: MakeARequest(),
            phrases: [
                "Make a request to \(.applicationName)",
                "Send a request to \(.applicationName)",
                "Request a song on \(.applicationName)",
                "Request a song for \(.applicationName)",
            ],
            shortTitle: "Send a request to WXYC",
            systemImageName: "message.fill"
        )
        AppShortcut(
            intent: OpenPlaycut(),
            phrases: [
                "Open the \(.applicationName) playcut",
                "What was that \(.applicationName) song",
            ],
            shortTitle: "Open Playcut",
            systemImageName: "music.note"
        )
        AppShortcut(
            intent: OpenConcert(),
            phrases: [
                "Open the \(.applicationName) concert",
                "Show me a \(.applicationName) concert",
            ],
            shortTitle: "Open Concert",
            systemImageName: "ticket.fill"
        )
        AppShortcut(
            intent: ToursNearMe(),
            phrases: [
                "What artists are touring near me on \(.applicationName)",
                "What's touring near me on \(.applicationName)",
                "What's touring this weekend on \(.applicationName)",
            ],
            shortTitle: "Touring Near Me",
            systemImageName: "calendar"
        )
    }
}
