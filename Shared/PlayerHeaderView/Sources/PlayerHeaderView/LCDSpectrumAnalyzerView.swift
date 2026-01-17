//
//  LCDSpectrumAnalyzerView.swift
//  PlayerHeaderView
//
//  Canvas-based GPU-accelerated LCD bar chart for audio visualization
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper

// MARK: - Bar Data

/// Data model for a single bar in the chart
public struct BarData: Identifiable, Equatable {
    public var id: String { category }
    public let category: String
    public let value: Int
    /// When set, shows only a single segment at this position (for falling dot animation)
    public let singleDotPosition: Int?

    public init(category: String, value: Int, singleDotPosition: Int? = nil) {
        self.category = category
        self.value = value
        self.singleDotPosition = singleDotPosition
    }
}

// MARK: - LCD Bar Chart View

/// An LCD-style segmented bar chart view for audio visualization
/// Uses Canvas for GPU-accelerated rendering instead of SwiftUI Charts
struct LCDSpectrumAnalyzerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lcdAccentHue) private var hue
    @Environment(\.lcdAccentSaturation) private var saturation
    @Environment(\.lcdAccentBrightness) private var accentBrightness
    @Environment(\.lcdMinOffset) private var minOffset
    @Environment(\.lcdMaxOffset) private var maxOffset
    @Environment(\.lcdActiveBrightness) private var activeBrightnessMultiplier

    let data: [BarData]
    let segmentsPerBar: Int
    let maxValue: Double

    init(
        data: [BarData],
        maxValue: Double,
        segmentsPerBar: Int = 8
    ) {
        self.data = data
        self.maxValue = maxValue
        self.segmentsPerBar = segmentsPerBar
    }

    public var body: some View {
        Canvas { context, size in
            let barCount = data.count
            guard barCount > 0 else { return }

            // Inset drawing area to prevent glow clipping at edges
            let glowRadius: CGFloat = 3
            let inset = glowRadius + 1
            let drawingRect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )

            // Calculate dimensions within the inset area
            let horizontalGap: CGFloat = 3.5
            let verticalGap: CGFloat = 5.5
            let barWidth = (drawingRect.width - horizontalGap * CGFloat(barCount - 1)) / CGFloat(barCount)
            let segmentHeight = (drawingRect.height - verticalGap * CGFloat(segmentsPerBar - 1)) / CGFloat(segmentsPerBar)
            let cornerRadius: CGFloat = min(barWidth, segmentHeight) * 0.2

            // Pre-calculate colors for all segment positions (avoids recalculating 128+ times per frame)
            let activeColors = (0..<segmentsPerBar).map { segmentColor(isActive: true, segmentIndex: $0) }
            let inactiveColors = (0..<segmentsPerBar).map { segmentColor(isActive: false, segmentIndex: $0) }
            let glowColors = (0..<segmentsPerBar).map { glowColor(for: $0, isActive: true) }

            // Create a single blur context for all glow effects
            var glowContext = context
            glowContext.addFilter(.blur(radius: glowRadius))

            // Single pass: iterate once through all bars and segments
            // Use index-based loop to reduce iterator overhead
            for barIndex in 0..<barCount {
                let item = data[barIndex]
                let activeSegments = Int((Double(item.value) / maxValue) * Double(segmentsPerBar))
                let x = drawingRect.minX + CGFloat(barIndex) * (barWidth + horizontalGap)
                let dotPosition = item.singleDotPosition

                for segmentIndex in 0..<segmentsPerBar {
                    // Determine if this segment is active
                    let isActive: Bool
                    if let dot = dotPosition {
                        isActive = segmentIndex == dot && dot >= 0
                    } else {
                        isActive = segmentIndex < activeSegments
                    }

                    // Calculate position (draw from bottom up)
                    let y = drawingRect.maxY - CGFloat(segmentIndex + 1) * (segmentHeight + verticalGap) + verticalGap
                    let rect = CGRect(x: x, y: y, width: barWidth, height: segmentHeight)
                    let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                    if isActive {
                        // Active segment: draw glow first, then segment on top
                        glowContext.fill(path, with: .color(glowColors[segmentIndex]))
                        context.fill(path, with: .color(activeColors[segmentIndex]))
                    } else {
                        // Inactive segment: just draw the segment (no glow)
                        context.fill(path, with: .color(inactiveColors[segmentIndex]))
                    }
                }
            }
        }
    }

    /// Interpolates between max offset (bottom) and min offset (top) based on segment position.
    /// Returns the interpolated HSB offset for the given segment index.
    private func interpolatedOffset(for segmentIndex: Int) -> HSBOffset {
        // Progress: 0 at bottom (index 0), 1 at top (index segmentsPerBar-1)
        let progress = Double(segmentIndex) / Double(max(segmentsPerBar - 1, 1))

        // Interpolate from max (bottom) to min (top)
        return HSBOffset(
            hue: maxOffset.hue + (minOffset.hue - maxOffset.hue) * progress,
            saturation: maxOffset.saturation + (minOffset.saturation - maxOffset.saturation) * progress,
            brightness: maxOffset.brightness + (minOffset.brightness - maxOffset.brightness) * progress
        )
    }

    private func segmentColor(isActive: Bool, segmentIndex: Int) -> Color {
        let offset = interpolatedOffset(for: segmentIndex)

        // Base accent color with offset applied
        let baseHue = hue + offset.hue / 360.0
        let baseSaturation = max(0, min(1, saturation + offset.saturation))
        let baseBrightness = max(0, min(1, accentBrightness + offset.brightness))

        // Active/inactive brightness multipliers
        // Light mode adds a boost factor on top of the configurable active brightness
        let activeBrightness = colorScheme == .light ? activeBrightnessMultiplier * 1.21 : activeBrightnessMultiplier
        let inactiveBrightness = colorScheme == .light ? 1.15 : 0.90

        let brightness = isActive ? activeBrightness : inactiveBrightness

        // Wrap hue to 0-1 range
        var finalHue = baseHue
        while finalHue < 0 { finalHue += 1 }
        while finalHue >= 1 { finalHue -= 1 }

        return Color(hue: finalHue, saturation: baseSaturation, brightness: brightness * baseBrightness)
    }

    private func glowColor(for segmentIndex: Int, isActive: Bool) -> Color {
        guard isActive else { return .clear }

        let offset = interpolatedOffset(for: segmentIndex)

        let baseHue = hue + offset.hue / 360.0
        let baseSaturation = max(0, min(1, saturation + offset.saturation))
        let baseBrightness = max(0, min(1, accentBrightness + offset.brightness))

        // Wrap hue to 0-1 range
        var finalHue = baseHue
        while finalHue < 0 { finalHue += 1 }
        while finalHue >= 1 { finalHue -= 1 }

        return Color(hue: finalHue, saturation: baseSaturation, brightness: 1.5 * baseBrightness).opacity(0.6)
    }
}
