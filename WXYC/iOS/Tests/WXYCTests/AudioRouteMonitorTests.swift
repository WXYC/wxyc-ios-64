//
//  AudioRouteMonitorTests.swift
//  WXYCTests
//
//  Tests for the observable wrapper that keeps the Station tab's "Listening"
//  row in step with the current audio route.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AVFoundation
import PlaybackCore
import Testing
@testable import WXYC

@MainActor
@Suite("AudioRouteMonitor")
struct AudioRouteMonitorTests {

    @Test("Starts on the local device when nothing external is attached")
    func startsLocal() {
        let monitor = AudioRouteMonitor(localDeviceLabel: "This iPhone") { [] }

        #expect(monitor.label.name == "This iPhone")
        #expect(!monitor.label.isExternal)
    }

    @Test("Refresh picks up a route that changed underneath it")
    func refreshTracksTheRoute() {
        nonisolated(unsafe) var outputs: [AudioOutput] = []
        let monitor = AudioRouteMonitor(localDeviceLabel: "This iPhone") { outputs }

        #expect(monitor.label.name == "This iPhone")

        outputs = [AudioOutput(portType: .airPlay, name: "Kitchen HomePod")]
        monitor.refresh()

        #expect(monitor.label.name == "Kitchen HomePod")
        #expect(monitor.label.isExternal)
    }

    @Test("Returning to the built-in speaker clears the external state")
    func refreshReturnsToLocal() {
        nonisolated(unsafe) var outputs: [AudioOutput] = [
            AudioOutput(portType: .airPlay, name: "Kitchen HomePod")
        ]
        let monitor = AudioRouteMonitor(localDeviceLabel: "This iPhone") { outputs }
        #expect(monitor.label.isExternal)

        outputs = [AudioOutput(portType: .builtInSpeaker, name: "Speaker")]
        monitor.refresh()

        #expect(monitor.label.name == "This iPhone")
        #expect(!monitor.label.isExternal)
    }

    @Test("Multi-room routes surface as a count")
    func multiRoomCollapsesToCount() {
        let monitor = AudioRouteMonitor(localDeviceLabel: "This iPhone") {
            [
                AudioOutput(portType: .airPlay, name: "Kitchen HomePod"),
                AudioOutput(portType: .airPlay, name: "Living Room"),
            ]
        }

        #expect(monitor.label.name == "2 speakers")
        #expect(monitor.label.isExternal)
    }
}
