//
//  LikeHeartButtonTests.swift
//  WXYC
//
//  Guards the celebratory-burst gate on the like heart: the spray + jump fire
//  only when a song crosses *into* the liked state, never on unlike, and never
//  when the user has asked for reduced motion.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("LikeHeartButton celebration gate")
struct LikeHeartButtonTests {
    @Test("Crossing into liked with motion allowed celebrates")
    func intoLikedCelebrates() {
        #expect(LikeHeartButton.shouldCelebrate(from: false, to: true, reduceMotion: false))
    }

    @Test("Unliking never celebrates")
    func unlikeDoesNotCelebrate() {
        #expect(LikeHeartButton.shouldCelebrate(from: true, to: false, reduceMotion: false) == false)
    }

    @Test("Reduce Motion suppresses the burst even when liking")
    func reduceMotionSuppresses() {
        #expect(LikeHeartButton.shouldCelebrate(from: false, to: true, reduceMotion: true) == false)
    }

    @Test("Staying liked does not re-fire the burst")
    func stayingLikedDoesNotCelebrate() {
        #expect(LikeHeartButton.shouldCelebrate(from: true, to: true, reduceMotion: false) == false)
    }

    /// The `.chrome` frame belongs only to the detail cover, where the heart sits
    /// parallel with the back button. Every other surface (the row's trailing
    /// slot, the Liked tab) must keep the bare 44pt glyph, so the default has to
    /// stay `.bare` — a flipped default would frost a circle behind every heart.
    @Test("Style defaults to bare so non-chrome surfaces stay unframed")
    func styleDefaultsToBare() {
        let button = LikeHeartButton(isLiked: false, action: {})
        guard case .bare = button.style else {
            Issue.record("Expected default style .bare, got \(button.style)")
            return
        }
    }
}
