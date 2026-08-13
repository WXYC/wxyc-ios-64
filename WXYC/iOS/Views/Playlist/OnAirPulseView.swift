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

#if canImport(UIKit)
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
    /// Key the pulse is installed under. Re-adding under the same key replaces
    /// rather than stacks, which is what keeps ``configure(size:color:blurRadius:reduceMotion:)``
    /// idempotent across SwiftUI's repeated `updateUIView` calls.
    static let animationKey = "onAirPulse"

    /// Opacity of the glow, matching the SwiftUI `.shadow(color: color.opacity(0.9))`.
    static let glowOpacity: Float = 0.9

    private var dotSize: CGFloat = 9
    private var reduceMotion = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false
        isAccessibilityElement = false

        // CoreAnimation strips a layer's animations when the app backgrounds, so
        // the pulse has to be reinstalled on the way back in or the dot returns
        // frozen at whatever opacity it was interrupted at.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyPulse),
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
        // Re-entering the hierarchy also drops animations.
        if window != nil { applyPulse() }
    }

    /// Applies the dot's appearance and (re)installs the pulse. Idempotent —
    /// SwiftUI calls `updateUIView` freely.
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

        applyPulse()
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

    @objc private func applyPulse() {
        layer.removeAnimation(forKey: Self.animationKey)
        layer.opacity = Float(OnAirIndicator.peakOpacity)

        guard !reduceMotion else { return }
        layer.add(Self.makePulseAnimation(), forKey: Self.animationKey)
    }
}
#endif
