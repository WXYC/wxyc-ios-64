//
//  DebugHUD.swift
//  DebugPanel
//
//  Created by Jake Bromberg on 12/23/25.
//

import SwiftUI

/// A debug HUD overlay displaying real-time performance metrics.
public struct DebugHUD: View {
    @State private var metrics = DebugMetricsProvider()
    private var hudState = DebugHUDState.shared

    public init() {}

    public var body: some View {
        Group {
            if hudState.isVisible {
                VStack(alignment: .leading, spacing: 2) {
                    MetricRow(label: "FPS", value: "\(metrics.fps)")
                    MetricRow(label: "CPU", value: String(format: "%.1f%%", metrics.cpuUsage))
                    MetricRow(label: "GPU", value: String(format: "%.1f MB", metrics.gpuMemoryMB))
                    MetricRow(label: "MEM", value: String(format: "%.1f MB", metrics.memoryMB))
                    MetricRow(label: "TMP", value: metrics.thermalState.description)
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.6))
                .clipShape(.rect(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 50)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .frame(width: 32, alignment: .leading)
            Text(value)
        }
    }
}
