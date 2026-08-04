//
//  NowPlayingInfoCenterManager.swift
//  WXYC
//
//  Manages MPNowPlayingInfoCenter metadata updates.
//
//  Created by Jake Bromberg on 02/15/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Foundation
import Logger
import MediaPlayer
import Playlist

// MARK: - NowPlayingInfoCenter Protocol

/// Protocol abstracting MPNowPlayingInfoCenter for testability.
@MainActor
protocol NowPlayingInfoCenterProtocol {
    var nowPlayingInfo: [String: Any]? { get set }
    var playbackState: MPNowPlayingPlaybackState { get set }
}

extension MPNowPlayingInfoCenter: NowPlayingInfoCenterProtocol {}

// MARK: - NowPlayingInfoCenterManager

/// Manages the system's Now Playing info center, updating playback state and track metadata.
/// This class is a simple processor - callers are responsible for observing streams and
/// calling the handler methods.
@MainActor
final class NowPlayingInfoCenterManager {
    private var infoCenter: NowPlayingInfoCenterProtocol
    private let boundsSize: CGSize

    /// Local mirror of the dictionary this manager last wrote to `infoCenter`.
    ///
    /// Reading `MPNowPlayingInfoCenter.nowPlayingInfo` is a synchronous cross-process
    /// (XPC) round-trip to `mediaserverd` that can block the main thread for seconds
    /// under contention — the cause of the IOS-3P AppHang. Because this manager is the
    /// sole writer of the app's Now Playing info, mutating this cache and writing it back
    /// is equivalent to the read-modify-write the getter used to perform, without ever
    /// blocking the main thread on the getter.
    private var cachedInfo: [String: Any]?

    init(
        infoCenter: NowPlayingInfoCenterProtocol = MPNowPlayingInfoCenter.default(),
        boundsSize: CGSize
    ) {
        self.infoCenter = infoCenter
        self.boundsSize = boundsSize
    }

    /// Write `info` to both the local cache and the system info center in one place,
    /// so the two never diverge and the getter is never consulted.
    private func commit(_ info: [String: Any]) {
        cachedInfo = info
        infoCenter.nowPlayingInfo = info
    }

    /// Seed a mutable copy from the cache, apply `body`, and commit the result in a
    /// single info-center write. Centralizes the read-modify-write the getter used to
    /// perform so every mutation stays one XPC round-trip on the main thread.
    private func mutate(_ body: (inout [String: Any]) -> Void) {
        var info = cachedInfo ?? [:]
        body(&info)
        commit(info)
    }

    // MARK: - Public API

    /// Update the track metadata and artwork in the Now Playing info center.
    ///
    /// Metadata and artwork land in a single `commit`, so a track change is one
    /// info-center write rather than two back-to-back XPC round-trips on the main thread.
    func handleNowPlayingItem(_ item: NowPlayingItem) {
        mutate { info in
            info.update(with: item.playcut.playcutMediaItems)
            info[MPMediaItemPropertyArtwork] = self.mediaItemArtwork(from: item.artwork, boundsSize: self.boundsSize)
        }
    }

