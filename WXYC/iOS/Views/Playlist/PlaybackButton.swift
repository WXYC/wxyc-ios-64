//
//  PlaybackButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core

/// A custom shape that morphs between play and pause states
struct PlaybackShape: Shape {
    var playbackValue: CGFloat // 0.0 = playing (pause icon), 1.0 = paused (play icon)
    
    var animatableData: CGFloat {
        get { playbackValue }
        set { playbackValue = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        return Path { path in
            let halfWidth = rect.width / 2.0
            let eighthWidth = halfWidth / 2.0
            let sixteenthWidth: CGFloat = eighthWidth / 2.0
            let thirtySecondWidth: CGFloat = sixteenthWidth / 2.0
            
            let componentWidth: CGFloat = sixteenthWidth * (1 + playbackValue)
            let insetMargin: CGFloat = thirtySecondWidth * (1 - playbackValue)
            
            let firstHalfMargin: CGFloat = eighthWidth + insetMargin
            let secondHalfMargin = halfWidth + insetMargin
            
            let halfHeight = rect.height / 2.0
            let quarterHeight: CGFloat = halfHeight / 2.0
            let sixteenthHeight: CGFloat = halfHeight / 4.0
            
            let h1: CGFloat = sixteenthHeight * playbackValue
            let h2: CGFloat = quarterHeight * playbackValue
            
            // First bar (left side)
            path.move(to: CGPoint(x: firstHalfMargin, y: quarterHeight))
            path.addLine(to: CGPoint(x: firstHalfMargin + componentWidth, y: quarterHeight + h1))
            path.addLine(to: CGPoint(x: firstHalfMargin + componentWidth, y: quarterHeight + halfHeight - h1))
            path.addLine(to: CGPoint(x: firstHalfMargin, y: quarterHeight + halfHeight))
            path.closeSubpath()
            
            // Second bar (right side)
            path.move(to: CGPoint(x: secondHalfMargin, y: quarterHeight + h1))
            path.addLine(to: CGPoint(x: secondHalfMargin + componentWidth, y: quarterHeight + h2))
            path.addLine(to: CGPoint(x: secondHalfMargin + componentWidth, y: quarterHeight + halfHeight - h2))
            path.addLine(to: CGPoint(x: secondHalfMargin, y: quarterHeight + halfHeight - h1))
            path.closeSubpath()
        }
    }
}

struct PlaybackButton: View {
    @State private var isPlaying: Bool = RadioPlayerController.shared.isPlaying
    
    var colorScheme: ColorScheme?
    var animationDuration: Double
    var action: (() -> Void)?
    
    init(
        colorScheme: ColorScheme? = nil,
        animationDuration: Double = 0.24,
        action: (() -> Void)? = nil
    ) {
        self.colorScheme = colorScheme
        self.animationDuration = animationDuration
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            if let colorScheme {
                switch colorScheme {
                case .light:
                    PlaybackShape(playbackValue: isPlaying ? 0.0 : 1.0)
                        .fill(Color(red: 57 / 255, green: 56 / 255, blue: 57 / 255))
                        .preferredColorScheme(colorScheme)
                case .dark:
                    PlaybackShape(playbackValue: isPlaying ? 0.0 : 1.0)
                        .preferredColorScheme(colorScheme)
                @unknown default:
                    PlaybackShape(playbackValue: isPlaying ? 0.0 : 1.0)
                        .fill(.ultraThickMaterial)
                }
            } else {
                PlaybackShape(playbackValue: isPlaying ? 0.0 : 1.0)
                    .fill(.ultraThickMaterial)
            }
        }
        .buttonStyle(NoHighlightButtonStyle())
        .task {
            // Observe playback state changes from RadioPlayerController
            let observation = Observations {
                RadioPlayerController.shared.isPlaying
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
        ZStack {
            Image("background")
                .resizable()
            
            PlaybackButton(
                action: {
                    status = status == .paused ? .playing : .paused
                }
            )
        }
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

struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label   // exactly the same, pressed or not
    }
}
