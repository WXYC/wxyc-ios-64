//
//  ImageCompatability.swift
//  Core
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation

#if canImport(UIKit)
import UIKit
public typealias Image = UIImage

public extension Image {
    // Unified helper to get PNG data in cross‑platform code
    var pngDataCompatibility: Data? { self.pngData() }
    // Unified initializer used when reconstructing from Data
    convenience init?(compatibilityData data: Data) { self.init(data: data) }
}

#elseif canImport(AppKit)
import AppKit
public typealias Image = NSImage

public extension Image {
    // Convert NSImage to PNG data
    var pngDataCompatibility: Data? {
        guard
            let tiff = self.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        return data
    }

    // NSImage already supports init?(data:)
    convenience init?(compatibilityData data: Data) {
        self.init(data: data)
    }
}

#else
#error("Neither UIKit nor AppKit is available to define Image alias.")
#endif
