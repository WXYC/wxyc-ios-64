import Testing
@testable import PlayerHeaderView

@Suite("PlayerHeaderView Tests")
struct PlayerHeaderViewTests {
    @Test("VisualizerConstants has correct default values")
    func visualizerConstantsDefaults() {
        #expect(VisualizerConstants.barAmount == 16)
        #expect(VisualizerConstants.historyLength == 8)
        #expect(VisualizerConstants.magnitudeLimit == 32)
        #expect(VisualizerConstants.updateInterval == 0.05)
    }
    
    @Test("BarData is identifiable and stores correct values")
    func barDataIdentifiable() {
        let barData = BarData(category: "test", value: 10)
        #expect(barData.id == "test")
        #expect(barData.category == "test")
        #expect(barData.value == 10)
    }
    
    @Test("createBarHistory with no values returns zeroed history")
    func createBarHistoryWithNoValues() {
        let history = createBarHistory()
        #expect(history.count == VisualizerConstants.barAmount)
        #expect(history[0].count == VisualizerConstants.historyLength)
        #expect(history[0].allSatisfy { $0 == 0 })
    }
    
    @Test("createBarHistory with preview values returns populated history")
    func createBarHistoryWithPreviewValues() {
        let previewValues: [Float] = [10, 20, 30]
        let history = createBarHistory(previewValues: previewValues)
        #expect(history.count == 3)
        #expect(history[0][0] == 10)
        #expect(history[1][0] == 20)
        #expect(history[2][0] == 30)
    }
}
