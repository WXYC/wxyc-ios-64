//
//  PlaybackButtonSwiftUI.swift
//  WXYC
//
//  SwiftUI-native implementation of PlaybackButton
//

import SwiftUI

enum PlaybackButtonSwiftUIState {
    case paused
    case playing
    
    var value: CGFloat {
        switch self {
        case .paused:
            return 1.0
        case .playing:
            return 0.0
        }
    }
}

/// A custom shape that morphs between play and pause states
struct PlaybackShape: Shape {
    var playbackValue: CGFloat // 0.0 = playing (pause icon), 1.0 = paused (play icon)
    
    var animatableData: CGFloat {
        get { playbackValue }
        set { playbackValue = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
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
        
        return path
    }
}

struct PlaybackButtonSwiftUI: View {
    @State private var playbackValue: CGFloat = 1.0 // Start in paused state
    var status: PlaybackButtonState = .paused
    var color: Color = .white
    var animationDuration: Double = 0.24
    var action: (() -> Void)?
    
    init(
        status: PlaybackButtonState = .paused,
        color: Color = .white,
        animationDuration: Double = 0.24,
        action: (() -> Void)? = nil
    ) {
        self.status = status
        self.color = color
        self.animationDuration = animationDuration
        self.action = action
        _playbackValue = State(initialValue: status.value)
    }
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            PlaybackShape(playbackValue: playbackValue)
                .fill(color)
                .aspectRatio(1.0, contentMode: .fit)
        }
        .onChange(of: status) { oldValue, newValue in
            withAnimation(.easeInOut(duration: animationDuration)) {
                playbackValue = newValue.value
            }
        }
    }
    
    /// Programmatically set the status with optional animation
    func setStatus(_ newStatus: PlaybackButtonState, animated: Bool = true) {
        if animated {
            withAnimation(.easeInOut(duration: animationDuration)) {
                playbackValue = newStatus.value
            }
        } else {
            playbackValue = newStatus.value
        }
    }
}

// MARK: - Preview
#Preview {
    PlaybackButtonExample()
        .frame(width: 100, height: 100)
    .padding()
    .background(Color.gray.opacity(0.2))
}

struct PlaybackButtonExample: View {
    @State private var status: PlaybackButtonState = .paused
    
    var body: some View {
        PlaybackButtonSwiftUI(
            status: status,
            color: .primary,
            action: {
                status = status == .paused ? .playing : .paused
            }
        )
    }
}




