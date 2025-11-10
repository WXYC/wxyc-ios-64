//
//  Logger.swift
//  Core
//
//  Created by Jake Bromberg on 2/20/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

public enum LogLevel: String, CustomStringConvertible, Sendable {
    public var description: String { rawValue }
    
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

@available(iOS 18.0, tvOS 11.0, watchOS 8.0, visionOS 1.0, *)
public let Log = Logger()

@available(iOS 18.0, tvOS 11.0, watchOS 8.0, visionOS 1.0, *)
public final class Logger: Sendable {
    public func callAsFunction(
        fileName: StaticString = #file,
        line: Int = #line,
        functionName: StaticString = #function,
        _ level: LogLevel,
        _ message: Any...
    ) {
        log(fileName, line, functionName, level, message)
    }
    
    public func log(
        _ fileName: StaticString,
        _ line: Int,
        _ functionName: StaticString,
        _ level:
        LogLevel, _
        message: Any...
    ) {
        let logStatement = "\(Logger.timestamp()) \(fileName):\(line) \(functionName) [\(level)] \(message)"
        print(logStatement)
        
        Task { @LoggerActor in
            Self.writeToLogFile(logStatement)
        }
    }
    
    public static func fetchLogs() -> (logName: String, data: Data)? {
        guard let logFileURL = todaysLogFile else {
            return nil
        }
        
        do {
            guard let (logName, data) = try readLogFromDisk(logFileURL) else {
                return nil
            }
            return (
                logName: logName,
                data: data
            )
        } catch {
            Log(.error, "Could not read log file: \(error)")
        }
        
        return nil
    }
    
    // MARK: Private
    
    @globalActor
    private actor LoggerActor: GlobalActor { static let shared = LoggerActor() }
    
    private static func readLogFromDisk(_ logFile: URL) throws -> (logName: String, data: Data)? {
        do {
            let fileHandle = try FileHandle(forReadingFrom: logFile)
            guard let data = try fileHandle.readToEnd() else {
                Log(.error, "Reader handle for log file returned nil data")
                return nil
            }
            return (logFile.lastPathComponent, data)
        } catch {
            Log(.error, "Could not read log file: \(error)")
            return nil
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }
    
    private static let todaysLogFile: URL? = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cachesDirectory = urls.first else {
            Log(.error, "Could not find caches directory")
            return nil
        }
        
        do {
            let logsDirectory = cachesDirectory.appendingPathComponent("logs/")
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true)
            
            let fileURL = logsDirectory.appendingPathComponent(todayDotLog)
            
            if !FileManager.default.fileExists(atPath: fileURL.path()) {
                if !FileManager.default.createFile(atPath: fileURL.path(), contents: nil) {
                    Log(.error, "Failed to create log file")
                }
            }
            
            return fileURL
        } catch {
            Log(.error, "Failed to create log directory: \(error)")
            return nil
        }
    }()
    
    private static var todayDotLog: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date()).appending(".log")
    }
    
    @LoggerActor
    private static let fileHandle: FileHandle = {
        guard let logFileURL = todaysLogFile else {
            return FileHandle.standardOutput
        }
        
        guard let fileHandle = FileHandle(forWritingAtPath: todaysLogFile!.path) else {
            Log(.error, "Failed create file handle")
            return FileHandle.standardOutput
        }
        
        do {
            try fileHandle.seekToEnd()
            return fileHandle
        } catch {
            Log(.error, "Failed to seek to end of log file handle: \(error)")
        }
        
        return FileHandle.standardOutput
    }()
    
    @LoggerActor
    private static func writeToLogFile(_ message: String) {
        do {
            fileHandle.seekToEndOfFile()
            guard let data = (message + "\n").data(using: .utf8) else {
                Log(.error, "Failed convert string to data: \(message)")
                return
            }
            try fileHandle.write(contentsOf: data)
        } catch {
            Log(.error, "Failed to write to log file: \(error)")
        }
    }
}
