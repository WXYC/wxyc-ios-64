import XCTest
@testable import PlayerHeaderView

final class PlayerHeaderViewTests: XCTestCase {
    func testVisualizerConstantsDefaults() {
        XCTAssertEqual(VisualizerConstants.barAmount, 16)
        XCTAssertEqual(VisualizerConstants.historyLength, 8)
        XCTAssertEqual(VisualizerConstants.magnitudeLimit, 32)
        XCTAssertEqual(VisualizerConstants.updateInterval, 0.05)
    }
    
    func testBarDataIdentifiable() {
        let barData = BarData(category: "test", value: 10)
        XCTAssertEqual(barData.id, "test")
        XCTAssertEqual(barData.category, "test")
        XCTAssertEqual(barData.value, 10)
    }
    
    func testCreateBarHistoryWithNoValues() {
        let history = createBarHistory()
        XCTAssertEqual(history.count, VisualizerConstants.barAmount)
        XCTAssertEqual(history[0].count, VisualizerConstants.historyLength)
        XCTAssertTrue(history[0].allSatisfy { $0 == 0 })
    }
    
    func testCreateBarHistoryWithPreviewValues() {
        let previewValues: [Float] = [10, 20, 30]
        let history = createBarHistory(previewValues: previewValues)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0][0], 10)
        XCTAssertEqual(history[1][0], 20)
        XCTAssertEqual(history[2][0], 30)
    }
}

