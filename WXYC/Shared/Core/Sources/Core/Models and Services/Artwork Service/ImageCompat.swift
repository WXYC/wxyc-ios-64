// ImageCompat.swift (new file in Core target)

import Foundation

#if canImport(UIKit)
import UIKit
public typealias Image = UIImage

public extension Image {
    var pngDataCompat: Data? { self.pngData() }
    convenience init?(data: Data) { self.init(data: data) }
}
#elseif canImport(AppKit)
import AppKit
public typealias Image = NSImage

public extension Image {
    var pngDataCompat: Data? {
        guard
            let tiff = self.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        return data
    }

    convenience init?(data: Data) {
        self.init(data: data)
    }
}
#else
#error("Neither UIKit nor AppKit is available for Image alias.")
#endif
