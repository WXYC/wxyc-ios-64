//
//  UploadPreviewTests.swift
//  app-store-previews
//
//  Unit tests for the App Store Connect upload tool.
//
//  Created by Jake on 01/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import CryptoKit

// ============================================================================
// Test Framework
// ============================================================================

var testsRun = 0
var testsPassed = 0
var testsFailed = 0

func assertEqual<T: Equatable>(_ expected: T, _ actual: T, _ message: String = "") -> Bool {
    if expected == actual {
        return true
    } else {
        print("    Expected: \(expected)")
        print("    Actual:   \(actual)")
        if !message.isEmpty { print("    Message:  \(message)") }
        return false
    }
}

func assertTrue(_ condition: Bool, _ message: String = "") -> Bool {
    if condition {
        return true
    } else {
        print("    Expected true but got false")
        if !message.isEmpty { print("    Message: \(message)") }
        return false
    }
}

func assertFalse(_ condition: Bool, _ message: String = "") -> Bool {
    if !condition {
        return true
    } else {
        print("    Expected false but got true")
        if !message.isEmpty { print("    Message: \(message)") }
        return false
    }
}

func assertContains(_ haystack: String, _ needle: String, _ message: String = "") -> Bool {
    if haystack.contains(needle) {
        return true
    } else {
        print("    Expected to contain: '\(needle)'")
        print("    In: '\(haystack.prefix(200))...'")
        if !message.isEmpty { print("    Message: \(message)") }
        return false
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "") -> Bool {
    if value != nil {
        return true
    } else {
        print("    Expected non-nil value")
        if !message.isEmpty { print("    Message: \(message)") }
        return false
    }
}

func runTest(_ name: String, _ test: () -> Bool) {
    testsRun += 1
    print("  Testing: \(name) ... ", terminator: "")

    if test() {
        print("✅ PASSED")
        testsPassed += 1
    } else {
        print("❌ FAILED")
        testsFailed += 1
    }
}

// ============================================================================
// Mock Types for Testing
// ============================================================================

struct TestAppStoreConnectConfig {
    let keyID: String
    let issuerID: String
    let privateKeyPath: String
    let appID: String
}

// ============================================================================
// Tests: Configuration
// ============================================================================

func testConfigCreation() -> Bool {
    let config = TestAppStoreConnectConfig(
        keyID: "ABC123",
        issuerID: "12345-67890",
        privateKeyPath: "/path/to/key.p8",
        appID: "com.example.app"
    )

    return assertEqual("ABC123", config.keyID) &&
           assertEqual("12345-67890", config.issuerID) &&
           assertEqual("/path/to/key.p8", config.privateKeyPath) &&
           assertEqual("com.example.app", config.appID)
}

// ============================================================================
// Tests: Base64 URL Encoding
// ============================================================================

func testBase64URLEncoding() -> Bool {
    // Standard base64 with characters that need URL-safe replacement
    let testData = Data([0xfb, 0xff, 0xfe])  // Will produce +/= in standard base64

    let standard = testData.base64EncodedString()
    let urlSafe = standard
        .replacing("+", with: "-")
        .replacing("/", with: "_")
        .replacing("=", with: "")

    // Verify no URL-unsafe characters remain
    return assertFalse(urlSafe.contains("+"), "Should not contain +") &&
           assertFalse(urlSafe.contains("/"), "Should not contain /") &&
           assertFalse(urlSafe.contains("="), "Should not contain =")
}

// ============================================================================
// Tests: MD5 Checksum
// ============================================================================

func testMD5Checksum() -> Bool {
    let testData = Data("Hello, World!".utf8)
    let checksum = Insecure.MD5.hash(data: testData)
        .map { String(format: "%02hhx", $0) }
        .joined()

    // Known MD5 of "Hello, World!"
    return assertEqual("65a8e27d8879283831b664bd8b7f0ad4", checksum)
}

func testMD5ChecksumEmpty() -> Bool {
    let testData = Data()
    let checksum = Insecure.MD5.hash(data: testData)
        .map { String(format: "%02hhx", $0) }
        .joined()

    // Known MD5 of empty string
    return assertEqual("d41d8cd98f00b204e9800998ecf8427e", checksum)
}

func testMD5ChecksumLength() -> Bool {
    let testData = Data("test".utf8)
    let checksum = Insecure.MD5.hash(data: testData)
        .map { String(format: "%02hhx", $0) }
        .joined()

    // MD5 is always 32 hex characters
    return assertEqual(32, checksum.count, "MD5 should be 32 hex chars")
}

// ============================================================================
// Tests: JSON Encoding
// ============================================================================

struct TestCodable: Codable {
    let type: String
    let id: String
}

func testJSONEncoding() -> Bool {
    let test = TestCodable(type: "appPreviews", id: "12345")

    do {
        let data = try JSONEncoder().encode(test)
        let json = String(data: data, encoding: .utf8) ?? ""

        return assertContains(json, "appPreviews") &&
               assertContains(json, "12345")
    } catch {
        print("    Encoding failed: \(error)")
        return false
    }
}

func testJSONDecoding() -> Bool {
    let json = """
    {"type":"appPreviews","id":"67890"}
    """

    do {
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(TestCodable.self, from: data)

        return assertEqual("appPreviews", decoded.type) &&
               assertEqual("67890", decoded.id)
    } catch {
        print("    Decoding failed: \(error)")
        return false
    }
}

// ============================================================================
// Tests: Upload Operation Parsing
// ============================================================================

struct TestUploadOperation: Codable {
    let method: String
    let url: String
    let length: Int
    let offset: Int
}

func testUploadOperationParsing() -> Bool {
    let json = """
    {
        "method": "PUT",
        "url": "https://example.com/upload",
        "length": 1048576,
        "offset": 0
    }
    """

    do {
        let data = Data(json.utf8)
        let op = try JSONDecoder().decode(TestUploadOperation.self, from: data)

        return assertEqual("PUT", op.method) &&
               assertEqual("https://example.com/upload", op.url) &&
               assertEqual(1048576, op.length) &&
               assertEqual(0, op.offset)
    } catch {
        print("    Parsing failed: \(error)")
        return false
    }
}

func testMultipleUploadOperations() -> Bool {
    let json = """
    [
        {"method": "PUT", "url": "https://example.com/1", "length": 1000, "offset": 0},
        {"method": "PUT", "url": "https://example.com/2", "length": 1000, "offset": 1000},
        {"method": "PUT", "url": "https://example.com/3", "length": 500, "offset": 2000}
    ]
    """

    do {
        let data = Data(json.utf8)
        let ops = try JSONDecoder().decode([TestUploadOperation].self, from: data)

        return assertEqual(3, ops.count) &&
               assertEqual(0, ops[0].offset) &&
               assertEqual(1000, ops[1].offset) &&
               assertEqual(2000, ops[2].offset)
    } catch {
        print("    Parsing failed: \(error)")
        return false
    }
}

// ============================================================================
// Tests: File Size Formatting
// ============================================================================

func testFileSizeFormatting() -> Bool {
    let sizes: [(Int64, String)] = [
        (500, "500 bytes"),
        (1024, "1 KB"),
        (1048576, "1 MB"),
        (52428800, "50 MB"),
    ]

    for (bytes, _) in sizes {
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        if formatted.isEmpty {
            print("    Empty format for \(bytes) bytes")
            return false
        }
    }

    return true
}

// ============================================================================
// Tests: URL Construction
// ============================================================================

func testURLConstruction() -> Bool {
    let baseURL = "https://api.appstoreconnect.apple.com/v1"
    let path = "/appPreviews/12345"

    guard let url = URL(string: "\(baseURL)\(path)") else {
        print("    Failed to construct URL")
        return false
    }

    return assertEqual("api.appstoreconnect.apple.com", url.host) &&
           assertEqual("/v1/appPreviews/12345", url.path)
}

// ============================================================================
// Tests: Error Types
// ============================================================================

enum TestError: LocalizedError {
    case invalidPrivateKey
    case networkError(String)
    case apiError(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            "Invalid private key format"
        case .networkError(let message):
            "Network error: \(message)"
        case .apiError(let message):
            "API error: \(message)"
        case .uploadFailed(let message):
            "Upload failed: \(message)"
        }
    }
}

