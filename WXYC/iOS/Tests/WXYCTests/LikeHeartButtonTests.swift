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
}
