//
//  ConfettiView.swift
//  PartyHorn
//
//  Animated confetti particle effect view.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Vortex

/// Carries burst locations from the owning UIKit view into the hosted SwiftUI
/// confetti view.
///
/// Single-consumer by construction: `taps` vends one stream, iterated by the one
/// `ConfettiView` the trigger is handed to. The owner must outlive that view —
/// `PartyHornView` holds the trigger directly rather than reaching back through
/// the hosting controller's `rootView`, so the channel cannot be detached by the
/// view struct being re-created.
@MainActor
final class TapTrigger {
    private let stream: AsyncStream<CGPoint>
    private let continuation: AsyncStream<CGPoint>.Continuation

    /// Burst locations, in the order they were fired.
    var taps: AsyncStream<CGPoint> { stream }

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func fire(with point: CGPoint) {
        continuation.yield(point)
    }

    deinit {
        continuation.finish()
    }
}

/// A sample view demonstrating confetti bursts.
struct ConfettiView: View {
    let trigger: TapTrigger

    var body: some View {
        VortexViewReader { proxy in
            VortexView(.confetti.makeUniqueCopy()) {
                Rectangle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .tag("square")
                
                Circle()
                    .fill(.white)
                    .frame(width: 16)
                    .tag("circle")
            }
            .onTapGesture { location in
                proxy.move(to: location)
                proxy.burst()
            }
            // Inside the reader, where `proxy` is in scope and valid.
            .task {
                for await point in trigger.taps {
                    proxy.move(to: point)
                    proxy.burst()
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension VortexSystem {
    /// A built-in effect that creates confetti only when a burst is triggered.
    /// Relies on "square" and "circle" tags being present – using `Rectangle`
    /// and `Circle` with frames of 16x16 works well.
    public nonisolated(unsafe) static let confetti: VortexSystem = {
        VortexSystem(
            tags: ["square", "circle"],
            birthRate: 0,
            lifespan: 4,
            speed: 0.5,
            speedVariation: 0.5,
            angleRange: .degrees(270),
            acceleration: [0, 1],
            angularSpeedVariation: [4, 4, 4],
            colors: .random(.purple, .yellow, .green, .blue, .pink, .orange, .cyan),
            size: 0.5,
            sizeVariation: 0.5
        )
    }()
}


#Preview {
    ConfettiView(trigger: TapTrigger())
}
