//
//  WarmupAudioQueueResult.swift
//  Intents
//
//  The result entity the iOS 27 audio playAudio schema requires for its
//  warmup-queue parameter. WXYC plays a single live stream with no queue, so
//  this is a transient stub that exists only to satisfy the schema shape.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents

@available(iOS 27.0, *)
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct WarmupAudioQueueResult: TransientAppEntity {
    init() { }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Queue")
    }
}
#endif
