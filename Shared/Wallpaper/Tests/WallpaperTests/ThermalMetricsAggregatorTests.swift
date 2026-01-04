import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalMetricsAggregator")
@MainActor
struct ThermalMetricsAggregatorTests {

    @Test("Flush does nothing without events")
    func flushWithoutEvents() {
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        aggregator.flush(reason: .periodic)

        #expect(reporter.reportedSummaries.isEmpty)
    }

    @Test("Records events and flushes summary")
    func recordAndFlush() {
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test_shader",
            fps: 60,
            scale: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))

        aggregator.flush(reason: .background)

        #expect(reporter.reportedSummaries.count == 1)
        #expect(reporter.reportedSummaries.first?.shaderId == "test_shader")
        #expect(reporter.reportedSummaries.first?.flushReason == .background)
    }

    @Test("Calculates average FPS and scale")
    func calculatesAverages() {
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 60,
            scale: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))
        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 40,
            scale: 0.8,
            thermalState: .fair,
            momentum: 0.2
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.avgFPS == 50)
        #expect(summary?.avgScale == 0.9)
    }

    @Test("Tracks time in critical")
    func tracksTimeInCritical() {
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 30,
            scale: 0.5,
            thermalState: .critical,
            momentum: 0.8
        ))
        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 30,
            scale: 0.5,
            thermalState: .critical,
            momentum: 0.8
        ))
        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 45,
            scale: 0.7,
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
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "shader1",
            fps: 60,
            scale: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))

        // Change shader
        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "shader2",
            fps: 55,
            scale: 0.9,
            thermalState: .fair,
            momentum: 0.1
        ))

        #expect(reporter.reportedSummaries.count == 1)
        #expect(reporter.reportedSummaries.first?.shaderId == "shader1")
        #expect(reporter.reportedSummaries.first?.flushReason == .shaderChanged)
    }

    @Test("Counts throttle events")
    func countsThrottleEvents() {
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 60,
            scale: 1.0,
            thermalState: .nominal,
            momentum: 0
        ))
        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 55,  // Down
            scale: 0.9,  // Down
            thermalState: .fair,
            momentum: 0.2
        ))
        aggregator.record(ThermalAdjustmentEvent(
            shaderId: "test",
            fps: 50,  // Down
            scale: 0.9,  // Same
            thermalState: .serious,
            momentum: 0.4
        ))

        aggregator.flush(reason: .periodic)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.throttleEventCount == 2)
    }

    @Test("Detects session outcome: neverThrottled")
    func sessionOutcomeNeverThrottled() {
        let reporter = MockThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)

        // Record at max quality for long enough
        let baseTime = Date()
        for i in 0..<10 {
            aggregator.record(ThermalAdjustmentEvent(
                shaderId: "efficient_shader",
                fps: 60,
                scale: 1.0,
                thermalState: .nominal,
                momentum: 0,
                timestamp: baseTime.addingTimeInterval(TimeInterval(i * 5))
            ))
        }

        aggregator.flush(reason: .background)

        let summary = reporter.reportedSummaries.first
        #expect(summary?.sessionOutcome == .neverThrottled)
    }
}
