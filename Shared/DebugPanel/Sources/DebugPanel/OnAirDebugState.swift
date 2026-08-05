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

#if DEBUG
/// Shared debug state for the playlist "on air" banner.
///
/// Lets you preview the banner between DJs (when no sign-on is present in the flowsheet)
/// and tune its indicator, DJ-handle typography, and spacing live.
///
/// Every persisted property writes through ``persist(_:forKey:)`` to a key in ``Keys`` —
/// a single write-through helper rather than a property wrapper, because `@Observable`
/// synthesizes its own storage for stored properties and a wrapper can't layer on top
/// of that (WXYC/wxyc-ios-64#752).
///
/// Wrapped in `#if DEBUG` rather than left reachable-but-unused: both of its consumers
/// (``OnAirBannerTheme/debugOverride`` and `OnAirBannerDebugView`) are already compile-gated
/// the same way, so this removes the type from the Release binary outright instead of
/// merely leaving it uncalled there. `Debug TestFlight` defines `DEBUG` too, so the debug
/// panel is unaffected.
@MainActor
@Observable
public final class OnAirDebugState {
    public static let shared = OnAirDebugState()

    /// When true, the playlist shows the on-air banner with a placeholder DJ even when
    /// no one is currently signed on.
    public var forceOnAir: Bool {
        didSet { persist(forceOnAir, forKey: Keys.forceOnAir) }
    }

    /// The DJ handle shown when ``forceOnAir`` is on — editable so the adaptive
    /// width-condensing can be tried against handles of any length.
    public var forcedDJName: String {
        didSet { persist(forcedDJName, forKey: Keys.forcedDJName) }
    }

    // MARK: - Adaptive handle width

    /// Whether the DJ handle condenses its width axis to fit one line beside the
    /// say-hi chip (on) or renders at the fixed ``handleWidth`` (off).
    public var adaptiveWidth: Bool {
        didSet { persist(adaptiveWidth, forKey: Keys.adaptiveWidth) }
    }

    /// The narrowest `wdth` axis the adaptive fit will use before the handle
    /// wraps, `30...150`.
    public var handleWidthFloor: Double {
        didSet { persist(handleWidthFloor, forKey: Keys.handleWidthFloor) }
    }

    // MARK: - Say Hi chip

    /// Opacity of the say-hi chip's green glass tint, `0...1` — the capsule
    /// background transparency. The chip's text and icon stay opaque.
    public var requestLineTintOpacity: Double {
        didSet { persist(requestLineTintOpacity, forKey: Keys.requestLineTintOpacity) }
    }

    // MARK: - "ON AIR" indicator theme

    /// Hue of the "ON AIR" indicator, `0...1`. Combined with ``indicatorSaturation`` and
    /// ``indicatorLightness`` into an ``HSL`` color at the view layer.
    public var indicatorHue: Double {
        didSet { persist(indicatorHue, forKey: Keys.indicatorHue) }
    }

    /// Saturation of the "ON AIR" indicator, `0...1`.
    public var indicatorSaturation: Double {
        didSet { persist(indicatorSaturation, forKey: Keys.indicatorSaturation) }
    }

    /// Lightness of the "ON AIR" indicator, `0...1`.
    public var indicatorLightness: Double {
        didSet { persist(indicatorLightness, forKey: Keys.indicatorLightness) }
    }

    /// Blur radius of the indicator's glow, in points.
    public var indicatorBlurRadius: Double {
        didSet { persist(indicatorBlurRadius, forKey: Keys.indicatorBlurRadius) }
    }

    // MARK: - DJ handle typography (SF Pro variable-font axes)

    /// SF Pro `wght` (Weight) axis for the DJ handle, `1...1000`.
    public var handleWeight: Double {
        didSet { persist(handleWeight, forKey: Keys.handleWeight) }
    }

    /// SF Pro `wdth` (Width) axis, `30...150`.
    public var handleWidth: Double {
        didSet { persist(handleWidth, forKey: Keys.handleWidth) }
    }

    /// SF Pro `opsz` (Optical Size) axis, `17...96`.
    public var handleOpticalSize: Double {
        didSet { persist(handleOpticalSize, forKey: Keys.handleOpticalSize) }
    }

