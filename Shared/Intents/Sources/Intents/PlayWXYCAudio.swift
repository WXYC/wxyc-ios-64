//
//  PlayWXYCAudio.swift
//  Intents
//
//  The iOS 27 audio-schema entry point for starting the WXYC live stream. By
//  adopting Apple's `.audio.playAudio` AppSchema, WXYC becomes a first-class
//  participant in Siri's media-domain disambiguation, so "Hey Siri, play WXYC"
//  routes here instead of losing to Apple Music's built-in play intent — the
//  regression this fixes (#450). The schema alone is not enough: Siri fills
//  `audioEntity` by asking `LiveRadioStationEntity`'s query, whose
//  `IntentValueQuery` answers the bare "Play WXYC" request. WXYC has one
//  continuous live stream, so the schema's queue/shuffle/repeat parameters
//  are accepted and ignored.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema): the schema symbols do not
//  exist in earlier SDKs. Pre-iOS-27 voice playback stays on the PlayWXYC path.
//
//  Assistant-only: `PlayWXYC` is the one Play WXYC the Shortcuts app lists (and
//  the iOS 26 voice path). Without this the two intents present as a duplicate
//  pair — Apple's documented remedy for a schema intent added beside an
//  existing shortcut intent is to hide the schema one from Shortcuts.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import AppIntents
import PlaybackCore

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
@AppIntent(schema: .audio.playAudio)
struct PlayWXYCAudio: AudioPlaybackIntent {
    static let isAssistantOnly = true

    var audioEntity: AudioItem
    var playbackAttributes: Set<PlaybackAttributes>
    var warmupAudioQueueResult: WarmupAudioQueueResult?
    var queueLocation: QueueInsertionLocation?

    func perform() async throws -> some IntentResult {
        await IntentPlayback.startAndAwait(reason: .playAudioSchemaIntent)
        return .result()
    }
}
#endif
#endif
