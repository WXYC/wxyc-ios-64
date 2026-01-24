//
//  upload-preview.swift
//  WXYC
//
//  Uploads app preview videos to App Store Connect using the REST API.
//  Handles authentication, chunked uploads, and commit verification.
//
//  Created by Jake on 01/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import CryptoKit

// MARK: - Configuration

struct AppStoreConnectConfig {
    let keyID: String
    let issuerID: String
    let privateKeyPath: String
    let appID: String

    var privateKey: String {
        get throws {
            try String(contentsOfFile: privateKeyPath, encoding: .utf8)
                .replacing("-----BEGIN PRIVATE KEY-----", with: "")
                .replacing("-----END PRIVATE KEY-----", with: "")
                .split(separator: "\n")
                .joined()
        }
    }
}

// MARK: - JWT Token Generation

struct JWTGenerator {
    let config: AppStoreConnectConfig

    func generateToken() throws -> String {
        let header = [
            "alg": "ES256",
            "kid": config.keyID,
            "typ": "JWT"
        ]

        let now = Date()
        let payload: [String: Any] = [
            "iss": config.issuerID,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(20 * 60).timeIntervalSince1970),
            "aud": "appstoreconnect-v1"
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerBase64 = headerData.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")

        let payloadBase64 = payloadData.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")

        let signingInput = "\(headerBase64).\(payloadBase64)"

        // Load private key and sign
        let privateKeyString = try config.privateKey
        guard let privateKeyData = Data(base64Encoded: privateKeyString) else {
            throw AppStoreConnectError.invalidPrivateKey
        }

        let privateKey = try P256.Signing.PrivateKey(derRepresentation: privateKeyData)
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        let signatureBase64 = signature.rawRepresentation.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")

        return "\(signingInput).\(signatureBase64)"
    }
}

// MARK: - API Models

struct AppPreviewSetResponse: Codable {
    let data: AppPreviewSetData
}

struct AppPreviewSetData: Codable {
    let id: String
    let type: String
}

struct AppPreviewCreateRequest: Codable {
    let data: AppPreviewCreateData
}

struct AppPreviewCreateData: Codable {
    let type: String
    let attributes: AppPreviewAttributes
    let relationships: AppPreviewRelationships
}

struct AppPreviewAttributes: Codable {
    let fileName: String
    let fileSize: Int
    let mimeType: String?
    let previewFrameTimeCode: String?
}

struct AppPreviewRelationships: Codable {
    let appPreviewSet: AppPreviewSetRelationship
}

struct AppPreviewSetRelationship: Codable {
    let data: AppPreviewSetRelationshipData
}

struct AppPreviewSetRelationshipData: Codable {
    let type: String
    let id: String
}

struct AppPreviewResponse: Codable {
    let data: AppPreviewData
}

struct AppPreviewData: Codable {
    let id: String
    let type: String
    let attributes: AppPreviewResponseAttributes?
}

struct AppPreviewResponseAttributes: Codable {
    let assetDeliveryState: AssetDeliveryState?
    let uploadOperations: [UploadOperation]?
}

struct AssetDeliveryState: Codable {
    let state: String
    let errors: [AssetError]?
}

struct AssetError: Codable {
    let code: String?
    let description: String?
}

struct UploadOperation: Codable {
    let method: String
    let url: String
    let length: Int
    let offset: Int
    let requestHeaders: [RequestHeader]
}

struct RequestHeader: Codable {
    let name: String
    let value: String
}

struct AppPreviewCommitRequest: Codable {
    let data: AppPreviewCommitData
}

struct AppPreviewCommitData: Codable {
    let type: String
    let id: String
    let attributes: AppPreviewCommitAttributes
}

struct AppPreviewCommitAttributes: Codable {
    let sourceFileChecksum: String
    let uploaded: Bool
}

// MARK: - Errors

enum AppStoreConnectError: LocalizedError {
    case invalidPrivateKey
    case networkError(String)
    case apiError(String)
    case uploadFailed(String)
    case invalidResponse

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
        case .invalidResponse:
            "Invalid response from API"
        }
    }
}

// MARK: - App Store Connect Client