    /// SF Pro `GRAD` (Grade) axis, `400...1000`.
    public var handleGrade: Double {
        didSet { persist(handleGrade, forKey: Keys.handleGrade) }
    }

    // MARK: - Banner spacing

    /// Vertical space between the "ON AIR" eyebrow and the DJ handle, in points.
    public var onAirSpacing: Double {
        didSet { persist(onAirSpacing, forKey: Keys.onAirSpacing) }
    }

    /// Line spacing applied to the DJ handle, in points (affects wrapped handles).
    public var handleLineSpacing: Double {
        didSet { persist(handleLineSpacing, forKey: Keys.handleLineSpacing) }
    }

    // MARK: - DJ handle grade wave

    /// Whether the handle plays its one-shot grade wave on appear / handle change.
    public var waveEnabled: Bool {
        didSet { persist(waveEnabled, forKey: Keys.waveEnabled) }
    }

    /// Duration of one handle-wave sweep, in seconds.
    public var waveDuration: Double {
        didSet { persist(waveDuration, forKey: Keys.waveDuration) }
    }

    /// How far the wave lightens a letter's grade at the crest peak (`0` is off).
    public var waveDepth: Double {
        didSet { persist(waveDepth, forKey: Keys.waveDepth) }
    }

    /// How far the wave also thins a letter's weight at the crest peak, for a much
    /// thinner crest than grade alone reaches (`0` leaves weight alone).
    public var waveWeightDepth: Double {
        didSet { persist(waveWeightDepth, forKey: Keys.waveWeightDepth) }
    }

    /// The wave crest's half-width as a fraction of the handle, `(0, 1]`.
    public var waveCrestHalfWidth: Double {
        didSet { persist(waveCrestHalfWidth, forKey: Keys.waveCrestHalfWidth) }
    }

    /// How many times the crest sweeps across the handle per animation, `1...5`.
    /// Stored as a `Double` for the slider; the banner rounds it to a whole count.
    public var waveRepetitions: Double {
        didSet { persist(waveRepetitions, forKey: Keys.waveRepetitions) }
    }

    /// The launch interval between consecutive crests, as a fraction of one sweep,
    /// `0.1...1`. Lower values overlap the crests for a snappier train.
    public var waveSpacing: Double {
        didSet { persist(waveSpacing, forKey: Keys.waveSpacing) }
    }

    /// A transient replay token bumped by the debug "Play wave" button to re-run
    /// the animation on demand. Not persisted — it's a one-shot UI event.
    public var waveReplayToken: Int = 0

    /// `UserDefaults` keys for every persisted property above, gathered in one place
    /// rather than declared inline at each `didSet` (WXYC/wxyc-ios-64#752). Values are
    /// load-bearing: they're already written to real devices, so changing one resets
    /// that tester's tuned banner back to the shipping default.
    private enum Keys {
        static let forceOnAir = "OnAirDebug.forceOnAir"
        static let forcedDJName = "OnAirDebug.forcedDJName"
        static let adaptiveWidth = "OnAirDebug.adaptiveWidth"
        static let handleWidthFloor = "OnAirDebug.handleWidthFloor"
        static let requestLineTintOpacity = "OnAirDebug.requestLineTintOpacity"
        static let indicatorHue = "OnAirDebug.indicatorHue"
        static let indicatorSaturation = "OnAirDebug.indicatorSaturation"
        static let indicatorLightness = "OnAirDebug.indicatorLightness"
        static let indicatorBlurRadius = "OnAirDebug.indicatorBlurRadius"
        static let handleWeight = "OnAirDebug.handleWght"
        static let handleWidth = "OnAirDebug.handleWdth"
        static let handleOpticalSize = "OnAirDebug.handleOpsz"
        static let handleGrade = "OnAirDebug.handleGrad"
        static let onAirSpacing = "OnAirDebug.onAirSpacing"
        static let handleLineSpacing = "OnAirDebug.handleLineSpacing"
        static let waveEnabled = "OnAirDebug.waveEnabled"
        static let waveDuration = "OnAirDebug.waveDuration"
        static let waveDepth = "OnAirDebug.waveDepth"
        static let waveWeightDepth = "OnAirDebug.waveWeightDepth"
        static let waveCrestHalfWidth = "OnAirDebug.waveCrestHalfWidth"
        static let waveRepetitions = "OnAirDebug.waveRepetitions"
        static let waveSpacing = "OnAirDebug.waveSpacing"
    }

