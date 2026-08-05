//
//  RoutePickerButton.swift
//  WXYC
//
//  SwiftUI wrapper over AVRoutePickerView, the only supported way to present the
//  system output picker.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AVKit
import SwiftUI

/// A tap surface that opens the system audio-output picker.
///
/// `AVRoutePickerView` exposes no API to present the picker programmatically —
/// it *is* the button and handles its own tap, so there is no action closure to
/// hand a SwiftUI `Button`. Rather than poke at its internals, this stretches
/// the real picker across the target area and draws the visible row underneath
/// it, so the touch it receives is a genuine one.
///
/// Measured on iOS 27.0 (2026-08-04): the picker's internal `UIButton` fills the
/// view's bounds at every size tested (44 / 160 / 329pt), `hitTest` resolves to
/// that button across 100% of the width, and `tintColor = .clear` renders zero
/// pixels. Those three facts are what make the overlay approach work; if a
/// future SDK changes any of them the row goes dead, so
/// `RoutePickerButtonTests` pins the first and third.
struct RoutePickerButton: UIViewRepresentable {
    /// Glyph tint when no external route is active. `.clear` hides the glyph
    /// entirely, for use as an invisible tap layer.
    var tint: Color = .clear

    /// Glyph tint while a route is active.
    var activeTint: Color = .clear

    /// Replaces the picker's built-in "AirPlay" label so VoiceOver reads the row.
    var accessibilityLabel: String?

    /// The current destination, read after the label.
    var accessibilityValue: String?

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "airPlayRouteButton"
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(activeTint)
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityValue = accessibilityValue
    }
}