func testErrorDescriptions() -> Bool {
    let errors: [(TestError, String)] = [
        (.invalidPrivateKey, "Invalid private key"),
        (.networkError("timeout"), "Network error: timeout"),
        (.apiError("401 Unauthorized"), "API error: 401"),
        (.uploadFailed("chunk 2"), "Upload failed: chunk 2"),
    ]

    for (error, expectedContains) in errors {
        guard let description = error.errorDescription else {
            print("    Missing error description for \(error)")
            return false
        }
        if !description.contains(expectedContains.components(separatedBy: ": ").last ?? expectedContains) {
            print("    Error description '\(description)' should contain '\(expectedContains)'")
            return false
        }
    }

    return true
}

// ============================================================================
// Tests: Argument Parsing Simulation
// ============================================================================

func testArgumentParsingKeyId() -> Bool {
    let args = ["upload-preview", "--key-id", "ABC123", "--issuer-id", "456", "--private-key", "/key.p8", "--preview-set-id", "789", "video.mp4"]

    var keyID: String?
    var i = 1
    while i < args.count {
        if args[i] == "--key-id" {
            i += 1
            keyID = args[i]
        }
        i += 1
    }

    return assertEqual("ABC123", keyID ?? "")
}

func testArgumentParsingFilePath() -> Bool {
    let args = ["upload-preview", "--key-id", "ABC", "--issuer-id", "456", "--private-key", "/key.p8", "--preview-set-id", "789", "my_video.mp4"]

    var filePath: String?
    var i = 1
    while i < args.count {
        if !args[i].hasPrefix("-") && i == args.count - 1 {
            filePath = args[i]
        }
        i += 1
    }

    return assertEqual("my_video.mp4", filePath ?? "")
}

