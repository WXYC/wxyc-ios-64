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
import struct Logger.Category
@testable import Logger

/// Serialized because Logger.destinations is process-global.
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

        #expect(dest1.messages.count == 1)
        #expect(dest2.messages.count == 1)
        #expect(dest1.messages.first?.message.contains("Multi-\(marker)") == true)
        #expect(dest2.messages.first?.message.contains("Multi-\(marker)") == true)
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

        #expect(destination.messages.isEmpty)
    }

    @Test("removeAllDestinations clears registered destinations")
    func removeAllClearsDestinations() {
        let destination = RecordingDestination()
        Logger.addDestination(destination)
        Logger.removeAllDestinations()

        let logger = Logger()
        logger(.error, category: .general, "After-Remove")

        #expect(destination.messages.isEmpty)
    }
}

// MARK: - Test Double

final class RecordingDestination: LogDestination, @unchecked Sendable {
    struct Entry {
        let level: LogLevel
        let category: Category
        let message: String
    }

    private let lock = NSLock()
    private var _messages: [Entry] = []

    var messages: [Entry] {
        lock.withLock { _messages }
    }

    func receive(level: LogLevel, category: Category, message: String) {
        lock.withLock {
            _messages.append(Entry(level: level, category: category, message: message))
        }
    }
}
