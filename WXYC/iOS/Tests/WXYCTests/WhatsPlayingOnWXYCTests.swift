//
//  WhatsPlayingOnWXYCTests.swift
//  WXYC
//
//  Unit tests for WhatsPlayingOnWXYC intent.
//  Verifies perform() resolves to a PlaycutEntity (not a bare String) when a song
//  leads, so Siri follow-ups can resolve against the entity directly. When no song
//  leads (automation, or before a show's first song) the value is nil and the tests
//  have nothing to check.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Testing
@testable import WXYC
@testable import WXYCIntents

@Suite(
    "WhatsPlayingOnWXYC Intent Tests",
    .serialized,
    .tags(.e2e),
    .disabled(if: ProcessInfo.processInfo.environment["RUN_E2E"] != "1")
)
struct WhatsPlayingOnWXYCTests {

    @Test("perform() returns a PlaycutEntity matching the now-playing playcut")
    func performReturnsPlaycutEntity() async throws {
        let intent = WhatsPlayingOnWXYC()
        let result = try await intent.perform()

        // `result.value` is `PlaycutEntity??`; a nil entity is a valid answer when no song leads.
        guard let entity = result.value ?? nil else { return }
        #expect(!entity.title.isEmpty, "Entity title should be populated from the now-playing playcut")
        #expect(!entity.artistName.isEmpty, "Entity artist name should be populated from the now-playing playcut")
    }

    @Test("perform() entity subtitle includes the artist name")
    func performEntitySubtitleIncludesArtist() async throws {
        let intent = WhatsPlayingOnWXYC()
        let result = try await intent.perform()

        guard let entity = result.value ?? nil else { return }
        #expect(entity.subtitleText.contains(entity.artistName))
    }
}
