//
//  LikeHeartButton.swift
//  WXYC
//
//  The song-like heart shared by every toggle surface (#492): the playcut row's
//  trailing slot, the detail card's title line, and the Liked tab's rows. One
//  component keeps the 44pt target, glyph scale, like-red fill, celebratory
//  burst, and accessibility semantics identical everywhere a heart appears.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A heart toggle for liking a song. Outline (`heart`, white 80%) when unliked,
/// filled (`heart.fill`, like red) when liked. Crossing *into* liked fires a
/// spray of hearts plus a springy jump (with their built-in haptics), all
/// suppressed under Reduce Motion.
struct LikeHeartButton: View {
    /// The like red from the interaction study's recorded verdict
    /// (docs/ideas/artist-likes-interactions.html, `--heart: #ff5c8a`).
    static let likeColor = Color(red: 1.0, green: 92 / 255, blue: 138 / 255)

    let isLiked: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A monotonic counter the change-effects watch. Incrementing it once per
    /// like-crossing fires exactly one burst; it never changes on unlike or
    /// under Reduce Motion, so those transitions stay silent.
    @State private var celebration = 0

    /// Whether a like transition should fire the celebratory burst. The burst
    /// belongs only to the moment a song crosses *into* the liked state, and
    /// never when the user has asked for reduced motion.
    static func shouldCelebrate(from wasLiked: Bool, to nowLiked: Bool, reduceMotion: Bool) -> Bool {
        nowLiked && !wasLiked && !reduceMotion
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(isLiked ? Self.likeColor : Color.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "Unlike" : "Like")
        .accessibilityAddTraits(isLiked ? [.isSelected] : [])
        .changeEffect(.spray(origin: .center) { sprayHeart }, value: celebration)
        .changeEffect(.jump(height: 12), value: celebration)
        .onChange(of: isLiked) { wasLiked, nowLiked in
            if Self.shouldCelebrate(from: wasLiked, to: nowLiked, reduceMotion: reduceMotion) {
                celebration += 1
            }
        }
    }

    /// The particle the spray emits. Pow draws several of these per burst and
    /// jitters each one's brightness, so a single like-red heart yields a range
    /// of shades without us enumerating sizes.
    private var sprayHeart: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(Self.likeColor)
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
