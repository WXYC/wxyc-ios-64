//
//  RadioShowEpisodeEntity.swift
//  Intents
//
//  One airing of a specialty program, modeled as an iOS 27 audio-schema `radioShowEpisode` entity.
//  Keyed by the show id from `on_air`. An episode exists only for a show row that carries
//  `specialty` (a DJ signed on as the program); nothing is inferred from the time slot. Distinct
//  from `ShowEntity`, which is a DJ sign-on keyed by its ShowMarker id.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema): the schema symbols do not exist in earlier
//  SDKs, so this file compiles out there.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import AppIntents
import Foundation
import Playlist

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@AppEntity(schema: .audio.radioShowEpisode)
struct RadioShowEpisodeEntity {
    static let defaultQuery = RadioShowEpisodeEntityQuery()

    let id: String

    var title: String
    var showName: String?
    var releaseDate: Date?
    var show: RadioShowEntity?

    /// `nil` unless `show` has an id and a `specialty`. `startTime` is the show's `start_time`, which
    /// `on_air` does not carry, so the caller supplies it.
    init?(show: OnAirShow, startTime: Date?) {
        guard let showID = show.id, let specialty = show.specialty else { return nil }
        self.id = String(showID)
        self.title = show.title.flatMap { $0.isEmpty ? nil : $0 } ?? specialty.name
        self.showName = specialty.name
        self.releaseDate = startTime
        self.show = RadioShowEntity(specialty: specialty)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    /// Resolves the airing the caller has already decoded. Past airings are not served by any
    /// endpoint the app reads, so an identifier that is not the current airing resolves to nothing.
    struct RadioShowEpisodeEntityQuery: EntityQuery {
        private let current: @Sendable () async -> RadioShowEpisodeEntity?

        init() {
            self.init(current: { nil })
        }

        init(current: @escaping @Sendable () async -> RadioShowEpisodeEntity?) {
            self.current = current
        }

        func entities(for identifiers: [String]) async throws -> [RadioShowEpisodeEntity] {
            guard let episode = await current(), identifiers.contains(episode.id) else { return [] }
            return [episode]
        }

        func suggestedEntities() async throws -> [RadioShowEpisodeEntity] {
            await current().map { [$0] } ?? []
        }
    }
}
#endif
#endif
