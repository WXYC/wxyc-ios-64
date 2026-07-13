//
//  AudioItem.swift
//  Intents
//
//  The union of audio entities the iOS 27 playAudio schema can target. WXYC only
//  ever plays its one live station, so this is a one-case union — the schema
//  permits a single case and this keeps us out of the other sixteen audio entity
//  types we don't model.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents

@available(iOS 27.0, *)
@UnionValue
enum AudioItem {
    case liveRadioStation(LiveRadioStationEntity)
}
#endif
