//
//  PerformanceControls.swift
//  Wallpaper
//
//  Controls for debugging shader performance (LOD, scale, FPS overrides).
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// Controls for debugging shader performance (LOD, scale, FPS overrides).
struct PerformanceControls: View {
    private let qualityController = AdaptiveQualityController.shared

    private var lodBinding: Binding<Float> {
        Binding(
            get: { qualityController.debugLODOverride ?? qualityController.currentLOD },
            set: { qualityController.debugLODOverride = $0 }
        )
    }

    private var scaleBinding: Binding<Float> {
        Binding(
            get: { qualityController.debugScaleOverride ?? qualityController.currentScale },
            set: { qualityController.debugScaleOverride = $0 }
        )
    }

    private var wallpaperFPSBinding: Binding<Float> {
        Binding(
            get: { qualityController.debugWallpaperFPSOverride ?? qualityController.currentWallpaperFPS },
            set: { qualityController.debugWallpaperFPSOverride = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Low Power Mode warning
            if qualityController.isLowPowerMode {
                HStack {
                    Image(systemName: "bolt.slash.fill")
                        .foregroundStyle(.yellow)
                    Text("Low Power Mode Active")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                }
                Text("Throttling locked to save battery. Disable Low Power Mode to adjust.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Current thermal state display
            HStack {
                Text("Thermal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(thermalStateLabel)
                    .font(.caption)
                    .foregroundStyle(thermalStateColor)
                Spacer()
                Text("Momentum: \(qualityController.currentMomentum, format: .number.precision(.fractionLength(2)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Interpolation status
            HStack {
                Text("Interpolation:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if qualityController.interpolationEnabled {
                    Text("ON")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("(\(Int(qualityController.shaderFPS)) fps shader → \(Int(qualityController.currentWallpaperFPS)) fps display)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("OFF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            OverridableSlider(
                label: "LOD",
                value: Binding(
                    get: { Double(lodBinding.wrappedValue) },
                    set: { lodBinding.wrappedValue = Float($0) }
                ),
                range: Double(AdaptiveProfile.lodRange.lowerBound)...Double(AdaptiveProfile.lodRange.upperBound),
                format: .decimal(precision: 2),
                isOverridden: qualityController.debugLODOverride != nil
            )

            OverridableSlider(
                label: "Scale",
                value: Binding(
                    get: { Double(scaleBinding.wrappedValue) },
                    set: { scaleBinding.wrappedValue = Float($0) }
                ),
                range: Double(AdaptiveProfile.scaleRange.lowerBound)...Double(AdaptiveProfile.scaleRange.upperBound),
                format: .decimal(precision: 2),
                isOverridden: qualityController.debugScaleOverride != nil
            )

            OverridableSlider(
                label: "Wallpaper FPS",
                value: Binding(
                    get: { Double(wallpaperFPSBinding.wrappedValue) },
                    set: { wallpaperFPSBinding.wrappedValue = Float($0) }
                ),
                range: Double(AdaptiveProfile.wallpaperFPSRange.lowerBound)...Double(AdaptiveProfile.wallpaperFPSRange.upperBound),
                format: .integer,
                isOverridden: qualityController.debugWallpaperFPSOverride != nil
            )

            ConditionalResetButton(
                hasOverrides: qualityController.debugLODOverride != nil ||
                              qualityController.debugScaleOverride != nil ||
                              qualityController.debugWallpaperFPSOverride != nil,
                label: "Clear Overrides"
            ) {
                qualityController.debugLODOverride = nil
                qualityController.debugScaleOverride = nil
                qualityController.debugWallpaperFPSOverride = nil
            }

            Divider()

            // Reset learned profile button
            Button("Reset Learned Profile") {
                qualityController.resetCurrentProfile()
            }
            .font(.caption)
            .foregroundStyle(.red)
            .disabled(qualityController.isLowPowerMode)

            Text(qualityController.isLowPowerMode
                 ? "Disabled while Low Power Mode is active"
                 : "Removes persisted throttling values and resets to max quality")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var thermalStateLabel: String {
        switch qualityController.rawThermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private var thermalStateColor: Color {
        switch qualityController.rawThermalState {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .gray
        }
    }
}
#endif
