//
//  PlaybackAttributes.swift
//  Intents
//
//  The shuffle/repeat attributes the iOS 27 playAudio schema declares. They are
//  meaningless for a single continuous live stream, so PlayWXYCAudio accepts and
//  ignores them; the enum exists only to satisfy the schema shape.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import AppIntents

@available(iOS 27.0, *)
@AppEnum(schema: .audio.playbackAttributes)
enum PlaybackAttributes: String {
    case shuffle
    case `repeat`

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .shuffle: "Shuffle",
        .repeat: "Repeat"
    ]
}
#endif
