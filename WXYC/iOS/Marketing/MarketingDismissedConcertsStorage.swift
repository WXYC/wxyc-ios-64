//
//  MarketingDismissedConcertsStorage.swift
//  WXYC
//
//  In-memory `Concerts.FileStorage` for `-marketing` recordings.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG
import Concerts
import Foundation

/// In-memory `Concerts.FileStorage` for `-marketing` recordings, so the
/// recording can never read or overwrite a real `dismissed-concerts.json` on a
/// simulator someone also uses by hand. Mirrors `MarketingLikedStorage`, and for
/// the same reason: the shared `InMemoryFileStorage` lives in the unlinked
/// `ConcertsTesting` module, which the app target doesn't link. Touched only on
/// the main actor by `DismissedConcertsStore`, hence `@unchecked Sendable`.
final class MarketingDismissedConcertsStorage: Concerts.FileStorage, @unchecked Sendable {
    private var bytes: Data?
    func load() throws -> Data? { bytes }
    func save(_ data: Data) throws { bytes = data }
}
#endif
