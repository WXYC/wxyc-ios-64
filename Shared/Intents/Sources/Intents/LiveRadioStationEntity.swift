//
//  LiveRadioStationEntity.swift
//  Intents
//
//  The single WXYC live-radio station, modeled as an iOS 27 audio-schema entity
//  so "Hey Siri, play WXYC" can resolve to a station WXYC owns instead of an
//  Apple Music search.
//
//  Under `.audio.playAudio`, Siri resolves the spoken name to an entity by
//  handing the relevant search term to the entity's query — NOT by asking for
//  "the" unique entity. A `UniqueAppEntityQuery` is never consulted on that
//  path, which is why an otherwise correctly-registered station still came back
//  unresolvable ("I can't find the station WXYC"). So the station is name-
//  resolvable via an `EntityStringQuery`: Siri passes the term, we return the
//  station when it names WXYC by call sign or frequency.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema): the schema symbols do not
//  exist in earlier SDKs. Pre-iOS-27 voice playback stays on the PlayWXYC path.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents

@available(iOS 27.0, *)
@AppEntity(schema: .audio.liveRadioStation)
struct LiveRadioStationEntity {
    static let defaultQuery = LiveRadioStationEntityQuery()

    let id: String

    var title: String
    var providerName: String?

    init() {
        self.id = "org.wxyc.live"
        self.title = "WXYC 89.3 FM"
        self.providerName = "WXYC Chapel Hill"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "WXYC 89.3 FM")
    }

    /// Resolves the one WXYC station for Siri's audio search. `entities(matching:)`
    /// is the method `.audio.playAudio` actually calls to turn "play WXYC" into a
    /// station entity; matching on the call sign or frequency keeps unrelated
    /// utterances from resolving to WXYC. `entities(for:)` round-trips the stable
    /// identifier so a resolved entity can be re-fetched later.
    struct LiveRadioStationEntityQuery: EntityStringQuery {
        func entities(for identifiers: [String]) async throws -> [LiveRadioStationEntity] {
            let station = LiveRadioStationEntity()
            return identifiers.contains(station.id) ? [station] : []
        }

        func entities(matching string: String) async throws -> [LiveRadioStationEntity] {
            let term = string.lowercased()
            let namesWXYC = term.contains("wxyc") || term.contains("89.3")
            return namesWXYC ? [LiveRadioStationEntity()] : []
        }

        func suggestedEntities() async throws -> [LiveRadioStationEntity] {
            [LiveRadioStationEntity()]
        }
    }
}
#endif
