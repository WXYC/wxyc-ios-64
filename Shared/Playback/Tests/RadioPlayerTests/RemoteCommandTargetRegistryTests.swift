//
//  RemoteCommandTargetRegistryTests.swift
//  Playback
//
//  Tests that remote-command teardown removes targets from the commands that
//  issued them, including commands registered conditionally.
//
//  Created by Jake Bromberg on 08/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS)
import MediaPlayer
import PlaybackTestUtilities
import Testing
@testable import PlaybackCore

@Suite("RemoteCommandTargetRegistry")
struct RemoteCommandTargetRegistryTests {

    @Test("removeAll removes targets from every command that issued one")
    func removeAllUnwindsEveryCommand() {
        let center = MockRemoteCommandCenter()
        var registry = RemoteCommandTargetRegistry()

        // The three always-registered commands plus the three that only exist on a
        // time-shiftable player. The latter three are exactly the ones a hardcoded
        // teardown list omitted.
        let commands: [MockRemoteCommand] = [
            center.mockPlayCommand,
            center.mockPauseCommand,
            center.mockTogglePlayPauseCommand,
            center.mockSkipBackwardCommand,
            center.mockSkipForwardCommand,
            center.mockChangePlaybackPositionCommand,
        ]

        for command in commands {
            registry.register(command) { _ in .success }
        }

        #expect(registry.count == commands.count)
        #expect(commands.allSatisfy { $0.targets.count == 1 })

        registry.removeAll()

        #expect(registry.count == 0)
        #expect(commands.allSatisfy { $0.targets.isEmpty })
    }

    @Test("removeAll leaves targets registered by anyone else alone")
    func removeAllLeavesForeignTargetsAlone() {
        let center = MockRemoteCommandCenter()
        var registry = RemoteCommandTargetRegistry()

        // A target registered outside the registry stands in for another owner of
        // the same process-global command centre.
        _ = center.playCommand.addTarget { _ in .success }
        registry.register(center.playCommand) { _ in .success }

        #expect(center.mockPlayCommand.targets.count == 2)

        registry.removeAll()

        #expect(center.mockPlayCommand.targets.count == 1)
    }

    @Test("removeAll is idempotent")
    func removeAllIsIdempotent() {
        let center = MockRemoteCommandCenter()
        var registry = RemoteCommandTargetRegistry()

        registry.register(center.skipForwardCommand) { _ in .success }
        registry.removeAll()
        registry.removeAll()

        #expect(registry.count == 0)
        #expect(center.mockSkipForwardCommand.targets.isEmpty)
    }
}
#endif
