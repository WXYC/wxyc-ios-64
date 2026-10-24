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
import PlaylistTesting
import SwiftUI
@testable import Artwork
@testable import Caching

private let logoURL = URL(string: "https://example.com/hogwash.png")!

private func program(squareURL: URL?) -> SpecialtyShowRef {
    .stub(squareURL: squareURL)
}

@Suite("SpecialtyArtwork")
struct SpecialtyArtworkTests {

    @Test("Chooses the logo URL only when the program has one")
    func logoURLSelection() {
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: logoURL)) == logoURL)
        #expect(SpecialtyArtwork.logoURL(for: program(squareURL: nil)) == nil)
    }
}

@Suite("SpecialtyArtwork.logo(for:)")
struct SpecialtyLogoEntryPointTests {

    private func makeCache() -> CacheCoordinator {
        CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
    }

    @Test("A second call for the same program is served from the cache")
    func secondCallDoesNotRefetch() async {
        let session = MockWebSession()
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!
        let cache = makeCache()
        let hogwash = program(squareURL: logoURL)

        let first = await SpecialtyArtwork.logo(for: hogwash, cache: cache, session: session)
        let second = await SpecialtyArtwork.logo(for: hogwash, cache: cache, session: session)

        #expect(first != nil)
        #expect(second != nil)
        #expect(session.requestedURLs == [logoURL])
    }

    @Test("A program with no logo URL loads nothing and returns nil")
    func noLogoURL() async {
        let session = MockWebSession()
        session.dataToReturn = CGImage.testImage.pngDataCompatibility!

        let image = await SpecialtyArtwork.logo(for: program(squareURL: nil), cache: makeCache(), session: session)

        #expect(image == nil)
        #expect(session.requestedURLs.isEmpty)
    }

    @Test("A failed load returns nil instead of throwing, so the caller draws the tile")
    func failedLoadReturnsNil() async {
        let session = MockWebSession()
        session.errorToThrow = ServiceError.noResults

        let image = await SpecialtyArtwork.logo(for: program(squareURL: logoURL), cache: makeCache(), session: session)

        #expect(image == nil)
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

@Suite("SpecialtyArtwork.logo(for:maxPixelSize:)")
struct SizedLogoTests {

    private func makeCache() -> CacheCoordinator {
        CacheCoordinator(cache: DiskCache(subdirectory: "test-\(UUID().uuidString)"))
    }

    private func source(side: Int) -> Data {
        createBorderedImage(
            size: CGSize(width: side, height: side),
            borderColor: .white, contentColor: .blue, top: 0, bottom: 0, left: 0, right: 0
        ).pngDataCompatibility!
    }

    @Test(
        "The logo is decoded no larger than the requested pixel size, never at full size; a smaller one keeps its size",
        arguments: [
            (source: 1024, maxPixelSize: 180, expected: 180),
            (source: 1024, maxPixelSize: 300, expected: 300),
            // The large widget's art slot (120 points at 3x).
            (source: 1024, maxPixelSize: 360, expected: 360),
            (source: 200, maxPixelSize: 300, expected: 200),
        ]
    )
    func downsamplesToTheRequestedSize(source side: Int, maxPixelSize: Int, expected: Int) async throws {
        let session = MockWebSession()
        session.dataToReturn = source(side: side)

        let image = try #require(await SpecialtyArtwork.logo(
            for: program(squareURL: logoURL), maxPixelSize: maxPixelSize, cache: makeCache(), session: session
        ))

        #expect(max(image.width, image.height) == expected)
    }

    @Test("A second size is served from the cached bytes without another download")
    func reusesTheCachedBytes() async throws {
        let session = MockWebSession()
        session.dataToReturn = source(side: 1024)
        let cache = makeCache()

        let small = try #require(await SpecialtyArtwork.logo(for: program(squareURL: logoURL), maxPixelSize: 120, cache: cache, session: session))
        let large = try #require(await SpecialtyArtwork.logo(for: program(squareURL: logoURL), maxPixelSize: 300, cache: cache, session: session))

        #expect(session.requestedURLs == [logoURL])
        #expect(small.width == 120)
        #expect(large.width == 300)
    }

    @Test("A program with no logo, or a failed download, has no logo to draw")
    func absentLogo() async {
        let session = MockWebSession()
        session.errorToThrow = ServiceError.noResults

        #expect(await SpecialtyArtwork.logo(for: program(squareURL: nil), maxPixelSize: 300, cache: makeCache(), session: session) == nil)
        #expect(await SpecialtyArtwork.logo(for: program(squareURL: logoURL), maxPixelSize: 300, cache: makeCache(), session: session) == nil)
        #expect(session.requestedURLs == [logoURL])
    }
}

@Suite("SpecialtyArtworkView")
@MainActor
struct SpecialtyArtworkViewTests {

    /// Two programs with no server logo URL and no bundled logo, so only the program tells them apart.
    private let first = SpecialtyShowRef.stub()
    private let second = SpecialtyShowRef.untaggedStub

