//
//  LiveRadioStationEntity.swift
//  Intents
//
//  The single WXYC live-radio station, modeled as an iOS 27 audio-schema entity
//  so "Hey Siri, play WXYC" can resolve to a station WXYC owns instead of an
//  Apple Music search. There is exactly one station, so it adopts UniqueAppEntity
//  and its query returns that one entity.
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
struct LiveRadioStationEntity: UniqueAppEntity {
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

    struct LiveRadioStationEntityQuery: UniqueAppEntityQuery {
        func uniqueEntity() async throws -> LiveRadioStationEntity {
            LiveRadioStationEntity()
        }
    }
}
#endif
