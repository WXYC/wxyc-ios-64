//
//  QualityMetricsAggregatorTests.swift
//  Wallpaper
//
//  Unit tests for QualityMetricsAggregator verifying event recording, aggregation,
//  stability detection, and analytics summary generation for wallpaper performance.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Wallpaper

@Suite("QualityMetricsAggregator")
@MainActor
struct QualityMetricsAggregatorTests {

    @Test("Flush does nothing without events")
    func flushWithoutEvents() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.flush(reason: .periodic)

        #expect(reporter.reportedSummaries.isEmpty)
    }

    @Test("Records events and flushes summary")
    func recordAndFlush() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test_shader",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))

        aggregator.flush(reason: .background)

        #expect(reporter.reportedSummaries.count == 1)
        #expect(reporter.reportedSummaries.first?.shaderId == "test_shader")
        #expect(reporter.reportedSummaries.first?.flushReason == .background)
    }

    @Test("Calculates average wallpaper FPS, scale, and LOD")
    func calculatesAverages() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 40,
            scale: 0.8,
            lod: 0.6,
            thermalState: .fair,
            momentum: 0.2
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.avgWallpaperFPS == 50)
        #expect(summary?.avgScale == 0.9)
        #expect(summary?.avgLOD == 0.8)
    }

    @Test("Tracks time in critical")
    func tracksTimeInCritical() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 30,
            scale: 0.5,
            lod: 0.5,
            thermalState: .critical,
            momentum: 0.8
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 30,
            scale: 0.5,
            lod: 0.5,
            thermalState: .critical,
            momentum: 0.8
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 45,
            scale: 0.7,
            lod: 0.7,
            thermalState: .serious,
            momentum: 0.5
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        // 2 ticks in critical * 5 seconds = 10 seconds
        #expect(summary?.timeInCriticalSeconds == 10)
    }

    @Test("Shader change triggers flush")
    func shaderChangeFlushes() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "shader1",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))

        // Change shader
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "shader2",
            wallpaperFPS: 55,
            scale: 0.9,
            lod: 0.9,
            thermalState: .fair,
            momentum: 0.1
        ))

        #expect(reporter.reportedSummaries.count == 1)
        #expect(reporter.reportedSummaries.first?.shaderId == "shader1")
        #expect(reporter.reportedSummaries.first?.flushReason == .shaderChanged)
    }

    @Test("Counts throttle events including LOD")
    func countsThrottleEvents() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 55,  // Down
            scale: 0.9,  // Down
            lod: 1.0,  // Same
            thermalState: .fair,
            momentum: 0.2
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 55,  // Same
            scale: 0.9,  // Same
            lod: 0.8,  // Down - throttle event
            thermalState: .serious,
            momentum: 0.4
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.throttleEventCount == 2)
    }

    @Test("Detects session outcome: neverThrottled")
    func sessionOutcomeNeverThrottled() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        // Record at max quality for long enough
        let baseTime = Date()
        for i in 0..<10 {
            aggregator.record(QualityAdjustmentEvent(
                shaderId: "efficient_shader",
                wallpaperFPS: 60,
                scale: 1.0,
                lod: 1.0,
                thermalState: .nominal,
                momentum: 0,
                timestamp: baseTime.addingTimeInterval(TimeInterval(i * 5))
            ))
        }

        aggregator.flush(reason: .background)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.sessionOutcome == .neverThrottled)
    }

    @Test("Stable values set when stability reached")
    func stableValuesWhenStabilityReached() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        // Record stable values for longer than stability threshold (30s)
        let baseTime = Date()
        for i in 0..<10 {
            aggregator.record(QualityAdjustmentEvent(
                shaderId: "test",
                wallpaperFPS: 45,
                scale: 0.8,
                lod: 0.7,
                thermalState: .fair,
                momentum: 0.2,
                timestamp: baseTime.addingTimeInterval(TimeInterval(i * 5))
            ))
        }

        aggregator.flush(reason: .background)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.reachedStability == true)
        #expect(summary?.stableWallpaperFPS == 45)
        #expect(summary?.stableScale == 0.8)
        #expect(summary?.stableLOD == 0.7)
    }

    @Test("Stable values nil when stability not reached")
    func stableValuesNilWhenUnstable() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        // Record values that keep changing (never stable)
        let baseTime = Date()
        for i in 0..<10 {
            aggregator.record(QualityAdjustmentEvent(
                shaderId: "test",
                wallpaperFPS: Float(60 - i * 2),  // Constantly changing
                scale: 1.0 - Float(i) * 0.05,
                lod: 1.0 - Float(i) * 0.03,
                thermalState: .fair,
                momentum: 0.2,
                timestamp: baseTime.addingTimeInterval(TimeInterval(i * 5))
            ))
        }

        aggregator.flush(reason: .background)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.reachedStability == false)
        #expect(summary?.stableWallpaperFPS == nil)
        #expect(summary?.stableScale == nil)
        #expect(summary?.stableLOD == nil)
    }

    // MARK: - Interpolation Metrics

    @Test("Tracks interpolation enabled percentage")
    func tracksInterpolationEnabledPercent() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        // 2 samples with interpolation on, 2 without = 50%
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0,
            interpolationEnabled: false,
            shaderFPS: 60
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0,
            interpolationEnabled: false,
            shaderFPS: 60
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.interpolationEnabledPercent == 50.0)
    }

    @Test("Calculates average shader FPS while interpolating")
    func calculatesAvgShaderFPS() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 20
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.avgShaderFPSWhileInterpolating == 25)
    }

    @Test("avgShaderFPSWhileInterpolating is nil when never interpolating")
    func avgShaderFPSNilWhenNoInterpolation() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0,
            interpolationEnabled: false,
            shaderFPS: 60
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.avgShaderFPSWhileInterpolating == nil)
        #expect(summary?.interpolationEnabledPercent == 0)
    }

    @Test("Counts interpolation activations")
    func countsInterpolationActivations() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        // Transition: off -> on -> off -> on = 2 activations
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0,
            interpolationEnabled: false,
            shaderFPS: 60
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 1.0,
            lod: 1.0,
            thermalState: .nominal,
            momentum: 0,
            interpolationEnabled: false,
            shaderFPS: 60
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.3,
            interpolationEnabled: true,
            shaderFPS: 30
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.interpolationActivationCount == 2)
    }

    @Test("Calculates estimated workload reduction")
    func calculatesWorkloadReduction() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        // All samples with interpolation on at 30fps shader / 60fps display = 50% reduction
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))
        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        // 100% interpolation enabled * 50% reduction = 50%
        #expect(summary?.estimatedWorkloadReductionPercent == 50.0)
    }

    @Test("Records interpolator resets")
    func recordsInterpolatorResets() {
        let reporter = MockWallpaperAnalytics()
        let aggregator = QualityMetricsAggregator(analytics: reporter)

        aggregator.record(QualityAdjustmentEvent(
            shaderId: "test",
            wallpaperFPS: 60,
            scale: 0.75,
            lod: 1.0,
            thermalState: .fair,
            momentum: 0.2,
            interpolationEnabled: true,
            shaderFPS: 30
        ))

        aggregator.recordInterpolatorReset()
        aggregator.recordInterpolatorReset()
        aggregator.recordInterpolatorReset()

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.interpolatorResetCount == 3)
    }
}
