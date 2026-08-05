//
//  MarketingFileStorage.swift
//  WXYC
//
//  In-memory `Core.FileStorage` for `-marketing` recordings.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import Core
import Foundation

/// In-memory `Core.FileStorage` for `-marketing` recordings, so seeded likes
/// and dismissed shows stay in RAM and never write `liked-songs.json` /
/// `dismissed-concerts.json` on a simulator someone also uses by hand. The
/// shared `InMemoryFileStorage` lives in the test-only `CoreTesting` module,
/// which the app target doesn't link, so the app target needs its own.
/// Backs both `LikedSongsStore` and `DismissedConcertsStore` under
/// `-marketing` (see `Singletonia.likedStorage(isMarketing:)` and
/// `dismissedConcertsStorage(isMarketing:)`) — each call site constructs its
/// own instance, so the two stores never share state. Touched only on the
/// main actor by those stores, hence `@unchecked Sendable`.
final class MarketingFileStorage: Core.FileStorage, @unchecked Sendable {
    private var bytes: Data?
    func load() throws -> Data? { bytes }
    func save(_ data: Data) throws { bytes = data }
}
#endif
