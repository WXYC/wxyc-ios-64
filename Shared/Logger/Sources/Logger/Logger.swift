//
//  Logger.swift
//  Logger
//
//  Unified logging API wrapping os.Logger for consistent debug output.
//
//  Created by Jake Bromberg on 02/21/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import OSLog

// MARK: - Log Level
    
/// Severity level for log messages.
public enum LogLevel: Int, Comparable, CustomStringConvertible, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
        
// MARK: - Category

/// Extensible log category for filtering and organization.
public struct Category: Hashable, RawRepresentable, Codable, Sendable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
        
    // Predefined categories
    public static let general = Category(rawValue: "General")
    public static let playback = Category(rawValue: "Playback")
    public static let artwork = Category(rawValue: "Artwork")
    public static let caching = Category(rawValue: "Caching")
    public static let network = Category(rawValue: "Network")
    public static let ui = Category(rawValue: "UI")
    public static let wallpaper = Category(rawValue: "Wallpaper")
}

// MARK: - Configuration
        
/// Configuration for log level filtering.
public final class LoggerConfiguration: @unchecked Sendable {
    public static let shared = LoggerConfiguration()
    
    private let lock = NSLock()
    private var _minimumLevel: LogLevel = .debug
    private var _categoryOverrides: [Category: LogLevel] = [:]
    
    /// Global minimum log level. Messages below this level are filtered out.
    public var minimumLevel: LogLevel {
        get { lock.withLock { _minimumLevel } }
        set { lock.withLock { _minimumLevel = newValue } }
    }
    
    /// Set a category-specific minimum log level.
    public func setMinimumLevel(_ level: LogLevel, for category: Category) {
        lock.withLock { _categoryOverrides[category] = level }
    }
    
    /// Clear category-specific override, falling back to global minimum.
    public func clearMinimumLevel(for category: Category) {
        lock.withLock { _categoryOverrides[category] = nil }
    }
    
    func shouldLog(level: LogLevel, category: Category) -> Bool {
        let threshold = lock.withLock {
            _categoryOverrides[category] ?? _minimumLevel
        }
        return level >= threshold
    }
}
    
// MARK: - Global Logger Instance

@available(iOS 18.0, tvOS 11.0, watchOS 8.0, visionOS 1.0, *)
public let Log = Logger()

// MARK: - Logger
        
@available(iOS 18.0, tvOS 11.0, watchOS 8.0, visionOS 1.0, *)
public final class Logger: Sendable {
    fileprivate static let subsystem = "org.wxyc.app"
    
    /// Cache of os.Logger instances by category
    private static let osLoggers = OSLoggerCache()
    
    // MARK: - Public API
    
    public func callAsFunction(
        _ level: LogLevel,
        category: Category = .general,
        _ message: @autoclosure () -> Any,
        fileName: StaticString = #file,
        line: Int = #line,
        functionName: StaticString = #function
    ) {
        guard LoggerConfiguration.shared.shouldLog(level: level, category: category) else {
            return
        }
    
        let messageValue = message()
        log(level, category: category, messageValue, fileName: fileName, line: line, functionName: functionName)
    }
    
    private func log(
        _ level: LogLevel,
        category: Category,
        _ message: Any,
        fileName: StaticString,
        line: Int,
        functionName: StaticString
    ) {
        let fileBasename = (String(describing: fileName) as NSString).lastPathComponent
        let logStatement = "\(Logger.timestamp()) \(fileBasename):\(line) \(functionName) [\(category.rawValue)/\(level)] \(message)"
        
        // Log to os.Logger for Console.app integration
        let osLogger = Self.osLoggers.logger(for: category)
        osLogger.log(level: level.osLogType, "\(logStatement)")
        
        // Also print for Xcode console
        print(logStatement)
        
        // Write to file asynchronously
        Task { @LoggerActor in
            Self.writeToLogFile(logStatement)
        }
    }
    
    // MARK: - Log Retrieval
    
    /// Fetch today's log file for export (e.g., attaching to feedback emails).
    public static func fetchLogs() -> (logName: String, data: Data)? {
        guard let logFileURL = todaysLogFile else {
            return nil
        }
        
        do {
            return try readLogFromDisk(logFileURL)
        } catch {
            // Use print to avoid recursion
            print("[Logger] Could not read log file: \(error)")
            return nil
        }
    }

