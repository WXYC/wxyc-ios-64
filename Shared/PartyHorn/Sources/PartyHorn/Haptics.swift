//
//  Haptics.swift
//  Party Horn
//
//  Created by Jake Bromberg on 8/16/25.
//

import UIKit
import CoreHaptics

@MainActor
final class Haptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            engine?.resetHandler = { [weak self] in
                // Engine can reset after interruptions; restart it
                try? self?.engine?.start()
            }
            try engine?.start()
        } catch {
            print("Haptics init error:", error)
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine?.stop()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            try? self?.engine?.start()
        }
    }

    /// Call this from your tap handler
    func onTap() {
        guard let engine else { return }

        do {
            var events: [CHHapticEvent] = []
            var curves: [CHHapticParameterCurve] = []

            // Continuous rumble that fades out over 1.5s
            let baseSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0)
            let baseIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)

            let fadeUp   = CHHapticParameterCurve.ControlPoint(relativeTime: 0.0, value: 1.0)
            let fadeDown = CHHapticParameterCurve.ControlPoint(relativeTime: 1.5, value: 0.0)
            let fadeCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [fadeUp, fadeDown],
                relativeTime: 0.0
            )
            curves.append(fadeCurve)

            let rumble = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [baseSharpness, baseIntensity],
                relativeTime: 0.0,
                duration: 1.5
            )
            events.append(rumble)

            // Sparkly transients
            for _ in 0..<16 {
                let sharp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 2.0)
                let inten = CHHapticEventParameter(parameterID: .hapticIntensity, value: 2.0)
                let t = TimeInterval.random(in: 0.1...1.0)
                events.append(CHHapticEvent(eventType: .hapticTransient,
                                            parameters: [sharp, inten],
                                            relativeTime: t))
            }

            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)

        } catch {
            // If you still see -4809 here, it usually means the device doesn’t support a specific
            // parameter on this OS build. Remove the curve entirely (see fallback below).
            print("Haptics tap error:", error)
        }
    }
}
