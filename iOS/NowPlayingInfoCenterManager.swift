//
//  NowPlayingInfoCenterManager.swift
//  WXYC
//
//  Created by Jake Bromberg on 2/15/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import UI
import Foundation
import MediaPlayer

final class NowPlayingInfoCenterManager: NowPlayingObserver {
    public static let shared = NowPlayingInfoCenterManager()
    
    public func update(nowPlayingItem: NowPlayingItem?) {
        Task {
            await self.update(playcut: nowPlayingItem?.playcut)
            await self.update(artwork: nowPlayingItem?.artwork)
        }
    }

    @MainActor
    private func update(playcut: Playcut?) async {
        await MainActor.run { @MainActor in
            let playcutMediaItems = playcut.playcutMediaItems
            
            if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
            }
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo?.update(with: playcutMediaItems)
            MPNowPlayingInfoCenter.default().playbackState = RadioPlayerController.shared.isPlaying ? .playing : .paused
        }
    }

    @MainActor
    private func update(artwork: UIImage?) async {
        if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] =
            self.mediaItemArtwork(from: artwork)
    }
    
    @MainActor
    private func mediaItemArtwork(from image: UIImage?) -> MPMediaItemArtwork {
        if let image {
            let screenWidth = UIScreen.main.bounds.size.width
            let boundsSize = CGSize(width: screenWidth, height: screenWidth)
            
            return MPMediaItemArtwork(boundsSize: boundsSize) { _ in
                return image
            }
        } else {
            return Self.defaultArt()
        }
    }
    
    @MainActor
    private static func defaultArt() -> MPMediaItemArtwork {
        return MPMediaItemArtwork(boundsSize: UIImage.placeholder.size) { size in
            UIImage.placeholder
        }
    }
}

extension Optional where Wrapped == Playcut {
    var playcutMediaItems: [String: Any] {
        if case .some(let playcut) = self {
            return [
                MPMediaItemPropertyArtist : playcut.artistName,
                MPMediaItemPropertyTitle : playcut.songTitle,
                MPMediaItemPropertyAlbumTitle : playcut.releaseTitle ?? "",
            ]
        } else {
            return [
                MPMediaItemPropertyArtist : RadioStation.WXYC.name,
                MPMediaItemPropertyTitle : RadioStation.WXYC.secondaryName,
                MPMediaItemPropertyAlbumTitle : "",
            ]
        }
    }
}

extension Dictionary {
    @MainActor
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
    func overlay(with overlay: UIImage) -> UIImage? {
        // Use the size of the background image or determine a custom size.
        let size = overlay.size

        // Begin a new image context with the desired options.
        UIGraphicsBeginImageContextWithOptions(size, false, overlay.scale)
        
        // Draw the background image.
        overlay.draw(in: CGRect(origin: .zero, size: size))
        
        // Draw the overlay image.
        // You can adjust the frame if you want to position it differently.
        overlay.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: 1.0)
        
        // Capture the composed image.
        let composedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return composedImage
    }
    
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
