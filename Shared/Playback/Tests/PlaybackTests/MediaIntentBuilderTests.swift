//
//  MediaIntentBuilderTests.swift
//  Playback
//
//  Guards the one canonical INPlayMediaIntent identity (#828) both donation
//  sites — WXYCApp.makeSiriIntentInteraction() and
//  AudioPlayerController.donatePlayIntent() — now build through. Before this,
//  each site built its own INMediaItem with a different identifier and a
//  different resumePlayback, splitting whatever per-item learning iOS's
//  media-suggestion engine does across two buckets.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(Intents) && !os(macOS)
import Core
import Intents
import Testing
@testable import PlaybackCore

@Suite("MediaIntentBuilder")
struct MediaIntentBuilderTests {
    @Test("Builds the canonical WXYC play-media intent identity")
    func buildsCanonicalIdentity() {
        let intent = MediaIntentBuilder.makePlayMediaIntent(artwork: nil)
        let mediaItem = intent.mediaItems?.first

        #expect(mediaItem?.identifier == RadioStation.WXYC.identifier)
        #expect(mediaItem?.title == "WXYC 89.3 FM")
        #expect(mediaItem?.type == .radioStation)
        // A live stream can't be resumed — see the design doc's canonical
        // identity block.
        #expect(intent.resumePlayback == false)
        #expect(intent.suggestedInvocationPhrase == "Play WXYC")
    }

    @Test("A supplied artwork survives onto the media item")
    func suppliedArtworkSurvivesOntoTheMediaItem() {
        let artwork = INImage(imageData: Data([0x01, 0x02, 0x03]))
        let intent = MediaIntentBuilder.makePlayMediaIntent(artwork: artwork)

        #expect(intent.mediaItems?.first?.artwork != nil)
    }

    @Test("Nil artwork yields nil on the media item")
    func nilArtworkYieldsNilOnTheMediaItem() {
        let intent = MediaIntentBuilder.makePlayMediaIntent(artwork: nil)

        #expect(intent.mediaItems?.first?.artwork == nil)
    }
}
#endif
