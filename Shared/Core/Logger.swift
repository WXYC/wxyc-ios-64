//
//  Logger.swift
//  Core
//
//  Created by Jake Bromberg on 2/20/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

enum LogLevel {
    case info
    case error
}

protocol Loggable {
    func log(_ level: LogLevel, _ message: String)
}

final class Logger: Loggable {

    func log(_ level: LogLevel, _ message: String) {
        let logStatement = "\(Logger.timestamp()) [\(level)] \(message)"
        print(logStatement)
        Task { @Actor in
            Self.writeToLogFile(logStatement)
        }
    }
    
    // MARK: Private
    
    @globalActor
    actor Actor: GlobalActor { static let shared = Actor() }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    private static func timestamp() -> String {
        dateFormatter.string(from: Date())
    }
    
    @Actor
    private static let logDirectory: URL? = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cachesDirectory = urls.first else {
            print("Error: Could not find caches directory")
            return nil
        }
        
        do {
            let logsDirectory = cachesDirectory.appendingPathComponent("logs/")
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true)
            
            return logsDirectory.appendingPathComponent(logFileName)
        } catch {
            return nil
        }
    }()
    
    private static var logFileName: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date()).appending(".log")
    }
    
    @Actor
    private static func writeToLogFile(_ message: String) {
        guard let logDirectory = logDirectory else { return }
        
        guard let logFileURL = Self.logDirectory else {
            print("Error: Could not find log file")
            return
        }
        
        do {
            try message.write(to: logFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write to log file: \(error)")
        }
    }
}
