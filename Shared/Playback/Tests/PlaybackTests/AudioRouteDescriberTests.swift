//
//  AudioRouteDescriberTests.swift
//  Playback
//
//  Tests for the audio-route -> display-label mapping behind the Station tab's
//  "Listening" row.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS) || os(watchOS)

import AVFoundation
import Testing
@testable import PlaybackCore

/// One row of the mapping table. Extracted to a named type because large tuple
/// arrays in `@Test(arguments:)` blow up the type-checker.
private struct RouteCase: Sendable, CustomTestStringConvertible {
    let summary: String
    let outputs: [AudioOutput]
    let expectedName: String
    let expectedIsExternal: Bool

    var testDescription: String { summary }
}

private let localLabel = "This iPhone"

private let routeCases: [RouteCase] = [
    RouteCase(
        summary: "no outputs falls back to the device",
        outputs: [],
        expectedName: localLabel,
        expectedIsExternal: false
    ),
    RouteCase(
        summary: "built-in speaker is the device",
        outputs: [AudioOutput(portType: .builtInSpeaker, name: "Speaker")],
        expectedName: localLabel,
        expectedIsExternal: false
    ),
    RouteCase(
        summary: "built-in receiver is the device",
        outputs: [AudioOutput(portType: .builtInReceiver, name: "Receiver")],
        expectedName: localLabel,
        expectedIsExternal: false
    ),
    RouteCase(
        summary: "AirPlay reports the speaker's own name",
        outputs: [AudioOutput(portType: .airPlay, name: "Kitchen HomePod")],
        expectedName: "Kitchen HomePod",
        expectedIsExternal: true
    ),
    RouteCase(
        summary: "Bluetooth reports the device's own name",
        outputs: [AudioOutput(portType: .bluetoothA2DP, name: "AirPods Pro")],
        expectedName: "AirPods Pro",
        expectedIsExternal: true
    ),
    RouteCase(
        summary: "wired headphones read as headphones",
        outputs: [AudioOutput(portType: .headphones, name: "Headphones")],
        expectedName: "Headphones",
        expectedIsExternal: true
    ),
    RouteCase(
        summary: "car audio reports its own name",
        outputs: [AudioOutput(portType: .carAudio, name: "Volvo")],
        expectedName: "Volvo",
        expectedIsExternal: true
    ),
    // The AirPlay 2 case this whole feature exists for: several speakers at once.
    RouteCase(
        summary: "two AirPlay speakers collapse to a count",
        outputs: [
            AudioOutput(portType: .airPlay, name: "Kitchen HomePod"),
            AudioOutput(portType: .airPlay, name: "Living Room"),
        ],
        expectedName: "2 speakers",
        expectedIsExternal: true
    ),
    RouteCase(
        summary: "three AirPlay speakers collapse to a count",
        outputs: [
            AudioOutput(portType: .airPlay, name: "Kitchen HomePod"),
            AudioOutput(portType: .airPlay, name: "Living Room"),
            AudioOutput(portType: .airPlay, name: "Office"),
        ],
        expectedName: "3 speakers",
        expectedIsExternal: true
    ),
]

@Suite("AudioRouteDescriber")
struct AudioRouteDescriberTests {

    @Test("Route outputs map to a display label", arguments: routeCases)
    fileprivate func describesRoute(_ testCase: RouteCase) {
        let label = AudioRouteDescriber.label(
            for: testCase.outputs,
            localDeviceLabel: localLabel
        )

        #expect(label.name == testCase.expectedName)
        #expect(label.isExternal == testCase.expectedIsExternal)
    }

    @Test("An unrecognized port still reports its name rather than going blank")
    func unknownPortFallsBackToName() {
        let label = AudioRouteDescriber.label(
            for: [AudioOutput(portType: .usbAudio, name: "Scarlett 2i2")],
            localDeviceLabel: localLabel
        )

        #expect(label.name == "Scarlett 2i2")
        #expect(label.isExternal)
    }

    @Test("A nameless external port falls back to the device label, never an empty row")
    func namelessPortDoesNotProduceAnEmptyLabel() {
        let label = AudioRouteDescriber.label(
            for: [AudioOutput(portType: .airPlay, name: "")],
            localDeviceLabel: localLabel
        )

        #expect(label.name == localLabel)
        #expect(!label.isExternal)
    }
}

#endif
