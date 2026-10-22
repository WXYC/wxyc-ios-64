//
//  RadioShowEpisodeEntityTests.swift
//  WXYCIntents
//
//  Coverage for the iOS 27 `radioShowEpisode` entity: an airing keyed by its show id maps to a title
//  that falls back from `show_name` to the program name, `showName` = program name, `releaseDate` =
//  the show's start time, and `show` = the program's `RadioShowEntity`. Identity exists only for a
//  show row that carries `specialty`.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import Foundation
import Playlist
import Testing
@testable import WXYCIntents

@Suite("RadioShowEpisodeEntity (iOS 27 audio schema)")
struct RadioShowEpisodeEntityTests {
    private static let specialty = SpecialtyShowRef(id: 4, slug: "rock-lobster", name: "Rock Lobster")
    private static let start = Date(timeIntervalSince1970: 1_792_000_000)

    @Test("An airing maps to the show id, the show_name title, the program name, the start time, and the program entity")
    func mapsAiring() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let onAir = OnAirShow(id: 812, title: "Lobster Night", specialty: Self.specialty)

        let entity = RadioShowEpisodeEntity(show: onAir, startTime: Self.start)

        #expect(entity?.id == "812")
        #expect(entity?.title == "Lobster Night")
        #expect(entity?.showName == "Rock Lobster")
        #expect(entity?.releaseDate == Self.start)
        #expect(entity?.show?.id == "rock-lobster")
        #expect(entity?.show?.title == "Rock Lobster")
    }

    @Test("The title falls back to the program name when show_name is absent", arguments: [nil, ""])
    func titleFallsBack(showName: String?) {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let onAir = OnAirShow(id: 812, title: showName, specialty: Self.specialty)

        #expect(RadioShowEpisodeEntity(show: onAir, startTime: nil)?.title == "Rock Lobster")
        #expect(RadioShowEpisodeEntity(show: onAir, startTime: nil)?.releaseDate == nil)
    }

    @Test("A show row without a specialty has no episode identity, even with a show_name")
    func noSpecialtyNoIdentity() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let onAir = OnAirShow(id: 812, title: "Late Night", specialty: nil)

        #expect(RadioShowEpisodeEntity(show: onAir, startTime: Self.start) == nil)
    }

    @Test("A show row without a show id has no episode identity")
    func noShowIDNoIdentity() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let onAir = OnAirShow(id: nil, title: "Lobster Night", specialty: Self.specialty)

        #expect(RadioShowEpisodeEntity(show: onAir, startTime: Self.start) == nil)
    }

    @Test("The query resolves the current airing by show id and drops other ids")
    func queryResolvesCurrentAiring() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let episode = RadioShowEpisodeEntity(
            show: OnAirShow(id: 812, title: nil, specialty: Self.specialty),
            startTime: Self.start
        )
        let query = RadioShowEpisodeEntity.RadioShowEpisodeEntityQuery(current: { episode })

        #expect(try await query.entities(for: ["811", "812"]).map(\.id) == ["812"])
        #expect(try await query.entities(for: ["811"]).isEmpty)
        #expect(try await query.suggestedEntities().map(\.id) == ["812"])
        #expect(try await RadioShowEpisodeEntity.RadioShowEpisodeEntityQuery().entities(for: ["812"]).isEmpty)
    }
}
#endif
#endif
