//
//  OnAirPulseView.swift
//  WXYC
//
//  Core Animation-backed pulse for the on-air live dot, so an idle Now Playing
//  screen can stop rendering entirely.
//
//  Created by Jake Bromberg on 08/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

// `UIViewRepresentable` and `UIView` are UIKit, but watchOS imports a UIKit that
// has neither — so `canImport` alone would send the watch target down this path.
#if canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// Hosts ``OnAirPulseDotView`` so the live dot's pulse runs on the render server.
///
/// A SwiftUI `.repeatForever` animation is stepped by SwiftUI's own animator on
/// every display refresh, which holds the ViewGraph display link open for as long
/// as it runs. The cost is not proportional to the animated view: each frame is a
/// full `ViewGraph.updateOutputsAsync` pass plus a display-list re-emit, measured
/// at 1.67% of a core on an idle screen for one 9pt dot, with CoreAnimation
/// walking the layer tree ~20 levels deep on every commit.
///
/// A `CABasicAnimation` is handed to the render server and interpolated out of
/// process. SwiftUI sees a static view, so the display link can go quiet.
struct OnAirPulseView: UIViewRepresentable {
    var size: CGFloat
    var color: Color
    var blurRadius: CGFloat
    var reduceMotion: Bool

    func makeUIView(context: Context) -> OnAirPulseDotView {
        let view = OnAirPulseDotView()
        apply(to: view)
        return view
    }

    func updateUIView(_ view: OnAirPulseDotView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: OnAirPulseDotView) {
        view.configure(
            size: size,
            color: UIColor(color),
            blurRadius: blurRadius,
            reduceMotion: reduceMotion
        )
    }
}

/// The dot itself: a circular layer with a static glow, pulsed by CoreAnimation.
///
/// The animation targets `layer.opacity`, which fades the shadow along with the
/// fill — matching the SwiftUI original, where `.opacity` wrapped `.shadow`.
final class OnAirPulseDotView: UIView {
    /// Key the pulse is installed under.
    ///
    /// Fixed rather than varying, so it doubles as the question "is a pulse
    /// already running?" — which is how ``installPulseIfNeeded()`` avoids both
    /// stacking animations and restarting the one in flight.
    static let animationKey = "onAirPulse"

    /// Opacity of the glow, matching the SwiftUI `.shadow(color: color.opacity(0.9))`.
    static let glowOpacity: Float = 0.9

    private var dotSize: CGFloat = 9
    private var reduceMotion = false

    /// Whether a trip through the background has invalidated the pulse.
    ///
    /// CoreAnimation strips a layer's animations when the app backgrounds, so
    /// the pulse has to go back on the way in or the dot returns lit but still.
    /// `didBecomeActive` is the wrong signal for that on its own: it also fires
    /// for every transient interruption that leaves the app visible — Control
    /// Center, Notification Center, the app switcher, a call banner — none of
    /// which strip anything. Reinstalling on those would restart the fade from
    /// full brightness in front of the user several times a session. This flag
    /// is what tells the two apart.
    private var animationsWereStripped = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false
        isAccessibilityElement = false

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(noteAnimationsStripped),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(restorePulseAfterBackground),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OnAirPulseDotView is created in code, never from a nib")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: dotSize, height: dotSize)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Leaving the hierarchy also drops animations.
        if window != nil { installPulseIfNeeded() }
    }

    /// Applies the dot's appearance and starts the pulse if it isn't already
    /// running. Idempotent, down to the pulse's phase — SwiftUI calls
    /// `updateUIView` freely.
    func configure(size: CGFloat, color: UIColor, blurRadius: CGFloat, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion

        if dotSize != size {
            dotSize = size
            invalidateIntrinsicContentSize()
        }

        layer.backgroundColor = color.cgColor
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = Self.glowOpacity
        layer.shadowRadius = blurRadius
        layer.shadowOffset = .zero

        installPulseIfNeeded()
    }

    /// Builds the pulse. Static and side-effect free so the shape can be asserted
    /// directly — the whole point of the CoreAnimation move is that this is the
    /// only animation in play.
    static func makePulseAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = OnAirIndicator.peakOpacity
        animation.toValue = OnAirIndicator.restingOpacity
        animation.duration = OnAirIndicator.pulseDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// Installs the pulse unless one is already running, and takes it down under
    /// Reduce Motion.
    ///
    /// Deliberately not a restart. `updateUIView` runs on every SwiftUI update
    /// that reaches the representable — a DJ sign-on changing the headline, the
    /// banner scrolling back into view, an environment change anywhere above it
    /// — and re-adding an animation re-seeds its `beginTime`, so an
    /// unconditional install would visibly snap the dot back to full brightness
    /// each time.
    private func installPulseIfNeeded() {
        guard !reduceMotion else {
            layer.removeAnimation(forKey: Self.animationKey)
            layer.opacity = Float(OnAirIndicator.peakOpacity)
            return
        }

        guard layer.animation(forKey: Self.animationKey) == nil else { return }

        layer.opacity = Float(OnAirIndicator.peakOpacity)
        layer.add(Self.makePulseAnimation(), forKey: Self.animationKey)
    }

    @objc private func noteAnimationsStripped() {
        animationsWereStripped = true
    }

    /// Restarts the pulse after a real trip through the background, and only
    /// then — see ``animationsWereStripped``.
    ///
    /// Unconditional rather than `installPulseIfNeeded()` alone, because the
    /// animation can come back as a live object that is no longer running, and
    /// a presence check can't tell that from a healthy pulse.
    @objc private func restorePulseAfterBackground() {
        guard animationsWereStripped else { return }
        animationsWereStripped = false

        layer.removeAnimation(forKey: Self.animationKey)
        installPulseIfNeeded()
    }
}
#endif
