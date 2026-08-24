//
//  PlatformImage.swift
//  WXUI
//
//  Cross-platform bitmap-image typealias and a SwiftUI Image bridge, so shared
//  views can build a SwiftUI Image from a UIKit or AppKit image without a
//  per-call-site #if branch.
//
//  This resolves to the same underlying type as Core's `Image` typealias
//  (`UIImage`/`NSImage`); it is deliberately redeclared here so WXUI stays a
//  leaf package with no dependency on Core.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
/// The platform's bitmap image type: `UIImage` on UIKit platforms (iOS, tvOS,
/// watchOS, visionOS, Mac Catalyst).
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
/// The platform's bitmap image type: `NSImage` on AppKit platforms (macOS).
public typealias PlatformImage = NSImage
#endif

public extension Image {
    /// Creates a SwiftUI `Image` from a platform image, bridging the
    /// `Image(uiImage:)` / `Image(nsImage:)` split so shared code needn't
    /// branch on the platform at every call site.
    init(platform image: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        self.init(nsImage: image)
        #endif
    }
}

#if canImport(AppKit)
public extension NSImage {
    /// The image's `CGImage`, mirroring `UIImage.cgImage` so shared code can read
    /// a platform image's backing `CGImage` without a per-call-site branch. Uses
    /// the whole image as the proposed rendering rect.
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif
