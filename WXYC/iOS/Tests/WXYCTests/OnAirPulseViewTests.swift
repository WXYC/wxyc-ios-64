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

#if canImport(UIKit) && !os(watchOS)
import UIKit

@Suite("OnAirPulseView", .serialized)
@MainActor
struct OnAirPulseViewTests {
    private func makeView(reduceMotion: Bool) -> OnAirPulseDotView {
        let view = OnAirPulseDotView()
        view.configure(size: 9, color: .green, blurRadius: 4.5, reduceMotion: reduceMotion)
        return view
    }

    private func installedPulse(on view: OnAirPulseDotView) -> CAAnimation? {
        view.layer.animation(forKey: OnAirPulseDotView.animationKey)
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

    // MARK: - Pulse Phase

    /// `CALayer` copies an animation when it's added, so the object read back is
    /// never the one that was handed in — but it is the layer's *stored* copy,
    /// stable across reads. That's what makes the identity assertions below mean
    /// "the same running animation" rather than "some equal animation."
    @Test("an installed animation reads back as the same object")
    func animationLookupIsStable() {
        let view = makeView(reduceMotion: false)

        #expect(installedPulse(on: view) === installedPulse(on: view))
    }

    /// The glitch a presence check can't see. SwiftUI calls `updateUIView` on
    /// every update that reaches the representable — a DJ sign-on changing the
    /// headline, the banner scrolling back into view, any environment change
    /// above it — and re-adding the animation re-seeds `beginTime`, so the dot
    /// snaps to full brightness and restarts its fade in front of the user.
    @Test("reconfiguring leaves the running pulse untouched")
    func reconfiguringPreservesThePulse() {
        let view = makeView(reduceMotion: false)
        let original = installedPulse(on: view)

        view.configure(size: 9, color: .green, blurRadius: 4.5, reduceMotion: false)

        #expect(installedPulse(on: view) === original)
    }

    /// `didBecomeActive` fires for every transient interruption that leaves the
    /// app visible — Control Center, Notification Center, the app switcher, a
    /// call banner — and none of those strip layer animations. Reinstalling on
    /// them would restart the pulse several times a session for no reason.
    @Test("a transient interruption leaves the running pulse untouched")
    func transientInterruptionPreservesThePulse() {
        let view = makeView(reduceMotion: false)
        let original = installedPulse(on: view)

        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        #expect(installedPulse(on: view) === original)
    }

    /// Backgrounding is the case that genuinely strips animations, so the dot
    /// comes back lit but frozen unless the pulse is put back.
    @Test("returning from the background reinstalls a stripped pulse")
    func returningFromBackgroundReinstallsStrippedPulse() {
        let view = makeView(reduceMotion: false)

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        view.layer.removeAllAnimations()
        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        #expect(installedPulse(on: view) != nil)
    }

    /// ...and restarts one that survived the trip but is no longer running,
    /// which a presence check alone cannot tell apart from a healthy pulse.
    @Test("returning from the background restarts a surviving pulse")
    func returningFromBackgroundRestartsSurvivingPulse() {
        let view = makeView(reduceMotion: false)
        let original = installedPulse(on: view)

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        #expect(installedPulse(on: view) !== original)
        #expect(installedPulse(on: view) != nil)
    }

    /// Leaving the view hierarchy drops animations too, so re-entering it has to
    /// put the pulse back — but re-entering with one already running must not
    /// restart it.
    @Test("entering the window reinstalls a stripped pulse")
    func enteringWindowReinstallsStrippedPulse() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = makeView(reduceMotion: false)
        view.layer.removeAllAnimations()

        window.addSubview(view)

        #expect(installedPulse(on: view) != nil)
    }

    @Test("entering the window leaves a running pulse untouched")
    func enteringWindowPreservesRunningPulse() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let view = makeView(reduceMotion: false)
        let original = installedPulse(on: view)

        window.addSubview(view)

        #expect(installedPulse(on: view) === original)
    }
}
#endif
