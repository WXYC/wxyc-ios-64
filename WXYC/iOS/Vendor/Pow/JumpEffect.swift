//
//  Vendored from Pow — https://github.com/EmergeTools/Pow
//  Copyright (c) 2023 Emerge Tools, Inc. MIT License. See LICENSE in this directory.
//
//  Trimmed to the change-effect subset used by WXYC (DEBUG previews and unused helpers removed).
//

import SwiftUI

public extension AnyChangeEffect {
    /// An effect that makes the view jump.
    ///
    /// - Parameter height: The height of the jump.
    static func jump(height: CGFloat) -> AnyChangeEffect {
        .simulation { change in
            JumpSimulationModifier(height: height, impulseCount: change)
        }
    }
}

internal struct JumpSimulationModifier: ViewModifier, Simulative {
    var impulseCount: Int

    var initialVelocity: CGFloat = 0

    private let spring = Spring(zeta: 1 / 3, stiffness: 100 * 1)

    @State
    private var displacement: CGFloat = .zero

    @State
    private var velocity: CGFloat = 0.0

    @State
    private var jumpBuffered: Bool = false

    #if os(iOS)
    @State
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    #endif

    private var isSimulationPaused: Bool {
        velocity.isZero
    }

    private var targetHeight: Double

    init(height: Double, impulseCount: Int) {
        self.impulseCount = impulseCount

        precondition(spring.zeta < 1, "Spring must be underdamped")

        let peakTime   = spring.peakTime(initialPosition: 0, initialVelocity: 1)
        let peakHeight = spring.value(initialPosition: 0, initialVelocity: 1, at: peakTime)

        self.initialVelocity = -(height / peakHeight)
        self.targetHeight = height
    }

    public func body(content: Content) -> some View {
        TimelineView(.animation(paused: isSimulationPaused)) { context in
            content
                .modifier(SquishOffset(displacement: displacement))
                .onChange(of: context.date) { (newValue: Date) in
                    let duration = Double(newValue.timeIntervalSince(context.date))
                    withAnimation(nil) {
                        update(max(0, min(duration, 1 / 30)))
                    }
                }
        }
        #if os(iOS)
        .onChange(of: isSimulationPaused) { isPaused in
            if isPaused {
                feedbackGenerator = nil
            } else {
                feedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
                feedbackGenerator?.prepare()
            }
        }
        #endif
        .onChange(of: impulseCount) { newValue in
            withAnimation(nil) {
                if displacement > -10 {
                    velocity = -initialVelocity
                    velocity = clamp(-2 * initialVelocity, velocity, 2 * initialVelocity)
                } else if velocity < 0 {
                    jumpBuffered = true
                }
            }
        }
    }

    private func update(_ step: Double) {
        let newValue: Double
        var newVelocity: Double

        if spring.response > 0 {
            // Slow down time as the view approaches its target height for
            // additional hangtime.
            //
            // TODO: Does this mean a `Spring` is just a bad way to model this?
            let speed: Double

            if targetHeight > 32 {
                speed = (1 - 0.8 * clamp(0, -displacement / targetHeight, 1.0))
            } else {
                speed = 1
            }

            (newValue, newVelocity) = spring.value(
                from: displacement,
                to: 0,
                velocity: velocity,
                // Slow down time for a more floaty feeling.
                timestep: step * speed
            )
        } else {
            newValue = 0
            newVelocity = .zero
        }

        if displacement < 0 && newValue >= 0 {
            #if os(iOS)
            feedbackGenerator?.impactOccurred(intensity: clamp(0, newVelocity / 800, 1))
            #endif

            if jumpBuffered {
                newVelocity -= initialVelocity
                jumpBuffered = false
            }
        }

        displacement = newValue
        velocity = newVelocity

        if abs(newValue) < 0.04, newVelocity < 0.04 {
            displacement = 0
            velocity = .zero
        }
    }
}

/// A view modifier that offsets the view vertically for negative values and
/// compresses the view for positive values.
///
/// TODO: Consider merging this with `Boing`.
private struct SquishOffset: GeometryEffect {
    // In points along the y axis.
    var displacement: CGFloat = 0

    internal init(displacement: CGFloat = 0) {
        self.displacement = displacement
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let area = size.width * size.height

        var t = CGAffineTransform.identity

        if displacement < 0 {
            t = t.translatedBy(x: size.width / 2, y: size.height / 2)
            t = t.translatedBy(x: 0, y: displacement)
            t = t.translatedBy(x: -size.width / 2, y: -size.height / 2)
        }

        if displacement > 0 {
            let newHeight = rubberClamp(size.height * 0.8, size.height - displacement / 3, size.height * 1)
            let newWidth  = area / newHeight

            t = t.translatedBy(x: size.width / 2, y: size.height)
            t = t.scaledBy(x: newWidth / size.width, y: newHeight / size.height)
            t = t.translatedBy(x: -size.width / 2, y: -size.height)
        }

        return ProjectionTransform(t)
    }
}