    /// Writes `value` to `UserDefaults.standard` under `key` — the shared write-through
    /// every persisted property's `didSet` calls. A plain method rather than a property
    /// wrapper: see the type-level doc comment for why a wrapper isn't an option here.
    /// Constrained to ``PersistableDebugValue`` (the `Bool`/`Double`/`String` this type's
    /// properties actually use) so it stays as type-safe as the individual
    /// `set(_:forKey:)` calls it replaced, rather than silently widening to `Any?`.
    private func persist<Value: PersistableDebugValue>(_ value: Value, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private init() {
        let defaults = UserDefaults.standard
        self.forceOnAir = defaults.bool(forKey: Keys.forceOnAir)
        self.forcedDJName = defaults.string(forKey: Keys.forcedDJName) ?? "DJ HOUNDSTOOTH"
        self.adaptiveWidth = defaults.object(forKey: Keys.adaptiveWidth) as? Bool ?? true
        self.handleWidthFloor = defaults.object(forKey: Keys.handleWidthFloor) as? Double ?? 50
        self.requestLineTintOpacity = defaults.object(forKey: Keys.requestLineTintOpacity) as? Double ?? 0.75
        self.indicatorHue = defaults.object(forKey: Keys.indicatorHue) as? Double ?? 0.33
        self.indicatorSaturation = defaults.object(forKey: Keys.indicatorSaturation) as? Double ?? 1.0
        self.indicatorLightness = defaults.object(forKey: Keys.indicatorLightness) as? Double ?? 0.5
        self.indicatorBlurRadius = defaults.object(forKey: Keys.indicatorBlurRadius) as? Double ?? 4.5
        self.handleWeight = defaults.object(forKey: Keys.handleWeight) as? Double ?? SFProFontAxis.weight.defaultValue
        self.handleWidth = defaults.object(forKey: Keys.handleWidth) as? Double ?? SFProFontAxis.width.defaultValue
        self.handleOpticalSize = defaults.object(forKey: Keys.handleOpticalSize) as? Double ?? SFProFontAxis.opticalSize.defaultValue
        self.handleGrade = defaults.object(forKey: Keys.handleGrade) as? Double ?? SFProFontAxis.grade.defaultValue
        self.onAirSpacing = defaults.object(forKey: Keys.onAirSpacing) as? Double ?? 0.0
        self.handleLineSpacing = defaults.object(forKey: Keys.handleLineSpacing) as? Double ?? 0.0
        self.waveEnabled = defaults.object(forKey: Keys.waveEnabled) as? Bool ?? true
        self.waveDuration = defaults.object(forKey: Keys.waveDuration) as? Double ?? 2
        self.waveDepth = defaults.object(forKey: Keys.waveDepth) as? Double ?? 536
        self.waveWeightDepth = defaults.object(forKey: Keys.waveWeightDepth) as? Double ?? 647
        self.waveCrestHalfWidth = defaults.object(forKey: Keys.waveCrestHalfWidth) as? Double ?? 0.75
        self.waveRepetitions = defaults.object(forKey: Keys.waveRepetitions) as? Double ?? 1
        self.waveSpacing = defaults.object(forKey: Keys.waveSpacing) as? Double ?? 0.66
    }
}

/// A `UserDefaults`-storable type ``OnAirDebugState`` persists. Conformance is
/// deliberately closed to the exact set its properties use today — `Bool`, `Double`,
/// and `String` — rather than opened to every plist-representable type, so `persist`
/// can't silently accept something `UserDefaults.set(_:forKey:)` would accept but this
/// type never actually stores.
private protocol PersistableDebugValue {}
extension Bool: PersistableDebugValue {}
extension Double: PersistableDebugValue {}
extension String: PersistableDebugValue {}
#endif
