//
//  PlaceholderArtwork.swift
//  WXYC
//
//  The Now Playing placeholder image, split out of NowPlayingInfoCenterManager
//  (where it lived as `UIImage` extensions) so `NowPlayingInfoCenterManager`
//  itself carries no UIKit coupling and builds on the native macOS target.
//
//  The iOS compositing — the WXYC logo laid over the background art — is
//  unchanged and stays under `#if canImport(UIKit)`: it rasterizes the
//  vector logo through `UIGraphicsImageRenderer` (`scaleAndCenter`) before
//  reading its `cgImage`, which a bare `UIImage(named:).cgImage` on the
//  vector-preserving asset would return `nil` for. macOS gets the background art
//  alone for now; compositing there is deferred to the native-target work.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import CoreImage
import Foundation
import Logger
import WXUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The system Now Playing placeholder artwork.
enum PlaceholderArtwork {
    #if canImport(UIKit)
    /// The WXYC logo composited over the background art.
    ///
    /// `nonisolated` is load-bearing, not decorative: this module builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a plain `static let` would
    /// default to the main actor and force this property's first-access
    /// CoreImage/Metal compositing onto the main-actor executor regardless of the
    /// caller's thread — the root cause of #740 (Sentry IOS-3M/IOS-14/IOS-19).
    nonisolated static let image: PlatformImage = {
        let backgroundImage: CGImage = #imageLiteral(resourceName: "background").cgImage!
        let overlayImage = logo.cgImage!
            .resize(to: backgroundImage.size)
        return UIImage(cgImage: backgroundImage.overlay(with: overlayImage)!)
    }()

    /// The WXYC logo, tint-preserved and rasterized (the `scaleAndCenter` render
    /// is what gives the otherwise-vector asset a non-nil `cgImage`).
    private nonisolated static let logo = UIImage(named: "logo.pdf")!
        .withRenderingMode(.alwaysOriginal)
        .scaleAndCenter(scale: 0.90)
    #elseif canImport(AppKit)
    /// The background art. The logo overlay is deferred to the native macOS
    /// target work; a bare background is a correct, if plainer, placeholder.
    nonisolated static let image: PlatformImage = PlatformImage(named: "background") ?? PlatformImage()
    #endif
}

#if canImport(UIKit)
private extension UIImage {
    /// The receiver scaled by `scale` and centered on a canvas its own size —
    /// this render also rasterizes a vector-preserving asset so its `cgImage` is
    /// readable.
    nonisolated func scaleAndCenter(scale: CGFloat) -> UIImage {
        let canvasSize = self.size
        let scaledSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            let origin = CGPoint(
                x: (canvasSize.width - scaledSize.width) / 2,
                y: (canvasSize.height - scaledSize.height) / 2
            )
            self.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}
#endif

extension CGImage {
    /// Composites `overlay` centered on top of the receiver, returning the merged
    /// image (or `nil` if a drawing context can't be created). Pure CoreGraphics,
    /// so it works on every platform.
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
        context.setBlendMode(.normal)
        // Draw the overlay image on top, centered.
        rect = CGRect(
            x: (self.width - overlay.width) / 2,
            y: (self.height - overlay.height) / 2,
            width: overlay.width,
            height: overlay.height
        )
        context.draw(overlay, in: rect)

        return context.makeImage()
    }

    /// Lanczos-resamples the image to `newSize`, preserving the receiver on
    /// failure.
    nonisolated func resize(to newSize: CGSize) -> CGImage {
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            return self
        }

        let ciImage = CIImage(cgImage: self)
        let scale = Double(newSize.width) / Double(ciImage.extent.size.width)

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value: scale), forKey: kCIInputScaleKey)
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
