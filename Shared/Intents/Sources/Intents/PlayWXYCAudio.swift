//
//  PlayWXYCAudio.swift
//  Intents
//
//  The iOS 27 audio-schema entry point for starting the WXYC live stream. By
//  adopting Apple's `.audio.playAudio` AppSchema, WXYC becomes a first-class
//  participant in Siri's media-domain disambiguation, so "Hey Siri, play WXYC"
//  routes here instead of losing to Apple Music's built-in play intent — the
//  regression this fixes (#450). WXYC has one continuous live stream, so the
//  schema's queue/shuffle/repeat parameters are accepted and ignored.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema): the schema symbols do not
//  exist in earlier SDKs. Pre-iOS-27 voice playback stays on the PlayWXYC path.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents
import PlaybackCore

@available(iOS 27.0, *)
@AppIntent(schema: .audio.playAudio)
struct PlayWXYCAudio: AudioPlaybackIntent {
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
