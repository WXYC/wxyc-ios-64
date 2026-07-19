//
//  OnAirDebugState.swift
//  DebugPanel
//
//  Observable singleton for forcing the playlist "on air" banner to display during testing.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

/// Shared debug state for the playlist "on air" banner.
///
/// Lets you preview the banner between DJs (when no sign-on is present in the flowsheet)
/// and tune its indicator, DJ-handle typography, and spacing live.
@MainActor
@Observable
public final class OnAirDebugState {
    public static let shared = OnAirDebugState()

    /// When true, the playlist shows the on-air banner with a placeholder DJ even when
    /// no one is currently signed on.
    public var forceOnAir: Bool {
        didSet {
            UserDefaults.standard.set(forceOnAir, forKey: "OnAirDebug.forceOnAir")
        }
    }

    /// The DJ handle shown when ``forceOnAir`` is on — editable so the adaptive
    /// width-condensing can be tried against handles of any length.
    public var forcedDJName: String {
        didSet {
            UserDefaults.standard.set(forcedDJName, forKey: "OnAirDebug.forcedDJName")
        }
    }

    // MARK: - Adaptive handle width

    /// Whether the DJ handle condenses its width axis to fit one line beside the
    /// say-hi chip (on) or renders at the fixed ``handleWidth`` (off).
    public var adaptiveWidth: Bool {
        didSet {
            UserDefaults.standard.set(adaptiveWidth, forKey: "OnAirDebug.adaptiveWidth")
        }
    }

    /// The narrowest `wdth` axis the adaptive fit will use before the handle
    /// wraps, `30...150`.
    public var handleWidthFloor: Double {
        didSet {
            UserDefaults.standard.set(handleWidthFloor, forKey: "OnAirDebug.handleWidthFloor")
        }
    }

    // MARK: - Say Hi chip

    /// Opacity of the say-hi chip's green glass tint, `0...1` — the capsule
    /// background transparency. The chip's text and icon stay opaque.
    public var sayHiTintOpacity: Double {
        didSet {
            UserDefaults.standard.set(sayHiTintOpacity, forKey: "OnAirDebug.sayHiTintOpacity")
        }
    }

    // MARK: - "ON AIR" indicator theme

    /// Hue of the "ON AIR" indicator, `0...1`. Combined with ``indicatorSaturation`` and
    /// ``indicatorLightness`` into an ``HSL`` color at the view layer.
    public var indicatorHue: Double {
        didSet { UserDefaults.standard.set(indicatorHue, forKey: "OnAirDebug.indicatorHue") }
    }

    /// Saturation of the "ON AIR" indicator, `0...1`.
    public var indicatorSaturation: Double {
        didSet { UserDefaults.standard.set(indicatorSaturation, forKey: "OnAirDebug.indicatorSaturation") }
    }

    /// Lightness of the "ON AIR" indicator, `0...1`.
    public var indicatorLightness: Double {
        didSet { UserDefaults.standard.set(indicatorLightness, forKey: "OnAirDebug.indicatorLightness") }
    }

    /// Blur radius of the indicator's glow, in points.
    public var indicatorBlurRadius: Double {
        didSet { UserDefaults.standard.set(indicatorBlurRadius, forKey: "OnAirDebug.indicatorBlurRadius") }
    }

    // MARK: - DJ handle typography (SF Pro variable-font axes)

    /// SF Pro `wght` (Weight) axis for the DJ handle, `1...1000`.
    public var handleWeight: Double {
        didSet { UserDefaults.standard.set(handleWeight, forKey: "OnAirDebug.handleWght") }
    }

    /// SF Pro `wdth` (Width) axis, `30...150`.
    public var handleWidth: Double {
        didSet { UserDefaults.standard.set(handleWidth, forKey: "OnAirDebug.handleWdth") }
    }

    /// SF Pro `opsz` (Optical Size) axis, `17...96`.
    public var handleOpticalSize: Double {
        didSet { UserDefaults.standard.set(handleOpticalSize, forKey: "OnAirDebug.handleOpsz") }
    }

    /// SF Pro `GRAD` (Grade) axis, `400...1000`.
    public var handleGrade: Double {
        didSet { UserDefaults.standard.set(handleGrade, forKey: "OnAirDebug.handleGrad") }
    }

    // MARK: - Banner spacing

    /// Vertical space between the "ON AIR" eyebrow and the DJ handle, in points.
    public var onAirSpacing: Double {
        didSet { UserDefaults.standard.set(onAirSpacing, forKey: "OnAirDebug.onAirSpacing") }
    }

    /// Line spacing applied to the DJ handle, in points (affects wrapped handles).
    public var handleLineSpacing: Double {
        didSet { UserDefaults.standard.set(handleLineSpacing, forKey: "OnAirDebug.handleLineSpacing") }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.forceOnAir = defaults.bool(forKey: "OnAirDebug.forceOnAir")
        self.forcedDJName = defaults.string(forKey: "OnAirDebug.forcedDJName") ?? "DJ HOUNDSTOOTH"
        self.adaptiveWidth = defaults.object(forKey: "OnAirDebug.adaptiveWidth") as? Bool ?? true
        self.handleWidthFloor = defaults.object(forKey: "OnAirDebug.handleWidthFloor") as? Double ?? 50
        self.sayHiTintOpacity = defaults.object(forKey: "OnAirDebug.sayHiTintOpacity") as? Double ?? 0.75
        self.indicatorHue = defaults.object(forKey: "OnAirDebug.indicatorHue") as? Double ?? 0.33
        self.indicatorSaturation = defaults.object(forKey: "OnAirDebug.indicatorSaturation") as? Double ?? 1.0
        self.indicatorLightness = defaults.object(forKey: "OnAirDebug.indicatorLightness") as? Double ?? 0.5
        self.indicatorBlurRadius = defaults.object(forKey: "OnAirDebug.indicatorBlurRadius") as? Double ?? 4.5
        self.handleWeight = defaults.object(forKey: "OnAirDebug.handleWght") as? Double ?? SFProFontAxis.weight.defaultValue
        self.handleWidth = defaults.object(forKey: "OnAirDebug.handleWdth") as? Double ?? SFProFontAxis.width.defaultValue
        self.handleOpticalSize = defaults.object(forKey: "OnAirDebug.handleOpsz") as? Double ?? SFProFontAxis.opticalSize.defaultValue
        self.handleGrade = defaults.object(forKey: "OnAirDebug.handleGrad") as? Double ?? SFProFontAxis.grade.defaultValue
        self.onAirSpacing = defaults.object(forKey: "OnAirDebug.onAirSpacing") as? Double ?? 0.0
        self.handleLineSpacing = defaults.object(forKey: "OnAirDebug.handleLineSpacing") as? Double ?? 0.0
    }
}
