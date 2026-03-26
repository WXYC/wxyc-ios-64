//
//  MacSingletonia.swift
//  WXYC
//
//  Observable singleton holding shared macOS app state. Adapted from the iOS
//  Singletonia, omitting widget services and using NSScreen for display metrics.
//
//  Created by Jake Bromberg on 03/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppKit
import AppServices
import Artwork
import Caching
import Core
import Logger
import MediaPlayer
import Observation
import Playback
import Playlist
import SwiftUI
import Wallpaper

/// Shared app state for the macOS app.
@MainActor
@Observable
final class MacSingletonia {
    static let shared = MacSingletonia()

    let playlistService = PlaylistService()
    let artworkService = MultisourceArtworkService()

    let themeConfiguration = ThemeConfiguration()
    let themePickerState = ThemePickerState()

    private var nowPlayingObservationTask: Task<Void, Never>?

    private init() {
        let screenWidth = NSScreen.main?.frame.width ?? 420
        ArtworkCacheConfiguration.targetWidth = screenWidth * (NSScreen.main?.backingScaleFactor ?? 2)

        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: artworkService
        )
        startNowPlayingObservation(nowPlayingService: nowPlayingService)
    }

    private func startNowPlayingObservation(nowPlayingService: NowPlayingService) {
        nowPlayingObservationTask = Task {
            do {
                for try await item in nowPlayingService {
                    guard !Task.isCancelled else { break }
                    updateNowPlayingInfo(item)
                }
            } catch {
                Log(.error, "NowPlaying observation error: \(error)")
            }
        }
    }

    private func updateNowPlayingInfo(_ item: NowPlayingItem) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtist] = item.playcut.artistName
        info[MPMediaItemPropertyTitle] = item.playcut.songTitle
        info[MPMediaItemPropertyAlbumTitle] = item.playcut.releaseTitle ?? ""
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
