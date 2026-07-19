//
//  LikeHeartButton.swift
//  WXYC
//
//  The song-like heart shared by every toggle surface (#492): the playcut row's
//  trailing slot, the detail card's title line, and the Liked tab's rows. One
//  component keeps the 44pt target, glyph scale, like-red fill, pop animation,
//  and accessibility semantics identical everywhere a heart appears.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A heart toggle for liking a song. Outline (`heart`, white 80%) when unliked,
/// filled (`heart.fill`, like red) when liked, with a small pop on like that is
/// suppressed under Reduce Motion.
struct LikeHeartButton: View {
    /// The like red from the interaction study's recorded verdict
    /// (docs/ideas/artist-likes-interactions.html, `--heart: #ff5c8a`).
    static let likeColor = Color(red: 1.0, green: 92 / 255, blue: 138 / 255)

    let isLiked: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popScale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(isLiked ? Self.likeColor : Color.white.opacity(0.8))
                .scaleEffect(popScale)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "Unlike" : "Like")
        .accessibilityAddTraits(isLiked ? [.isSelected] : [])
        .onChange(of: isLiked) { _, nowLiked in
            // Pop only on the transition into liked, and only when the user
            // hasn't asked for reduced motion.
            guard nowLiked, !reduceMotion else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                popScale = 1.3
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.12)) {
                popScale = 1
            }
        }
    }
}

#Preview {
    struct HeartPreview: View {
        @State private var isLiked = false

        var body: some View {
            LikeHeartButton(isLiked: isLiked) { isLiked.toggle() }
        }
    }
    return HeartPreview()
        .padding()
        .background(.black)
}