actor AppStoreConnectClient {
    private let config: AppStoreConnectConfig
    private let baseURL = "https://api.appstoreconnect.apple.com/v1"
    private var token: String?
    private var tokenExpiry: Date?

    init(config: AppStoreConnectConfig) {
        self.config = config
    }

    private func getToken() throws -> String {
        if let token, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        let generator = JWTGenerator(config: config)
        let newToken = try generator.generateToken()
        token = newToken
        tokenExpiry = Date().addingTimeInterval(15 * 60)
        return newToken
    }

    private func makeRequest<T: Decodable>(
        method: String,
        path: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        let token = try getToken()
        let url = URL(string: "\(baseURL)\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppStoreConnectError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Public API

    /// Create an app preview reservation
    func createAppPreview(
        previewSetID: String,
        fileName: String,
        fileSize: Int
    ) async throws -> AppPreviewResponse {
        let request = AppPreviewCreateRequest(
            data: AppPreviewCreateData(
                type: "appPreviews",
                attributes: AppPreviewAttributes(
                    fileName: fileName,
                    fileSize: fileSize,
                    mimeType: "video/mp4",
                    previewFrameTimeCode: "00:00:05:00"
                ),
                relationships: AppPreviewRelationships(
                    appPreviewSet: AppPreviewSetRelationship(
                        data: AppPreviewSetRelationshipData(
                            type: "appPreviewSets",
                            id: previewSetID
                        )
                    )
                )
            )
        )

        return try await makeRequest(
            method: "POST",
            path: "/appPreviews",
            body: request
        )
    }

    /// Upload a chunk to the specified URL
    func uploadChunk(
        operation: UploadOperation,
        fileHandle: FileHandle
    ) async throws {
        var request = URLRequest(url: URL(string: operation.url)!)
        request.httpMethod = operation.method

        for header in operation.requestHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        // Read the chunk
        try fileHandle.seek(toOffset: UInt64(operation.offset))
        let chunkData = fileHandle.readData(ofLength: operation.length)

        request.httpBody = chunkData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppStoreConnectError.uploadFailed("Chunk upload failed at offset \(operation.offset)")
        }
    }

    /// Commit the upload
    func commitUpload(
        previewID: String,
        checksum: String
    ) async throws -> AppPreviewResponse {
        let request = AppPreviewCommitRequest(
            data: AppPreviewCommitData(
                type: "appPreviews",
                id: previewID,
                attributes: AppPreviewCommitAttributes(
                    sourceFileChecksum: checksum,
                    uploaded: true
                )
            )
        )

        return try await makeRequest(
            method: "PATCH",
            path: "/appPreviews/\(previewID)",
            body: request
        )
    }

    /// Get the current status of an app preview
    func getAppPreview(id: String) async throws -> AppPreviewResponse {
        try await makeRequest(method: "GET", path: "/appPreviews/\(id)")
    }

    /// List app preview sets for a localization
    func listAppPreviewSets(localizationID: String) async throws -> [AppPreviewSetData] {
        struct Response: Codable {
            let data: [AppPreviewSetData]
        }

        let response: Response = try await makeRequest(
            method: "GET",
            path: "/appStoreVersionLocalizations/\(localizationID)/appPreviewSets"
        )
        return response.data
    }
}

// MARK: - Upload Manager

struct UploadManager {
    let client: AppStoreConnectClient

    func uploadPreview(
        filePath: String,
        previewSetID: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        let fileURL = URL(fileURLWithPath: filePath)
        let fileName = fileURL.lastPathComponent

        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
        guard let fileSize = fileAttributes[.size] as? Int else {
            throw AppStoreConnectError.uploadFailed("Could not determine file size")
        }

        print("📁 File: \(fileName) (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))")

        // Step 1: Create reservation
        print("📝 Creating upload reservation...")
        let reservation = try await client.createAppPreview(
            previewSetID: previewSetID,
            fileName: fileName,
            fileSize: fileSize
        )

        guard let operations = reservation.data.attributes?.uploadOperations,
              !operations.isEmpty else {
            throw AppStoreConnectError.invalidResponse
        }

        let previewID = reservation.data.id
        print("✅ Reservation created: \(previewID)")
        print("📦 Upload will be split into \(operations.count) chunk(s)")

        // Step 2: Upload chunks
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var completedChunks = 0
        let totalChunks = operations.count

        try await withThrowingTaskGroup(of: Void.self) { group in
            for operation in operations {
                group.addTask {
                    try await client.uploadChunk(operation: operation, fileHandle: fileHandle)
                }
            }

            for try await _ in group {
                completedChunks += 1
                let progress = Double(completedChunks) / Double(totalChunks)
                progressHandler?(progress)
                print("⬆️  Uploaded chunk \(completedChunks)/\(totalChunks)")
            }
        }

        // Step 3: Calculate checksum
        print("🔐 Calculating checksum...")
        let fileData = try Data(contentsOf: fileURL)
        let checksum = Insecure.MD5.hash(data: fileData)
            .map { String(format: "%02hhx", $0) }
            .joined()

        // Step 4: Commit upload
        print("✅ Committing upload...")
        _ = try await client.commitUpload(previewID: previewID, checksum: checksum)

        // Step 5: Poll for completion
        print("⏳ Waiting for processing...")
        var attempts = 0
        let maxAttempts = 60 // 5 minutes at 5-second intervals

        while attempts < maxAttempts {
            try await Task.sleep(for: .seconds(5))
            attempts += 1

            let status = try await client.getAppPreview(id: previewID)
            let state = status.data.attributes?.assetDeliveryState?.state ?? "UNKNOWN"

            switch state {
            case "COMPLETE":
                print("🎉 Upload complete!")
                return previewID
            case "FAILED":
                let errors = status.data.attributes?.assetDeliveryState?.errors ?? []
                let errorMessages = errors.map { $0.description ?? $0.code ?? "Unknown" }.joined(separator: ", ")
                throw AppStoreConnectError.uploadFailed("Processing failed: \(errorMessages)")
            default:
                print("   Status: \(state) (attempt \(attempts)/\(maxAttempts))")
            }
        }

        throw AppStoreConnectError.uploadFailed("Processing timed out")
    }
}

// MARK: - CLI

func printUsage() {
    print("""
    Usage: upload-preview.swift [OPTIONS] <video-file>

    Upload an app preview video to App Store Connect.

    REQUIRED OPTIONS:
        --key-id <id>           App Store Connect API Key ID
        --issuer-id <id>        App Store Connect Issuer ID
        --private-key <path>    Path to API private key (.p8 file)
        --preview-set-id <id>   App Preview Set ID to upload to

    OPTIONAL:
        --app-id <id>           App ID (for reference)
        -h, --help              Show this help message

    SETUP:
        1. Create an API key in App Store Connect:
           https://appstoreconnect.apple.com/access/integrations/api

        2. Download the .p8 private key file

        3. Note your Key ID and Issuer ID from the API Keys page

        4. Find your App Preview Set ID:
           - Use the API to list your app's versions and localizations
           - Or inspect network requests in App Store Connect web UI

    EXAMPLE:
        ./upload-preview.swift \\
            --key-id ABCD123456 \\
            --issuer-id 12345678-1234-1234-1234-123456789012 \\
            --private-key ~/AuthKey_ABCD123456.p8 \\
            --preview-set-id 12345678-1234-1234-1234-123456789012 \\
            preview_iphone-6.9_portrait.mp4

    """)
}

func runCLI() async {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        printUsage()
        exit(1)
    }

    // Parse arguments
    var keyID: String?
    var issuerID: String?
    var privateKeyPath: String?
    var appID: String?
    var previewSetID: String?
    var filePath: String?

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--key-id":
            i += 1
            keyID = args[i]
        case "--issuer-id":
            i += 1
            issuerID = args[i]
        case "--private-key":
            i += 1
            privateKeyPath = args[i]
        case "--app-id":
            i += 1
            appID = args[i]
        case "--preview-set-id":
            i += 1
            previewSetID = args[i]
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            if !args[i].hasPrefix("-") {
                filePath = args[i]
            }
        }
        i += 1
    }

    // Validate required arguments
    guard let keyID, let issuerID, let privateKeyPath, let previewSetID, let filePath else {
        print("❌ Missing required arguments")
        printUsage()
        exit(1)
    }

    let config = AppStoreConnectConfig(
        keyID: keyID,
        issuerID: issuerID,
        privateKeyPath: privateKeyPath,
        appID: appID ?? ""
    )

    let client = AppStoreConnectClient(config: config)
    let manager = UploadManager(client: client)

    do {
        let previewID = try await manager.uploadPreview(
            filePath: filePath,
            previewSetID: previewSetID
        ) { progress in
            let percent = Int(progress * 100)
            print("\rProgress: \(percent)%", terminator: "")
            fflush(stdout)
        }

        print("\n✅ Successfully uploaded preview: \(previewID)")
    } catch {
        print("\n❌ Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Entry point for script execution
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runCLI()
    semaphore.signal()
}
semaphore.wait()
