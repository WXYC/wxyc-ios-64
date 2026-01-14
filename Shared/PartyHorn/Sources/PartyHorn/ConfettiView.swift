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
import Combine

final class TapTrigger: ObservableObject {
    let tap = PassthroughSubject<CGPoint, Never>()
    func fire(with point: CGPoint) { tap.send(point) }
}
/// A sample view demonstrating confetti bursts.
struct ConfettiView: View {
    @ObservedObject var trigger = TapTrigger()

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
            .onReceive(trigger.tap) {
                proxy.move(to: $0)
                proxy.burst()
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
    ConfettiView()
}
