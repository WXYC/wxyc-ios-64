//
//  AudioRouteMonitor.swift
//  WXYC
//
//  Observable current-audio-route state for the Station tab's "Listening" row.
//  The mapping rules live in PlaybackCore's AudioRouteDescriber; this is the
//  thin observable shell that re-reads the route when the session says it moved.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AVFoundation
import Observation
import PlaybackCore
import UIKit

/// Tracks where audio is currently playing.
///
/// The route is read through an injected closure rather than an
/// `AVAudioSession` reference because `AVAudioSessionPortDescription` has no
/// public initializer — a test cannot build a fake route, but it can supply the
/// values a route would have produced.
@MainActor
@Observable
final class AudioRouteMonitor {

    /// How the current route should be presented.
    private(set) var label: AudioRouteLabel

    private let localDeviceLabel: String
    private let outputs: @Sendable () -> [AudioOutput]

    /// What to call this device when playback is local — "This iPhone", "This iPad".
    /// `UIDevice.model` is the generic device class, not the user's device name, so
    /// this reads no personal information.
    static var defaultDeviceLabel: String {
        "This \(UIDevice.current.model)"
    }

    /// Reads the live route from the shared `AVAudioSession`.
    private static let liveOutputs: @Sendable () -> [AudioOutput] = {
        AVAudioSession.sharedInstance().currentRoute.outputs.map {
            AudioOutput(portType: $0.portType, name: $0.portName)
        }
    }

    init(
        localDeviceLabel: String = AudioRouteMonitor.defaultDeviceLabel,
        outputs: @escaping @Sendable () -> [AudioOutput] = AudioRouteMonitor.liveOutputs
    ) {
        self.localDeviceLabel = localDeviceLabel
        self.outputs = outputs
        self.label = AudioRouteDescriber.label(
            for: outputs(),
            localDeviceLabel: localDeviceLabel
        )
    }

    /// Re-reads the current route.
    func refresh() {
        label = AudioRouteDescriber.label(
            for: outputs(),
            localDeviceLabel: localDeviceLabel
        )
    }

    /// Keeps ``label`` in step with the session until the calling task is
    /// cancelled. Drive this from a `.task` modifier so observation lives
    /// exactly as long as the view that shows it.
    func observeRouteChanges() async {
        refresh()
        for await _ in NotificationCenter.default.notifications(
            named: AVAudioSession.routeChangeNotification
        ) {
            refresh()
        }
    }
}
