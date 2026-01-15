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

    init(
        infoCenter: NowPlayingInfoCenterProtocol = MPNowPlayingInfoCenter.default(),
        boundsSize: CGSize
    ) {
        self.infoCenter = infoCenter
        self.boundsSize = boundsSize
    }

    // MARK: - Public API

    /// Update the track metadata and artwork in the Now Playing info center.
    func handleNowPlayingItem(_ item: NowPlayingItem) {
        update(playcut: item.playcut)
        update(artwork: item.artwork)
    }
        
    // MARK: - Private
        
    private func update(playcut: Playcut) {
        let playcutMediaItems = playcut.playcutMediaItems
        
        if infoCenter.nowPlayingInfo == nil {
            infoCenter.nowPlayingInfo = [:]
        }
        
        infoCenter.nowPlayingInfo?.update(with: playcutMediaItems)
    }

    private func update(artwork: UIImage?) {
        let artwork = artwork ?? UIImage.placeholder
        if infoCenter.nowPlayingInfo == nil {
            infoCenter.nowPlayingInfo = [:]
        }

        infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] =
            self.mediaItemArtwork(from: artwork, boundsSize: boundsSize)
    }
    
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
    static let placeholder: UIImage = {
        let backgroundImage: CGImage = #imageLiteral(resourceName: "background").cgImage!
        let overlayImage = logoImage.cgImage!
            .resize(to: backgroundImage.size)
        return UIImage(cgImage: backgroundImage.overlay(with: overlayImage)!)
    }()
    
    static let logoImage = UIImage(named: "logo.pdf")!
        .withRenderingMode(.alwaysOriginal)
        .scaleAndCenter(scale: 0.90)
}
    
extension CGImage {
    func overlay(with overlay: CGImage) -> CGImage? {
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
    
    func resize(to newSize: CGSize) -> CGImage {
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

    var size: CGSize {
        .init(width: CGFloat(width), height: CGFloat(height))
    }
}

extension UIImage {
    func scaleAndCenter(scale: CGFloat) -> UIImage {
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