    /// Fetch all log files (today's uncompressed + older compressed).
    public static func fetchAllLogs() -> [(logName: String, data: Data)] {
        guard let logsDir = logsDirectory else { return [] }

        var results: [(String, Data)] = []
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        for file in contents {
            guard let data = try? Data(contentsOf: file) else { continue }
            results.append((file.lastPathComponent, data))
        }

        return results
    }

    // MARK: - Private

    @globalActor
    private actor LoggerActor: GlobalActor { static let shared = LoggerActor() }

    private static func readLogFromDisk(_ logFile: URL) throws -> (logName: String, data: Data)? {
        let fileHandle = try FileHandle(forReadingFrom: logFile)
        guard let data = try fileHandle.readToEnd() else {
            return nil
        }
        return (logFile.lastPathComponent, data)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }

    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static let logsDirectory: URL? = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cachesDirectory = urls.first else {
            print("[Logger INIT] Could not find caches directory")
            return nil
        }

        let logsDir = cachesDirectory.appendingPathComponent("logs/")
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            return logsDir
        } catch {
            print("[Logger INIT] Failed to create logs directory: \(error)")
            return nil
        }
    }()

    private static let todaysLogFile: URL? = {
        guard let logsDir = logsDirectory else { return nil }

        let fileName = todayDateString() + ".log"
        let fileURL = logsDir.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: fileURL.path()) {
            if !FileManager.default.createFile(atPath: fileURL.path(), contents: nil) {
                print("[Logger INIT] Failed to create log file")
            }
        }

        // Run cleanup asynchronously on startup
        Task.detached(priority: .utility) {
            cleanupOldLogs()
        }

        return fileURL
    }()

    @LoggerActor
    private static let fileHandle: FileHandle? = {
        guard let logFileURL = todaysLogFile else { return nil }

        guard let handle = FileHandle(forWritingAtPath: logFileURL.path()) else {
            print("[Logger INIT] Failed to create file handle")
            return nil
        }

        do {
            try handle.seekToEnd()
            return handle
        } catch {
            print("[Logger INIT] Failed to seek to end: \(error)")
            return nil
        }
    }()

    @LoggerActor
    private static func writeToLogFile(_ message: String) {
        guard let fileHandle else { return }

        do {
            try fileHandle.seekToEnd()
            guard let data = (message + "\n").data(using: .utf8) else { return }
            try fileHandle.write(contentsOf: data)
        } catch {
            // Avoid recursion - use print
            print("[Logger] Failed to write to log file: \(error)")
        }
    }

    // MARK: - Log Cleanup

    private static func cleanupOldLogs() {
        guard let logsDir = logsDirectory else { return }

        let today = todayDateString()
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in contents {
            let fileName = file.lastPathComponent

            // Skip today's log
            if fileName.hasPrefix(today) { continue }

            // Compress uncompressed .log files from previous days
            if fileName.hasSuffix(".log") && !fileName.hasSuffix(".log.zip") {
                compressLogFile(file)
            }
            // Delete .log.zip files older than 7 days
            else if fileName.hasSuffix(".log.zip") {
                if let values = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let created = values.creationDate,
                   created < cutoffDate {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    private static func compressLogFile(_ logFile: URL) {
        guard let data = try? Data(contentsOf: logFile) else { return }
        guard let compressed = try? (data as NSData).compressed(using: .zlib) as Data else { return }

        // Create zip file with same base name
        let zipURL = logFile.appendingPathExtension("zip")

        do {
            try compressed.write(to: zipURL)
            try FileManager.default.removeItem(at: logFile)
        } catch {
            print("[Logger] Failed to compress log file: \(error)")
        }
    }
}

// MARK: - OS Logger Cache

/// Thread-safe cache of os.Logger instances by category.
private final class OSLoggerCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [Category: os.Logger] = [:]

    func logger(for category: Category) -> os.Logger {
        lock.withLock {
            if let existing = cache[category] {
                return existing
            }
            let newLogger = os.Logger(subsystem: Logger.subsystem, category: category.rawValue)
            cache[category] = newLogger
            return newLogger
        }
    }
}