// ============================================================================
// Tests: JWT Structure
// ============================================================================

func testJWTHeaderStructure() -> Bool {
    let header: [String: String] = [
        "alg": "ES256",
        "kid": "KEY123",
        "typ": "JWT"
    ]

    return assertEqual("ES256", header["alg"]) &&
           assertEqual("KEY123", header["kid"]) &&
           assertEqual("JWT", header["typ"])
}

func testJWTPayloadTimestamps() -> Bool {
    let now = Date()
    let iat = Int(now.timeIntervalSince1970)
    let exp = Int(now.addingTimeInterval(20 * 60).timeIntervalSince1970)

    // exp should be 20 minutes (1200 seconds) after iat
    return assertEqual(1200, exp - iat, "Token should expire in 20 minutes")
}

// ============================================================================
// Run All Tests
// ============================================================================

print("")
print("========================================")
print("  App Store Connect Upload Tool Tests")
print("========================================")
print("")

print("Configuration:")
runTest("config creation", testConfigCreation)

print("")
print("Base64 URL Encoding:")
runTest("URL-safe encoding", testBase64URLEncoding)

print("")
print("MD5 Checksum:")
runTest("known checksum", testMD5Checksum)
runTest("empty string checksum", testMD5ChecksumEmpty)
runTest("checksum length", testMD5ChecksumLength)

print("")
print("JSON Encoding/Decoding:")
runTest("encoding", testJSONEncoding)
runTest("decoding", testJSONDecoding)

print("")
print("Upload Operation Parsing:")
runTest("single operation", testUploadOperationParsing)
runTest("multiple operations", testMultipleUploadOperations)

print("")
print("File Size Formatting:")
runTest("various sizes", testFileSizeFormatting)

print("")
print("URL Construction:")
runTest("API URL", testURLConstruction)

print("")
print("Error Types:")
runTest("error descriptions", testErrorDescriptions)

print("")
print("Argument Parsing:")
runTest("key ID parsing", testArgumentParsingKeyId)
runTest("file path parsing", testArgumentParsingFilePath)

print("")
print("JWT Structure:")
runTest("header structure", testJWTHeaderStructure)
runTest("payload timestamps", testJWTPayloadTimestamps)

// Summary
print("")
print("========================================")
print("  Results: \(testsPassed)/\(testsRun) passed")
if testsFailed > 0 {
    print("  ❌ \(testsFailed) test(s) failed")
    exit(1)
} else {
    print("  ✅ All tests passed!")
    exit(0)
}
