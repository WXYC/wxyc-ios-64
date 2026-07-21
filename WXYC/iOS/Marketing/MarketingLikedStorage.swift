//
//  MarketingLikedStorage.swift
//  WXYC
//
//  In-memory `LikedSongs.FileStorage` for `-marketing` recordings.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import Foundation
import LikedSongs

/// In-memory `LikedSongs.FileStorage` for `-marketing` recordings, so seeded
/// likes stay in RAM and never write `liked-songs.json` on a simulator someone
/// also uses by hand. The shared `InMemoryFileStorage` lives in the unlinked
/// `LikedSongsTesting` module, which the app target doesn't link, so the app
/// target needs its own. Touched only on the main actor by `LikedSongsStore`,
/// hence `@unchecked Sendable`.
final class MarketingLikedStorage: LikedSongs.FileStorage, @unchecked Sendable {
    private var bytes: Data?
    func load() throws -> Data? { bytes }
    func save(_ data: Data) throws { bytes = data }
}
#endif
