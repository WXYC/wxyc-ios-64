//
//  LoggerTests.swift
//  Logger
//
//  Tests for the Logger module, verifying thread-safe file writes and log
//  formatting. These tests exercise the production code paths that were
//  previously losing log entries from @MainActor @Observable callers.
//
//  Created by Jake Bromberg on 02/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Logger

// MARK: - Log File Write Tests

/// Serialized because LoggerConfiguration.shared is process-global and
/// other suites mutate its minimumLevel.
@Suite("Logger file writes", .serialized)
struct LoggerFileWriteTests {

    @Test("Log entries are written to today's log file")
    func logEntryWrittenToFile() async throws {
        let logger = Logger()
        let marker = UUID().uuidString

        logger(.error, category: .general, "FileWrite-\(marker)")

        let content = try fetchLogContent()
        #expect(content.contains("FileWrite-\(marker)"))
    }

    @Test("Concurrent log writes from multiple threads all persist")
    func concurrentWritesAllPersist() async throws {
        let logger = Logger()
        let marker = UUID().uuidString
        let count = 50

        // Fire log calls concurrently from many tasks.
        // Use .error level so configuration changes from other suites can't filter these out.
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    logger(.error, category: .general, "\(marker)-\(i)")
                }
            }
        }

        let content = try fetchLogContent()

        for i in 0..<count {
            #expect(
                content.contains("\(marker)-\(i)"),
                "Missing log entry \(i) of \(count)"
            )
        }
    }

    @Test("Log entries from @MainActor context are written to file")
    func mainActorWritesPersist() async throws {
        let marker = UUID().uuidString

        // Simulate the exact call pattern that was dropping logs:
        // a @MainActor caller invoking Log()
        await MainActor.run {
            Log(.error, category: .playback, "MainActor-\(marker)")
        }

        let content = try fetchLogContent()
        #expect(content.contains("MainActor-\(marker)"))
    }
}

// MARK: - Log Level Filtering Tests

/// Serialized because these tests mutate LoggerConfiguration.shared.
@Suite("Log level filtering", .serialized)
struct LogLevelFilteringTests {

    @Test("Messages below minimum level are filtered out")
    func belowMinimumFiltered() async throws {
        let config = LoggerConfiguration.shared
        let previousLevel = config.minimumLevel

        config.minimumLevel = .warning
        defer { config.minimumLevel = previousLevel }

        let marker = UUID().uuidString
        let logger = Logger()

        logger(.debug, category: .general, "SHOULD-NOT-APPEAR-\(marker)")
        logger(.warning, category: .general, "SHOULD-APPEAR-\(marker)")

        let content = try fetchLogContent()

        #expect(!content.contains("SHOULD-NOT-APPEAR-\(marker)"))
        #expect(content.contains("SHOULD-APPEAR-\(marker)"))
    }

    @Test("Category-specific overrides are respected")
    func categoryOverride() async throws {
        let config = LoggerConfiguration.shared
        let previousLevel = config.minimumLevel

        config.minimumLevel = .debug
        config.setMinimumLevel(.error, for: .playback)
        defer {
            config.minimumLevel = previousLevel
            config.clearMinimumLevel(for: .playback)
        }

        let marker = UUID().uuidString
        let logger = Logger()

        logger(.info, category: .playback, "PLAYBACK-FILTERED-\(marker)")
        logger(.error, category: .playback, "PLAYBACK-VISIBLE-\(marker)")
        logger(.info, category: .general, "GENERAL-VISIBLE-\(marker)")

        let content = try fetchLogContent()

        #expect(!content.contains("PLAYBACK-FILTERED-\(marker)"))
        #expect(content.contains("PLAYBACK-VISIBLE-\(marker)"))
        #expect(content.contains("GENERAL-VISIBLE-\(marker)"))
    }
}

// MARK: - Log Format Tests

@Suite("Log format", .serialized)
struct LogFormatTests {

    @Test("Log entries contain category and level tags")
    func formatIncludesCategoryAndLevel() async throws {
        let marker = UUID().uuidString
        let logger = Logger()

        logger(.error, category: .network, "FORMAT-\(marker)")

        let content = try fetchLogContent()

        let line = try #require(
            content.components(separatedBy: "\n").first { $0.contains("FORMAT-\(marker)") }
        )

        #expect(line.contains("[Network/ERROR]"))
        #expect(line.contains("LoggerTests.swift"))
    }
}

// MARK: - Helpers

/// Read today's log file content, flushing first to ensure all writes are visible.
private func fetchLogContent() throws -> String {
    let logs = Logger.fetchLogs()
    let logData = try #require(logs, "Expected today's log file to exist")
    return try #require(String(data: logData.data, encoding: .utf8))
}
