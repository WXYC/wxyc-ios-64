//
//  WipeDownRevealModifier.swift
//  PartyHorn
//
//  Created by Jake Bromberg on 12/2/25.
//

import SwiftUI

import SwiftUI

struct WipeModifier: ViewModifier {
    enum Direction {
        case topToBottom
        case bottomToTop
    }

    let duration: Double
    let direction: Direction

    @State private var progress: CGFloat = 0   // 0 = hidden, 1 = fully revealed

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let height = proxy.size.height

            ZStack {
                content
                    .mask(
                        Rectangle()
                            .frame(height: height * progress)
                            .frame(maxHeight: .infinity, alignment: alignmentForMask)
                    )
            }
            .onAppear {
                withAnimation(.easeInOut(duration: duration)) {
                    progress = 1
                }
            }
        }
    }

    private var alignmentForMask: Alignment {
        switch direction {
        case .topToBottom: return .top
        case .bottomToTop: return .bottom
        }
    }
}

extension View {
    func wipe(
        direction: WipeModifier.Direction = .topToBottom,
        duration: Double = 0.8
    ) -> some View {
        modifier(WipeModifier(
            duration: duration,
            direction: direction
        ))
    }
}
