//
//  WXYCGradientTests.swift
//  WXUI
//
//  Coverage for WXYCGradient.resolve(in:) — the brand gradient shape style
//  that WXYCBackground duplicated byte-for-byte before the two were
//  consolidated onto this one (WXYC/wxyc-ios-64#322).
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import WXUI

@Suite("WXYCGradient")
@MainActor
struct WXYCGradientTests {
    private static var lightEnvironment: EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        return environment
    }

    private static var darkEnvironment: EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        return environment
    }

    @Test("light scheme resolves to the brand gradient stops")
    func lightSchemeStops() {
        let resolved = WXYCGradient().resolve(in: Self.lightEnvironment)
        let expected = Gradient(stops: [
            .init(color: Color(red: 126 / 255, green: 133 / 255, blue: 193 / 255), location: 0.0),
            .init(color: Color(red: 126 / 255, green: 133 / 255, blue: 193 / 255), location: 0.08),
            .init(color: Color(red: 226 / 255, green: 125 / 255, blue: 178 / 255), location: 0.66),
            .init(color: Color(red: 233 / 255, green: 140 / 255, blue: 140 / 255), location: 0.72),
            .init(color: Color(red: 230 / 255, green: 161 / 255, blue: 191 / 255), location: 1.0)
        ])
        #expect(resolved.stops.count == expected.stops.count)
        for (resolvedStop, expectedStop) in zip(resolved.stops, expected.stops) {
            #expect(resolvedStop.location == expectedStop.location)
            #expect(
                resolvedStop.color.resolve(in: Self.lightEnvironment)
                    == expectedStop.color.resolve(in: Self.lightEnvironment)
            )
        }
    }

    @Test("dark scheme resolves to the brand gradient stops")
    func darkSchemeStops() {
        let resolved = WXYCGradient().resolve(in: Self.darkEnvironment)
        let expected = Gradient(stops: [
            .init(color: Color(hue: 0.649, saturation: 0.547, brightness: 0.557), location: 0.0),
            .init(color: Color(hue: 0.649, saturation: 0.547, brightness: 0.557), location: 0.08),
            .init(color: Color(hue: 0.913, saturation: 0.647, brightness: 0.686), location: 0.66),
            .init(color: Color(hue: 0.000, saturation: 0.599, brightness: 0.714), location: 0.72),
            .init(color: Color(hue: 0.928, saturation: 0.600, brightness: 0.702), location: 1.0)
        ])
        #expect(resolved.stops.count == expected.stops.count)
        for (resolvedStop, expectedStop) in zip(resolved.stops, expected.stops) {
            #expect(resolvedStop.location == expectedStop.location)
            #expect(
                resolvedStop.color.resolve(in: Self.darkEnvironment)
                    == expectedStop.color.resolve(in: Self.darkEnvironment)
            )
        }
    }

    @Test("light and dark resolve to different gradients")
    func lightAndDarkDiffer() {
        let light = WXYCGradient().resolve(in: Self.lightEnvironment)
        let dark = WXYCGradient().resolve(in: Self.darkEnvironment)
        #expect(
            light.stops.first?.color.resolve(in: Self.lightEnvironment)
                != dark.stops.first?.color.resolve(in: Self.darkEnvironment)
        )
    }
}
