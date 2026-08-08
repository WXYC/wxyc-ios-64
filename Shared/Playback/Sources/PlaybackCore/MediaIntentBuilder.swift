//
//  MediaIntentBuilder.swift
//  PlaybackCore
//
//  The one canonical INPlayMediaIntent identity for WXYC (#828), shared by
//  every SiriKit donation site: WXYCApp.makeSiriIntentInteraction() (launch
//  time) and AudioPlayerController.donatePlayIntent() (play time). Before
//  this, each site built its own INMediaItem with its own identifier and its
//  own resumePlayback value, splitting whatever per-item learning iOS's
//  media-suggestion engine does across two buckets — see the "Canonical
//  intent identity" section of docs/plans/media-suggestion-headphones.md.
//
//  Artwork is deliberately a caller-supplied parameter rather than baked in
//  here: the launch-time donation composites a real placeholder image, the
//  play-time donation and MediaSuggestionService (AppServices) both pass
//  nil to stay off the #740 main-actor compositing hazard. This file has no
//  opinion on which.
//
//  Compiles for watchOS as well as iOS — the first time INMediaItem /
//  INPlayMediaIntent / INImage have been compiled for watchOS in this repo,
//  since PlaybackCore (unlike the Playback product that houses
//  AudioPlayerController) has no watchOS-excluding dependency. Gated
//  `#if canImport(Intents) && !os(macOS)`, matching the existing donation
//  call sites: SiriKit is unavailable on macOS (API_UNAVAILABLE(macos) on
//  INPlayMediaIntent).
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(Intents) && !os(macOS)
import Core
import Intents

/// Builds the canonical WXYC `INPlayMediaIntent` — one identifier, one title,
/// one `resumePlayback` value — for every SiriKit donation site to share.
public enum MediaIntentBuilder {
    /// - Parameter artwork: Tile artwork for the media item, or `nil` to let
    ///   the suggestion tile fall back to the app icon. Callers decide: see
    ///   the file-level doc comment for why this builder takes no position.
    public static func makePlayMediaIntent(artwork: INImage?) -> INPlayMediaIntent {
        let mediaItem = INMediaItem(
            identifier: RadioStation.WXYC.identifier,
            title: "WXYC 89.3 FM",
            type: .radioStation,
            artwork: artwork
        )

        let intent = INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            // A live stream has no position to resume from.
            resumePlayback: false,
            playbackQueueLocation: .now,
            playbackSpeed: nil
        )
        intent.suggestedInvocationPhrase = "Play \(RadioStation.WXYC.name)"
        return intent
    }
}
#endif
