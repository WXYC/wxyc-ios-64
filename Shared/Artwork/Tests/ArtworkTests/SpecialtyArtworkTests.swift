//
//  SpecialtyArtworkTests.swift
//  Artwork
//
//  Tests for the specialty program logo: the URL-and-fallback decision and the
//  URL-keyed artwork cache entry point it loads through.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Synchronization
import CoreGraphics
import Core
import Logger
import Playlist
@testable import Artwork
@testable import Caching

private let logoURL = URL(string: "https://example.com/hogwash.png")!

private func program(squareURL: URL?, hasArtwork: Bool = true) -> SpecialtyShowRef {
    SpecialtyShowRef(
        id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW",
        artwork: hasArtwork ? .init(squareURL: squareURL) : nil
    )
}

@Suite("SpecialtyArtwork")
struct SpecialtyArtworkTests {

    @Test("Chooses the logo URL only when the program has one")
    func logoURLSelection() {
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: logoURL)) == logoURL)
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: nil)) == nil)
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: nil, hasArtwork: false)) == nil)
    }

    @Test(
        "Shows the tile unless a logo URL exists and has loaded",
        arguments: [
            (hasURL: false, state: SpecialtyArtwork.LogoState.loading, showsLogo: false),
            (hasURL: false, state: .loaded, showsLogo: false),
            (hasURL: true, state: .loading, showsLogo: false),
            (hasURL: true, state: .failed, showsLogo: false),
            (hasURL: true, state: .loaded, showsLogo: true),
        ]
    )
    func fallbackDecision(hasURL: Bool, state: SpecialtyArtwork.LogoState, showsLogo: Bool) {
        let url = hasURL ? logoURL : nil
        #expect(SpecialtyArtwork.showsLogo(url: url, state: state) == showsLogo)
    }
}

@Suite("CacheCoordinator.image(from:)")
struct URLKeyedArtworkCacheTests {

    private func makeCache() -> CacheCoordinator {
        CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
    }

    @Test("A second request for the same URL is served from the cache")
    func secondRequestDoesNotRefetch() async throws {
        let session = MockWebSession()
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!
        let cache = makeCache()

        _ = try await cache.image(from: logoURL, session: session)
        _ = try await cache.image(from: logoURL, session: session)

        #expect(session.requestedURLs == [logoURL])
    }

    @Test("A second coordinator over the same disk directory serves the logo without a network fetch")
    func persistsAcrossCoordinators() async throws {
        let directory = "test-\(UUID().uuidString)"
        let session = MockWebSession()
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!

        let first = CacheCoordinator(cache: DiskCache(subdirectory: directory))
        _ = try await first.image(from: logoURL, session: session)
        await first.waitForPurge()

        // A fresh coordinator and DiskCache start with an empty in-memory layer, so a hit can only come from disk.
        let second = CacheCoordinator(cache: DiskCache(subdirectory: directory))
        _ = try await second.image(from: logoURL, session: session)

        #expect(session.requestedURLs == [logoURL])
        await second.clearAll()
    }

    @Test(
        "The logo is never trimmed, on the first appearance or from the cache",
        arguments: [
            // A white margin the album-art trimmer would cut (up to 5% per edge).
            (width: 110, height: 110, border: 5),
            // Wider than ArtworkCacheConfiguration.targetWidth, so it is also downsampled.
            (width: 600, height: 400, border: 20),
            (width: 90, height: 150, border: 4),
        ]
    )
    func logoIsStoredUntrimmed(width: Int, height: Int, border: Int) async throws {
        let original = createBorderedImage(
            size: CGSize(width: width, height: height),
            borderColor: .white, contentColor: .blue,
            top: border, bottom: border, left: border, right: border
        )
        let session = MockWebSession()
        session.dataToReturn = original.pngDataCompatibility!
        let directory = "test-\(UUID().uuidString)"

        let first = CacheCoordinator(cache: DiskCache(subdirectory: directory))
        let firstAppearance = try await first.image(from: logoURL, session: session)
        await first.waitForPurge()
        let fromDisk = try await CacheCoordinator(cache: DiskCache(subdirectory: directory))
            .image(from: logoURL, session: session)

        #expect(session.requestedURLs == [logoURL])
        for image in [firstAppearance, fromDisk] {
            // The aspect ratio is kept to within the rounding of a downsample, so no edge was cut.
            let aspect = Double(image.width) / Double(image.height)
            #expect(abs(aspect - Double(width) / Double(height)) < 0.02)
            // The white border is still there (a trim would leave the content color in the corner) ...
            #expect(image.rgba(atX: 1, y: 1) == [255, 255, 255, 255])
            // ... and the content inside it is untouched.
            #expect(image.rgba(atX: image.width / 2, y: image.height / 2) == [0, 0, 255, 255])
        }
        await first.clearAll()
    }

