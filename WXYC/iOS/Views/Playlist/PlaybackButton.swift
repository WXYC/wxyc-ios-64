//
//  PlaybackButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import CoreGraphics
import Core
import WXUI
import PlayerHeaderView
import Playback

struct PlaybackShape: InsettableShape {
    var playbackValue: CGFloat   // 0.0 = playing (pause), 1.0 = paused (play)
    var insetAmount: CGFloat = 0
    var cornerRadius: CGFloat = 3
    
    var animatableData: CGFloat {
        get { playbackValue }
        set { playbackValue = newValue }
    }
    
    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
    
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        
        return Path { path in
            let halfWidth = r.width / 2.0
            let eighthWidth = halfWidth / 2.0
            let sixteenthWidth: CGFloat = eighthWidth / 2.0
            let thirtySecondWidth: CGFloat = sixteenthWidth / 2.0
            
            let componentWidth: CGFloat = sixteenthWidth * (1 + playbackValue)
            let insetMargin: CGFloat = thirtySecondWidth * (1 - playbackValue)
            
            let firstHalfMargin: CGFloat = r.minX + eighthWidth + insetMargin
            let secondHalfMargin = r.minX + halfWidth + insetMargin
            
            let halfHeight = r.height / 2.0
            let quarterHeight: CGFloat = halfHeight / 2.0
            let sixteenthHeight: CGFloat = halfHeight / 4.0
            
            let h1: CGFloat = sixteenthHeight * playbackValue
            let h2: CGFloat = quarterHeight * playbackValue
            
            let maxRadius = min(cornerRadius, componentWidth * 0.3, halfHeight * 0.1)
            
            // First bar corners
            let tl1 = CGPoint(x: firstHalfMargin, y: r.minY + quarterHeight)
            let tr1 = CGPoint(x: firstHalfMargin + componentWidth, y: r.minY + quarterHeight + h1)
            let br1 = CGPoint(x: firstHalfMargin + componentWidth, y: r.minY + quarterHeight + halfHeight - h1)
            let bl1 = CGPoint(x: firstHalfMargin, y: r.minY + quarterHeight + halfHeight)
            
            // First bar - round left corners, sharp right when triangle
            path.move(to: CGPoint(x: tl1.x, y: tl1.y + maxRadius))
            path.addQuadCurve(to: CGPoint(x: tl1.x + maxRadius, y: tl1.y), control: tl1)
            
            if playbackValue < 0.9 {
                path.addLine(to: CGPoint(x: tr1.x - maxRadius, y: tr1.y))
                path.addQuadCurve(to: CGPoint(x: tr1.x, y: tr1.y + maxRadius), control: tr1)
                path.addLine(to: CGPoint(x: br1.x, y: br1.y - maxRadius))
                path.addQuadCurve(to: CGPoint(x: br1.x - maxRadius, y: br1.y), control: br1)
            } else {
                path.addLine(to: tr1)
                path.addLine(to: br1)
            }
            
            path.addLine(to: CGPoint(x: bl1.x + maxRadius, y: bl1.y))
            path.addQuadCurve(to: CGPoint(x: bl1.x, y: bl1.y - maxRadius), control: bl1)
            
            path.closeSubpath()
            
            // Second bar
            let tl2 = CGPoint(x: secondHalfMargin, y: r.minY + quarterHeight + h1)
            let tr2 = CGPoint(x: secondHalfMargin + componentWidth, y: r.minY + quarterHeight + h2)
            let br2 = CGPoint(x: secondHalfMargin + componentWidth, y: r.minY + quarterHeight + halfHeight - h2)
            let bl2 = CGPoint(x: secondHalfMargin, y: r.minY + quarterHeight + halfHeight - h1)
            
            if playbackValue < 0.9 {
                path.move(to: CGPoint(x: tl2.x, y: tl2.y + maxRadius))
                path.addQuadCurve(to: CGPoint(x: tl2.x + maxRadius, y: tl2.y), control: tl2)
                path.addLine(to: CGPoint(x: tr2.x - maxRadius, y: tr2.y))
                path.addQuadCurve(to: CGPoint(x: tr2.x, y: tr2.y + maxRadius), control: tr2)
                path.addLine(to: CGPoint(x: br2.x, y: br2.y - maxRadius))
                path.addQuadCurve(to: CGPoint(x: br2.x - maxRadius, y: br2.y), control: br2)
                path.addLine(to: CGPoint(x: bl2.x + maxRadius, y: bl2.y))
                path.addQuadCurve(to: CGPoint(x: bl2.x, y: bl2.y - maxRadius), control: bl2)
            } else {
                // Triangle mode
                path.move(to: tl2)
                
                // Small rounded tip - cut into triangle slightly
                let tipRadius = min(maxRadius * 0.5, 2.0)
                
                path.addLine(to: CGPoint(x: tr2.x - tipRadius, y: tr2.y))
                path.addQuadCurve(to: CGPoint(x: tr2.x - tipRadius, y: br2.y),
                                  control: CGPoint(x: tr2.x, y: (tr2.y + br2.y) / 2))
                path.addLine(to: bl2)
            }
            
            path.closeSubpath()
        }
    }
}

struct PlaybackButton: View {
    @State private var isPlaying: Bool = AudioPlayerController.shared.isPlaying
    @State private var isExpanded = false

    var brightness: Double
    var alpha: Double
    var animationDuration: Double
    var action: (() -> Void)?

    init(
        brightness: Double = 1.0,
        alpha: Double = 1.0,
        animationDuration: Double = 0.24,
        action: (() -> Void)? = nil
    ) {
        self.brightness = brightness
        self.alpha = alpha
        self.animationDuration = animationDuration
        self.action = action
    }

    private var buttonColor: Color {
        Color(white: brightness, opacity: alpha)
    }

    var body: some View {
        Button(action: {
            action?()
        }) {
            PlaybackShape(playbackValue: isPlaying ? 0.0 : 1.0)
                .fill(buttonColor)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .animation(.spring(), value: isExpanded)
        .task {
            let observation = Observations {
                AudioPlayerController.shared.isPlaying
            }
            
            for await newIsPlaying in observation {
                withAnimation(.easeInOut(duration: animationDuration)) {
                    isPlaying = newIsPlaying
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    PlaybackButtonExample()
        .frame(width: 100, height: 100)
        .padding()
}

enum PlaybackButtonState {
    case playing
    case paused
}

struct PlaybackButtonExample: View {
    @State private var status: PlaybackButtonState = .paused
    
    var body: some View {
        PlaybackButton(
            action: {
                status = (status == .paused) ? .playing : .paused
            }
        )
        .background(WXYCBackground())
    }
}

struct HoleCutout<S: Shape>: Shape, Animatable {
    var hole: S

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addPath(hole.path(in: rect))
        return path
    }
}

struct NoHighlightButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label   // exactly the same, pressed or not
    }
}
