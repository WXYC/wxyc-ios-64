//
//  OpenPlaycutTests.swift
//  WXYCIntents
//
//  Verifies OpenPlaycut.perform() posts a PlaycutOpenMessage carrying the
//  target entity's id — the message Singletonia observes to route a
//  Spotlight/Siri "open this playcut" hit to the playlist detail (#537),
//  mirroring OpenConcertTests/OpenVenueTests. There was no perform()-level
//  coverage for OpenPlaycut before this; PlaycutOpenMessageTests only
//  exercised the message type directly.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("OpenPlaycut")
struct OpenPlaycutTests {
    @Test("perform() posts a PlaycutOpenMessage with the target's id")
    @MainActor
    func performPostsPlaycutOpenMessage() async throws {
        let entity = PlaycutEntity(playcut: .stub(id: 42))
        let intent = OpenPlaycut(target: entity)

        // `queue: nil` delivers the observer synchronously on the poster's
        // thread, race-free without polling — mirroring OpenConcertTests.
        // This necessarily posts through the shared `NotificationCenter.default`
        // because that's what `perform()` uses; the observer is torn down
        // before this test returns.
        var observer: NSObjectProtocol?
        let received: PlaycutOpenMessage = await withCheckedContinuation { continuation in
            observer = NotificationCenter.default.addObserver(
                forName: PlaycutOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = PlaycutOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message)
                }
            }
            Task {
                _ = try? await intent.perform()
            }
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        #expect(received.playcutID == PlaycutID(42))
    }
}
