import Testing
import Foundation
@testable import Playlist

// MARK: - FlowsheetEntryType Tests

@Suite("FlowsheetEntryType Tests")
struct FlowsheetEntryTypeTests {

    @Test("Nil message returns playcut")
    func nilMessageIsPlaycut() {
        let entryType = FlowsheetEntryType.from(message: nil)
        #expect(entryType == .playcut)
    }

    @Test("Empty message returns playcut")
    func emptyMessageIsPlaycut() {
        // Empty message should be treated as unknown, defaulting to playcut
        let entryType = FlowsheetEntryType.from(message: "")
        #expect(entryType == .playcut)
    }

    @Test("'Talkset' message returns talkset")
    func talksetMessage() {
        let entryType = FlowsheetEntryType.from(message: "Talkset")
        #expect(entryType == .talkset)
    }

    @Test("Message containing 'Breakpoint' returns breakpoint")
    func breakpointMessage() {
        let entryType = FlowsheetEntryType.from(message: "01:00 PM Breakpoint")
        #expect(entryType == .breakpoint)
    }

    @Test("Plain 'Breakpoint' returns breakpoint")
    func plainBreakpointMessage() {
        let entryType = FlowsheetEntryType.from(message: "Breakpoint")
        #expect(entryType == .breakpoint)
    }

    @Test("'Start of Show:' parses DJ name correctly")
    func showStartWithDJName() {
        let entryType = FlowsheetEntryType.from(message: "Start of Show: DJ Cool joined the set at 10/14/2025 2:00 PM")
        if case .showStart(let djName) = entryType {
            #expect(djName == "DJ Cool")
        } else {
            Issue.record("Expected showStart but got \(entryType)")
        }
    }

    @Test("'End of Show:' parses DJ name correctly")
    func showEndWithDJName() {
        let entryType = FlowsheetEntryType.from(message: "End of Show: DJ Cool left the set at 10/14/2025 4:00 PM")
        if case .showEnd(let djName) = entryType {
            #expect(djName == "DJ Cool")
        } else {
            Issue.record("Expected showEnd but got \(entryType)")
        }
    }

    @Test("'Start of Show:' with no space before 'joined' falls back to full text")
    func showStartWithNoSpaceBeforeJoined() {
        // When there's no space before "joined", the pattern doesn't match
        // and the full text is returned as the DJ name fallback
        let entryType = FlowsheetEntryType.from(message: "Start of Show: joined the set at 10/14/2025")
        if case .showStart(let djName) = entryType {
            #expect(djName == "joined the set at 10/14/2025")
        } else {
            Issue.record("Expected showStart but got \(entryType)")
        }
    }

    @Test("'Start of Show:' without standard format falls back")
    func showStartWithoutStandardFormat() {
        let entryType = FlowsheetEntryType.from(message: "Start of Show: Some Random Text")
        if case .showStart(let djName) = entryType {
            // Should return the entire text after "Start of Show:" since it doesn't match pattern
            #expect(djName == "Some Random Text")
        } else {
            Issue.record("Expected showStart but got \(entryType)")
        }
    }

    @Test("Unknown message defaults to playcut")
    func unknownMessageDefaultsToPlaycut() {
        let entryType = FlowsheetEntryType.from(message: "Some random message")
        #expect(entryType == .playcut)
    }

    @Test("Case sensitivity: 'TALKSET' is not talkset")
    func caseSensitiveTalkset() {
        let entryType = FlowsheetEntryType.from(message: "TALKSET")
        // Should be playcut since exact match "Talkset" is expected
        #expect(entryType == .playcut)
    }

    @Test("Case sensitivity: 'breakpoint' still contains 'Breakpoint'")
    func caseSensitiveBreakpoint() {
        // "breakpoint" does NOT contain "Breakpoint" (case sensitive)
        let entryType = FlowsheetEntryType.from(message: "breakpoint")
        #expect(entryType == .playcut)
    }
}
