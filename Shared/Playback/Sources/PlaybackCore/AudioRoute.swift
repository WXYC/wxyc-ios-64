//
//  AudioRoute.swift
//  Playback
//
//  Reduces an AVAudioSession route to the one line of text the UI shows for it.
//  Split from AVAudioSession itself so the mapping is testable: route
//  descriptions and port descriptions have no public initializers, so the rules
//  live here over plain values instead.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS) || os(tvOS) || os(watchOS)

import AVFoundation

/// A single output port of the current audio route, reduced to what a label needs.
public struct AudioOutput: Equatable, Sendable {
    /// The port's type, e.g. `.airPlay` or `.builtInSpeaker`.
    public let portType: AVAudioSession.Port

    /// The port's human-readable name, e.g. `"Kitchen HomePod"`. May be empty.
    public let name: String

    public init(portType: AVAudioSession.Port, name: String) {
        self.portType = portType
        self.name = name
    }
}

/// How the current audio route should be presented in the UI.
public struct AudioRouteLabel: Equatable, Sendable {
    /// The text to display, e.g. `"Kitchen HomePod"`, `"2 speakers"`, or the
    /// caller's device label. Never empty.
    public let name: String

    /// Whether audio is leaving this device's own speaker. Drives the accent
    /// treatment — there is nothing to highlight when playback is local.
    public let isExternal: Bool

    public init(name: String, isExternal: Bool) {
        self.name = name
        self.isExternal = isExternal
    }
}

/// Maps a route's output ports to a display label.
public enum AudioRouteDescriber {

    /// Ports that are part of the device itself rather than somewhere audio was sent.
    private static let deviceOwnedPorts: Set<AVAudioSession.Port> = [
        .builtInSpeaker,
        .builtInReceiver,
    ]

    /// Describes where audio is currently playing.
    ///
    /// Device-owned ports are filtered out first, so a route is "external" only
    /// when something other than the built-in speaker or receiver is carrying
    /// audio. More than one surviving port means AirPlay 2 multi-room, which
    /// collapses to a count rather than an unbounded list of names.
    ///
    /// - Parameters:
    ///   - outputs: The route's output ports, in the order the session reports them.
    ///   - localDeviceLabel: What to call this device when playback is local,
    ///     e.g. `"This iPhone"`. Also the fallback when an external port reports
    ///     no usable name, so the UI never renders an empty row.
    /// - Returns: The label to display.
    public static func label(
        for outputs: [AudioOutput],
        localDeviceLabel: String
    ) -> AudioRouteLabel {
        let local = AudioRouteLabel(name: localDeviceLabel, isExternal: false)
        let external = outputs.filter { !deviceOwnedPorts.contains($0.portType) }

        guard !external.isEmpty else { return local }

        // Multi-room: naming every speaker would overflow the row, and the count
        // is the part that actually tells you something you didn't already know.
        guard external.count == 1 else {
            return AudioRouteLabel(name: "\(external.count) speakers", isExternal: true)
        }

        let name = external[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return local }

        return AudioRouteLabel(name: name, isExternal: true)
    }
}

public extension AudioRouteDescriber {
    /// Convenience over a live `AVAudioSessionRouteDescription`.
    static func label(
        for route: AVAudioSessionRouteDescription,
        localDeviceLabel: String
    ) -> AudioRouteLabel {
        label(
            for: route.outputs.map { AudioOutput(portType: $0.portType, name: $0.portName) },
            localDeviceLabel: localDeviceLabel
        )
    }
}

#endif
