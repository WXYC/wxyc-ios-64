//
//  OnAirBannerTheme+Debug.swift
//  WXYC
//
//  Builds an OnAirBannerTheme from the live debug-panel state. Isolated in its own
//  file, entirely behind #if DEBUG || DEBUG_TESTFLIGHT, so OnAirDebugState is never
//  reachable from a Release build of the app target (WXYC/wxyc-ios-64#752).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if DEBUG || DEBUG_TESTFLIGHT
import DebugPanel
import SwiftUI
import WXUI

extension OnAirBannerTheme {
    /// Snapshots ``OnAirDebugState/shared`` into a theme value. The composition root
    /// (`RootTabView`) reads this once per body evaluation and installs it via
    /// `.environment(\.onAirBannerTheme, ...)`, so any edit in `OnAirBannerDebugView`
    /// invalidates that read and the banner re-renders immediately — the same
    /// live-tuning loop as before, just sourced from the environment instead of a
    /// direct singleton read inside `PlaylistView`.
    static var debugOverride: OnAirBannerTheme {
        let debug = OnAirDebugState.shared
        return OnAirBannerTheme(
            indicatorColor: Color(HSL(
                hue: debug.indicatorHue,
                saturation: debug.indicatorSaturation,
                lightness: debug.indicatorLightness
            )),
            indicatorBlurRadius: CGFloat(debug.indicatorBlurRadius),
            handleVariation: SFProVariation(
                weight: debug.handleWeight,
                width: debug.handleWidth,
                opticalSize: debug.handleOpticalSize,
                grade: debug.handleGrade
            ),
            adaptiveWidth: debug.adaptiveWidth,
            handleWidthFloor: debug.handleWidthFloor,
            requestLineTintOpacity: debug.requestLineTintOpacity,
            onAirSpacing: CGFloat(debug.onAirSpacing),
            handleLineSpacing: CGFloat(debug.handleLineSpacing),
            waveEnabled: debug.waveEnabled,
            waveDuration: debug.waveDuration,
            waveDepth: debug.waveDepth,
            waveWeightDepth: debug.waveWeightDepth,
            waveCrestHalfWidth: debug.waveCrestHalfWidth,
            waveRepetitions: Int(debug.waveRepetitions.rounded()),
            waveSpacing: debug.waveSpacing,
            waveReplayToken: debug.waveReplayToken
        )
    }
}
#endif
