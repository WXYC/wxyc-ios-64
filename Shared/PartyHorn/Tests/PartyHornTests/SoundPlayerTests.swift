//
//  SoundPlayerTests.swift
//  PartyHorn
//
//  Tests for SoundPlayer's audio session configuration. The party horn must
//  play even when the device's silent switch is on, which requires activating
//  the .playback audio session category before playing.
//
//  Created by Jake Bromberg on 05/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import AVFoundation
@testable import PartyHorn

@MainActor
@Suite(
    "SoundPlayer audio session configuration",
    .tags(.ciHang),
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_CI_HANG"] == "1", "Hangs on CI paravirt activating AVAudioSession — excluded from CI")
)
struct SoundPlayerTests {

    @Test("play() activates the .playback category so audio overrides the silent switch")
    func playUsesPlaybackCategory() {
        let session = MockAudioSession()
        let player = SoundPlayer(audioSession: session)

        player.play()

        #expect(session.lastCategory == .playback)
    }

    @Test("play() mixes with other audio so the radio stream is not interrupted")
    func playMixesWithOthers() {
        let session = MockAudioSession()
        let player = SoundPlayer(audioSession: session)

        player.play()

        #expect(session.lastCategoryOptions?.contains(.mixWithOthers) == true)
    }

    @Test("play() activates the audio session")
    func playActivatesSession() {
        let session = MockAudioSession()
        let player = SoundPlayer(audioSession: session)

        player.play()

        #expect(session.lastActiveState == true)
    }

    @Test("Initialization does not configure the audio session, to avoid interrupting other apps")
    func initDoesNotConfigureSession() {
        let session = MockAudioSession()
        _ = SoundPlayer(audioSession: session)

        #expect(session.setCategoryCallCount == 0)
        #expect(session.setActiveCallCount == 0)
    }
}

// MARK: - Mocks

final class MockAudioSession: AudioSessionConfiguring, @unchecked Sendable {
    var setCategoryCallCount = 0
    var setActiveCallCount = 0
    var lastCategory: AVAudioSession.Category?
    var lastMode: AVAudioSession.Mode?
    var lastCategoryOptions: AVAudioSession.CategoryOptions?
    var lastActiveState: Bool?

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        setCategoryCallCount += 1
        lastCategory = category
        lastMode = mode
        lastCategoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        setActiveCallCount += 1
        lastActiveState = active
    }
}
