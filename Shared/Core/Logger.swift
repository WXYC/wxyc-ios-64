//
//  Logger.swift
//  Core
//
//  Created by Jake Bromberg on 2/20/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

public enum LogLevel: String, CustomStringConvertible, Sendable {
    public var description: String {
        self.rawValue
    }
    
    case info = "INFO"
    case error = "ERROR"
}

protocol Loggable {
    func log(_ level: LogLevel, _ message: Any...)
}

public let Log = Logger()

public final class Logger: Loggable, Sendable {
    public func callAsFunction(_ level: LogLevel, _ message: Any...) {
        log(level, message)
    }
    
    func log(_ level: LogLevel, _ message: Any...) {
        let logStatement = "\(Logger.timestamp()) [\(level)] \(message)"
        print(logStatement)
        
        Task { @Actor in
            Self.writeToLogFile(logStatement)
        }
    }
    
    public static func fetchLogs() -> (logName: String, data: Data)? {
        guard let logFileURL = logFile else {
            return nil
        }
        
        do {
            let fileHandle = try FileHandle(forReadingFrom: logFileURL)
            guard let data = try fileHandle.readToEnd() else {
                Log(.error, "Reader handle for log file returned nil data")
                return nil
            }
            return (
                logName: todayFormatted,
                data: data
            )
        } catch {
            Log(.error, "Could not read log file: \(error)")
        }
        
        return nil
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
    
    private static let logFile: URL? = {
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
            
            let fileURL = logsDirectory.appendingPathComponent(todayFormatted)
            
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
    
    private static var todayFormatted: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date()).appending(".log")
    }
    
    @Actor
    private static let fileHandle: FileHandle = {
        guard let logFileURL = logFile else {
            return FileHandle.standardOutput
        }
        
        guard let fileHandle = FileHandle(forWritingAtPath: logFile!.path) else {
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
    
    @Actor
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

import Foundation
import Compression

enum CompressionError: Error {
    case fileReadError
    case fileWriteError
    case compressionFailed
    case invalidInput
}

/// Supported compression algorithms.
enum CompressionAlgorithm {
    case lzfse, lz4, zlib, lzma
    
    var algorithm: compression_algorithm {
        switch self {
        case .lzfse: return COMPRESSION_LZFSE
        case .lz4:   return COMPRESSION_LZ4
        case .zlib:  return COMPRESSION_ZLIB
        case .lzma:  return COMPRESSION_LZMA
        }
    }
}

/// Compresses an entire Data object using the given algorithm.
func compressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
    let dstBufferSize = 64 * 1024  // 64 KB buffer
    var compressedData = Data()
    
    try data.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) in
        guard let srcBaseAddress = srcBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            throw CompressionError.fileReadError
        }
        
        // Initialize the compression stream with default values.
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 0)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 0)!,
            src_size: 0,
            state: nil
        )
        let status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, algorithm.algorithm)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw CompressionError.compressionFailed
        }
        defer { compression_stream_destroy(&stream) }
        
        stream.src_ptr = srcBaseAddress
        stream.src_size = data.count
        
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
        defer { dstBuffer.deallocate() }
        
        repeat {
            stream.dst_ptr = dstBuffer
            stream.dst_size = dstBufferSize
            
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            let streamStatus = compression_stream_process(&stream, flags)
            let outputSize = dstBufferSize - stream.dst_size
            compressedData.append(dstBuffer, count: outputSize)
            
            if streamStatus == COMPRESSION_STATUS_ERROR {
                throw CompressionError.compressionFailed
            }
            if streamStatus == COMPRESSION_STATUS_END {
                break
            }
        } while true
    }
    
    if compressedData.isEmpty {
        throw CompressionError.compressionFailed
    }
    return compressedData
}

/// Compresses a file or directory at sourceURL and writes the compressed output to destinationURL.
///
/// - Parameters:
///   - sourceURL: URL to the file or directory you wish to compress.
///   - destinationURL: For a file, this is the output file URL. For a directory, this is the output directory URL where
///                     each file will be written (mirroring the source structure, with a “.compressed” extension).
///   - algorithm: The compression algorithm to use (default is zlib).
///
/// This implementation compresses raw file data. For directories, it recursively compresses each file.
func compressItem(at sourceURL: URL, to destinationURL: URL, algorithm: CompressionAlgorithm = .zlib) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
        throw CompressionError.invalidInput
    }
    
    if isDirectory.boolValue {
        // Create the destination directory if it doesn't exist.
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        
        // Recursively enumerate files in the directory.
        guard let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: nil) else {
            throw CompressionError.invalidInput
        }
        
        for case let file as URL in enumerator {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue {
                // Determine the file's relative path within the source directory.
                let relativePath = file.path.replacingOccurrences(of: sourceURL.path, with: "")
                // Append the relative path to the destination directory and add a ".compressed" extension.
                let destFileURL = destinationURL
                    .appendingPathComponent(relativePath)
                    .appendingPathExtension("compressed")
                // Ensure the destination directory exists.
                let parentDir = destFileURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                // Compress the file.
                let fileData = try Data(contentsOf: file)
                let compressed = try compressData(fileData, algorithm: algorithm)
                try compressed.write(to: destFileURL)
            }
        }
    } else {
        // Single file: compress and write out to destinationURL.
        let fileData = try Data(contentsOf: sourceURL)
        let compressed = try compressData(fileData, algorithm: algorithm)
        try compressed.write(to: destinationURL)
    }
}