    /// Re-evaluates `SpecialtyArtworkView.body` on every render by changing an input the parent passes down.
    private struct Host: View {
        let program: SpecialtyShowRef
        let pass: Int
        let resolve: @Sendable (SpecialtyShowRef) async -> CGImage?

        var body: some View {
            SpecialtyArtworkView(program: program, size: 20, resolve: resolve)
                .overlay(alignment: .topLeading) { Color.clear.frame(width: CGFloat(pass + 1), height: 1) }
        }
    }

    private func solid(red: Double, green: Double, blue: Double) -> CGImage {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }

    /// The center pixel of the rendered view.
    private func centerPixel(_ renderer: ImageRenderer<Host>) -> [UInt8]? {
        guard let image = renderer.cgImage else { return nil }
        return image.rgba(atX: image.width / 2, y: image.height / 2)
    }

    /// Renders the host repeatedly, letting the view's task run in between, until the center pixel is `expected`
    /// (or a bounded timeout passes, leaving the caller's assertion to report the mismatch).
    private func render(_ renderer: ImageRenderer<Host>, program: SpecialtyShowRef, pass: inout Int,
                        resolve: @escaping @Sendable (SpecialtyShowRef) async -> CGImage?,
                        until expected: [UInt8]) async {
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            pass += 1
            renderer.content = Host(program: program, pass: pass, resolve: resolve)
            _ = renderer.cgImage
            try? await Task.sleep(for: .milliseconds(20))
        } while centerPixel(renderer) != expected && ContinuousClock.now < deadline
    }

    @Test("Many body evaluations for one program resolve once, and the resolved image is drawn")
    func resolvesOncePerProgram() async {
        let calls = Mutex(0)
        let red = solid(red: 1, green: 0, blue: 0)
        let resolve: @Sendable (SpecialtyShowRef) async -> CGImage? = { _ in
            calls.withLock { $0 += 1 }
            return red
        }
        var pass = 0
        let renderer = ImageRenderer(content: Host(program: first, pass: pass, resolve: resolve))

        await render(renderer, program: first, pass: &pass, resolve: resolve, until: [255, 0, 0, 255])
        for _ in 0..<5 {
            pass += 1
            renderer.content = Host(program: first, pass: pass, resolve: resolve)
            _ = renderer.cgImage
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(calls.withLock { $0 } == 1)
        #expect(centerPixel(renderer) == [255, 0, 0, 255])
    }

    @Test("Changing the program resolves again, and each program shows its own result, even with no server URL")
    func changingProgramResolvesAgain() async {
        let requested = Mutex<[String]>([])
        let red = solid(red: 1, green: 0, blue: 0)
        let blue = solid(red: 0, green: 0, blue: 1)
        let resolve: @Sendable (SpecialtyShowRef) async -> CGImage? = { program in
            requested.withLock { $0.append(program.slug) }
            return program.slug == "hogwash" ? red : blue
        }
        var pass = 0
        let renderer = ImageRenderer(content: Host(program: first, pass: pass, resolve: resolve))

        await render(renderer, program: first, pass: &pass, resolve: resolve, until: [255, 0, 0, 255])
        let firstPixel = centerPixel(renderer)
        await render(renderer, program: second, pass: &pass, resolve: resolve, until: [0, 0, 255, 255])
        let secondPixel = centerPixel(renderer)

        #expect(requested.withLock { $0 } == [first.slug, second.slug])
        #expect(firstPixel == [255, 0, 0, 255])
        #expect(secondPixel == [0, 0, 255, 255])
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

/// Records the size its single child reports for the proposal it was given.
private struct SizeRecorder: Layout {
    let box: SizeBox

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        box.size = subviews[0].sizeThatFits(proposal)
        return box.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

private final class SizeBox: @unchecked Sendable {
    var size = CGSize.zero
}

@MainActor
private func reportedSize(imageWidth: Int, imageHeight: Int, slot: CGFloat) -> CGSize {
    let context = CGContext(
        data: nil, width: imageWidth, height: imageHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let image = context.makeImage()!
    let box = SizeBox()
    let view = SizeRecorder(box: box) {
        SquareFill { Image(decorative: image, scale: 1).resizable().scaledToFill() }
    }
    .frame(width: slot, height: slot)
    let renderer = ImageRenderer(content: view)
    _ = renderer.cgImage
    return box.size
}

@Suite("SquareFill")
@MainActor
struct SquareFillTests {
    @Test("A logo of any aspect ratio stays inside a square proposal", arguments: [
        (300, 100), (100, 300), (100, 100), (1200, 800),
    ])
    func staysInsideSlot(width: Int, height: Int) {
        let size = reportedSize(imageWidth: width, imageHeight: height, slot: 120)
        #expect(abs(size.width - 120) < 0.5)
        #expect(abs(size.height - 120) < 0.5)
    }
}
