//
//  OnAirPulseViewTests.swift
//  WXYC
//
//  Tests over the Core Animation-backed live-dot pulse. The point of moving the
//  pulse off SwiftUI is that a `repeatForever` SwiftUI animation is stepped by
//  SwiftUI's own animator every frame, which holds the ViewGraph display link
//  open and costs a render pass over the whole view tree. A `CABasicAnimation`
//  is interpolated by the render server instead, so SwiftUI sees a static view.
//
//  That property is measured by sampling, not asserted here. What these tests
//  pin is the contract the measurement depends on: exactly one animation is
//  installed, it is the unbounded autoreversing opacity pulse, and Reduce Motion
//  installs none at all.
//
//  Created by Jake Bromberg on 08/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import WXYC

#if canImport(UIKit)
import UIKit

@Suite("OnAirPulseView")
@MainActor
struct OnAirPulseViewTests {
    private func makeView(reduceMotion: Bool) -> OnAirPulseDotView {
        let view = OnAirPulseDotView()
        view.configure(size: 9, color: .green, blurRadius: 4.5, reduceMotion: reduceMotion)
        return view
    }

    @Test("the pulse is an unbounded autoreversing opacity animation")
    func pulseAnimationShape() {
        let animation = OnAirPulseDotView.makePulseAnimation()

        #expect(animation.keyPath == "opacity")
        #expect(animation.autoreverses)
        #expect(animation.repeatCount == .infinity)
        #expect(animation.duration == OnAirIndicator.pulseDuration)
        #expect(animation.fromValue as? Double == OnAirIndicator.peakOpacity)
        #expect(animation.toValue as? Double == OnAirIndicator.restingOpacity)
    }

    @Test("configuring installs the pulse on the layer")
    func installsPulse() {
        let view = makeView(reduceMotion: false)

        #expect(view.layer.animation(forKey: OnAirPulseDotView.animationKey) != nil)
    }

    /// Reduce Motion must leave the dot lit and perfectly still — no animation
    /// object at all, not a zero-duration one.
    @Test("Reduce Motion installs no animation and pins the dot lit")
    func reduceMotionInstallsNothing() {
        let view = makeView(reduceMotion: true)

        #expect(view.layer.animation(forKey: OnAirPulseDotView.animationKey) == nil)
        #expect(view.layer.opacity == Float(OnAirIndicator.peakOpacity))
    }

    /// `updateUIView` re-runs `configure` on every SwiftUI update, so a naive
    /// implementation would stack a fresh pulse each time and drift the layer's
    /// animation list without bound.
    @Test("reconfiguring does not stack duplicate animations")
    func reconfiguringDoesNotStack() {
        let view = makeView(reduceMotion: false)

        for _ in 0..<5 {
            view.configure(size: 9, color: .green, blurRadius: 4.5, reduceMotion: false)
        }

        #expect(view.layer.animationKeys()?.count == 1)
    }

    @Test("turning Reduce Motion on removes an already-installed pulse")
    func reduceMotionRemovesExistingPulse() {
        let view = makeView(reduceMotion: false)
        #expect(view.layer.animation(forKey: OnAirPulseDotView.animationKey) != nil)

        view.configure(size: 9, color: .green, blurRadius: 4.5, reduceMotion: true)

        #expect(view.layer.animation(forKey: OnAirPulseDotView.animationKey) == nil)
    }
}
#endif