    @Test(
        "A logo wider than the artwork target is downsampled to it, aspect ratio kept, identically on first appearance and from disk; a smaller one keeps its size",
        arguments: [
            // Landscape, portrait and square sources larger than the target.
            (width: 1024, height: 1024, scales: true),
            (width: 1000, height: 600, scales: true),
            (width: 600, height: 1000, scales: true),
            // At and below the target.
            (width: 430, height: 430, scales: false),
            (width: 300, height: 200, scales: false),
            (width: 64, height: 64, scales: false),
        ]
    )
    func logoIsDownsampledToTheArtworkTarget(width: Int, height: Int, scales: Bool) async throws {
        let target = Int(ArtworkCacheConfiguration.targetWidth)
        let original = createBorderedImage(
            size: CGSize(width: width, height: height),
            borderColor: .white, contentColor: .blue, top: 0, bottom: 0, left: 0, right: 0
        )
        let session = MockWebSession()
        session.dataToReturn = original.pngDataCompatibility!
        let directory = "test-\(UUID().uuidString)"

        let first = CacheCoordinator(cache: DiskCache(subdirectory: directory))
        let firstAppearance = try await first.image(from: logoURL, session: session)
        await first.waitForPurge()
        let fromDisk = try await CacheCoordinator(cache: DiskCache(subdirectory: directory))
            .image(from: logoURL, session: session)

        let longest = max(width, height)
        let scale = scales ? Double(target) / Double(longest) : 1
        let expected = (
            width: Double(width) * scale,
            height: Double(height) * scale
        )
        for image in [firstAppearance, fromDisk] {
            #expect(max(image.width, image.height) == (scales ? target : longest))
            #expect(abs(Double(image.width) - expected.width) <= 1)
            #expect(abs(Double(image.height) - expected.height) <= 1)
        }
        #expect(fromDisk.width == firstAppearance.width)
        #expect(fromDisk.height == firstAppearance.height)
        await first.clearAll()
    }

    @Test("A failed download throws and is not cached")
    func failureIsNotCached() async throws {
        let session = MockWebSession()
        session.errorToThrow = ServiceError.noResults
        let cache = makeCache()

        await #expect(throws: (any Error).self) { try await cache.image(from: logoURL, session: session) }

        session.errorToThrow = nil
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!
        _ = try await cache.image(from: logoURL, session: session)
        #expect(session.requestedURLs.count == 2)
    }

    @Test("Undecodable data throws")
    func undecodableDataThrows() async {
        let session = MockWebSession()
        session.dataToReturn = Data("not an image".utf8)

        await #expect(throws: (any Error).self) { try await makeCache().image(from: logoURL, session: session) }
    }
}

@Suite("CacheCoordinator.image(from:) failure logging")
struct URLKeyedArtworkFailureLoggingTests {

    @Test(
        "Cancellation is rethrown but not logged as a failure; a real failure is logged",
        arguments: [
            (error: URLError(.cancelled) as any Error, isLogged: false),
            (error: CancellationError() as any Error, isLogged: false),
            (error: URLError(.timedOut) as any Error, isLogged: true),
        ]
    )
    func cancellationIsNotLogged(error: any Error, isLogged: Bool) async throws {
        // Log destinations are process-wide, so match on a URL no other test uses.
        let url = URL(string: "https://example.com/\(UUID().uuidString).png")!
        let recorder = FailureLogRecorder(matching: url.absoluteString)
        Logger.addDestination(recorder)
        let session = MockWebSession()
        session.errorToThrow = error
        let cache = CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))

        await #expect(throws: (any Error).self) { try await cache.image(from: url, session: session) }

        #expect(recorder.warnings.isEmpty == !isLogged)
    }
}

private final class FailureLogRecorder: LogDestination {
    private let marker: String
    private let storage = Mutex<[String]>([])

    init(matching marker: String) {
        self.marker = marker
    }

    var warnings: [String] { storage.withLock { $0 } }

    func receive(level: LogLevel, category: LogCategory, message: String) {
        guard level == .warning, message.contains(marker) else { return }
        storage.withLock { $0.append(message) }
    }
}

private extension CGImage {
    /// The RGBA bytes of the pixel at (`x`, `y`), measured from the top-left, after drawing into an sRGB bitmap.
    func rgba(atX x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Draw the image offset so the requested pixel lands on the single-pixel context.
        context.draw(self, in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height))
        return pixel
    }
}
