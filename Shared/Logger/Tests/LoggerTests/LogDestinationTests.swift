//
//  LogDestinationTests.swift
//  Logger
//
//  Tests for the LogDestination hook, verifying that registered destinations
//  receive log messages after Log(...) calls.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Logger

/// Serialized because `Logger.destinations` is process-global. Note that
/// `.serialized` only orders tests *within* this suite — sibling suites keep
/// running concurrently and their log lines land in any destination registered
/// here. Every assertion below therefore scopes to a per-test UUID marker
/// instead of a raw message count.
@Suite("LogDestination", .serialized)
struct LogDestinationTests {

    @Test("Registered destination receives messages after Log()")
    func registeredDestinationReceivesMessages() {
        let destination = RecordingDestination()
        Logger.addDestination(destination)
        defer { Logger.removeAllDestinations() }

        let marker = UUID().uuidString
        let logger = Logger()
        logger(.error, category: .general, "Dest-\(marker)")

        let matching = destination.messages.filter { $0.message.contains(marker) }
        #expect(matching.count == 1)
        #expect(matching.first?.message.contains("Dest-\(marker)") == true)
        #expect(matching.first?.level == .error)
        #expect(matching.first?.category == .general)
    }

    @Test("Multiple destinations each receive the same message")
    func multipleDestinationsEachReceive() {
        let dest1 = RecordingDestination()
        let dest2 = RecordingDestination()
        Logger.addDestination(dest1)
        Logger.addDestination(dest2)
        defer { Logger.removeAllDestinations() }

        let marker = UUID().uuidString
        let logger = Logger()
        logger(.warning, category: .network, "Multi-\(marker)")

        let matching1 = dest1.messages.filter { $0.message.contains(marker) }
        let matching2 = dest2.messages.filter { $0.message.contains(marker) }
        #expect(matching1.count == 1)
        #expect(matching2.count == 1)
        #expect(matching1.first?.message.contains("Multi-\(marker)") == true)
        #expect(matching2.first?.message.contains("Multi-\(marker)") == true)
    }

    @Test("Destinations not called for messages below minimum level")
    func destinationsRespectLevelFiltering() {
        let config = LoggerConfiguration.shared
        let previousLevel = config.minimumLevel
        config.minimumLevel = .warning
        defer { config.minimumLevel = previousLevel }

        let destination = RecordingDestination()
        Logger.addDestination(destination)
        defer { Logger.removeAllDestinations() }

        let marker = UUID().uuidString
        let logger = Logger()
        logger(.debug, category: .general, "FILTERED-\(marker)")

        #expect(destination.messages.allSatisfy { !$0.message.contains(marker) })
    }

    @Test("removeAllDestinations clears registered destinations")
    func removeAllClearsDestinations() {
        let destination = RecordingDestination()
        Logger.addDestination(destination)
        Logger.removeAllDestinations()

        let marker = UUID().uuidString
        let logger = Logger()
        logger(.error, category: .general, "After-Remove-\(marker)")

        #expect(destination.messages.allSatisfy { !$0.message.contains(marker) })
    }
}

// MARK: - Test Double

final class RecordingDestination: LogDestination, @unchecked Sendable {
    struct Entry {
        let level: LogLevel
        let category: LogCategory
        let message: String
    }

    private let lock = NSLock()
    private var _messages: [Entry] = []

    var messages: [Entry] {
        lock.withLock { _messages }
    }

    func receive(level: LogLevel, category: LogCategory, message: String) {
        lock.withLock {
            _messages.append(Entry(level: level, category: category, message: message))
        }
    }
}