    /// Reflect the current playback state in MPNowPlayingInfoCenter.
    ///
    /// On macOS / Mac Catalyst this is required for the app to be selected as the
    /// active Now Playing source: the system can't infer it from AVAudioSession the
    /// way it does on iOS. Without it, Control Center's Now Playing widget stays
    /// empty and the Music app receives the media keys instead.
    func setPlaybackState(isPlaying: Bool) {
        mutate { $0[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0 }
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    /// Update the playback position for the Lock Screen scrub bar.
    /// Setting `isLiveStream` to false enables the scrub bar in Control Center and Lock Screen.
    func updatePlaybackPosition(secondsBehindLive: TimeInterval, maxLookback: TimeInterval) {
        mutate { info in
            info[MPMediaItemPropertyPlaybackDuration] = maxLookback
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = maxLookback - secondsBehindLive
            info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        }
    }

    /// Reset to live stream mode (no scrub bar).
    ///
    /// Mirrors the previous optional-chained semantics: if nothing has been set yet,
    /// there is no position to clear, so this is a no-op.
    func clearPlaybackPosition() {
        guard var info = cachedInfo else { return }
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
        info.removeValue(forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime)
        commit(info)
    }

    // MARK: - Private

    private func mediaItemArtwork(from image: UIImage?, boundsSize: CGSize) -> MPMediaItemArtwork {
        // Capture the resolved image on MainActor before creating the artwork.
        // The closure will be called by the system on an arbitrary queue.
        let resolvedImage = image ?? UIImage.placeholder
        return MPMediaItemArtwork(boundsSize: boundsSize) { @Sendable _ in
            resolvedImage
        }
    }
}
        
extension Playcut {
    var playcutMediaItems: [String: Any] {
        return [
            MPMediaItemPropertyArtist : self.artistName,
            MPMediaItemPropertyTitle : self.songTitle,
            MPMediaItemPropertyAlbumTitle : self.releaseTitle ?? "",
        ]
    }
}

extension Dictionary {
    // TODO: Replace with new `mutating func merging` method
    mutating func update(with dict: Dictionary<Key, Value>) {
        for (key, value) in dict {
            self[key] = value
        }
    }
}

extension UIImage {
    // `nonisolated` here (and throughout the rest of this file's UIImage/CGImage
    // extensions) is load-bearing, not decorative: this module builds with
    // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a plain `static let`/
    // `func` would otherwise default to the main actor, forcing every access —
    // including this property's first-access CoreImage/Metal compositing —
    // onto the main actor's executor regardless of which thread the caller is
    // on. That was the actual root cause of #740 (Sentry IOS-3M/IOS-14/IOS-19):
    // `WXYCApp.donateSiriIntent()` deferring its work to a `Task` wasn't
    // sufficient on its own, because this property (and everything it calls)
    // was still implicitly main-actor isolated underneath it. Verified
    // empirically: without these annotations, `MainActor.assertIsolated()`
    // inside `donateSiriIntent()`'s `Task` did not trap.
    nonisolated static let placeholder: UIImage = {
        let backgroundImage: CGImage = #imageLiteral(resourceName: "background").cgImage!
        let overlayImage = logoImage.cgImage!
            .resize(to: backgroundImage.size)
        return UIImage(cgImage: backgroundImage.overlay(with: overlayImage)!)
    }()

    nonisolated static let logoImage = UIImage(named: "logo.pdf")!
        .withRenderingMode(.alwaysOriginal)
        .scaleAndCenter(scale: 0.90)
}

extension CGImage {
    nonisolated func overlay(with overlay: CGImage) -> CGImage? {
        Log(.info, "overlaying \(overlay.size) with \(size)")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Log(.error, "Couldn't create CGContext")
            return nil
        }
    
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Draw the background image.
        context.draw(self, in: rect)
        // Optionally set a blend mode if needed:
        context.setBlendMode(.normal)
        // Draw the overlay image on top.
        rect = CGRect(
            x: (self.width - overlay.width) / 2,
            y: (self.height - overlay.height) / 2,
            width: overlay.width,
            height: overlay.height
        )
        context.draw(overlay, in: rect)
    
        // Create a new CGImage from the context.
        return context.makeImage()
    }
    
    nonisolated func resize(to newSize: CGSize) -> CGImage {
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            return self
        }

        let ciImage = CIImage(cgImage: self)
        let scale = (Double)(newSize.width) / (Double)(ciImage.extent.size.width)

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value:scale), forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let outputImage = filter.value(forKey: kCIOutputImageKey) as? CIImage else {
            return self
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(outputImage, from: outputImage.extent) ?? self

    }

    nonisolated var size: CGSize {
        .init(width: CGFloat(width), height: CGFloat(height))
    }
}

extension UIImage {
    nonisolated func scaleAndCenter(scale: CGFloat) -> UIImage {
        // Use the original image size as the canvas size.
        let canvasSize = self.size
        // Compute the scaled size by multiplying the original dimensions by the scale.
        let scaledSize = CGSize(width: self.size.width * scale,
                                height: self.size.height * scale)

        // Create an image renderer using the original image's size.
        let renderer = UIGraphicsImageRenderer(size: canvasSize)

        let newImage = renderer.image { _ in
            // Calculate the origin so the scaled image is centered in the canvas.
            let origin = CGPoint(x: (canvasSize.width - scaledSize.width) / 2,
                                 y: (canvasSize.height - scaledSize.height) / 2)
            // Draw the image in the computed rect.
            self.draw(in: CGRect(origin: origin, size: scaledSize))
        }

        return newImage
    }
}
