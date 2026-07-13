//
//  QueueInsertionLocation.swift
//  Intents
//
//  Where in a playback queue the iOS 27 playAudio schema would insert an item.
//  WXYC has no queue — the live stream is always "now" — so PlayWXYCAudio accepts
//  and ignores this; the enum exists only to satisfy the schema shape.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents

@available(iOS 27.0, *)
@AppEnum(schema: .audio.queueInsertionLocation)
enum QueueInsertionLocation: String {
    case next
    case tail

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .next: "Next",
        .tail: "Tail"
    ]
}
#endif
