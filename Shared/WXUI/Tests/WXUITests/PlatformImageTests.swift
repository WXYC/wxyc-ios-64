//
//  PlatformImageTests.swift
//  WXUI
//
//  Tests for the PlatformImage typealias and the Image(platform:) bridge.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import WXUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("PlatformImage")
struct PlatformImageTests {

    @Test("PlatformImage aliases the platform's bitmap image type")
    func platformImageResolvesToPlatformType() {
        #if os(macOS)
        #expect(PlatformImage.self == NSImage.self)
        #elseif canImport(UIKit)
        #expect(PlatformImage.self == UIImage.self)
        #endif
    }

    @Test("Image(platform:) builds a SwiftUI Image from a platform image without trapping")
    @MainActor
    func imageFromPlatformImageDoesNotTrap() {
        let platformImage = PlatformImage()
        let image = Image(platform: platformImage)
        // Constructing the SwiftUI Image without trapping is the assertion; the
        // rendered pixels aren't introspectable from a unit test.
        _ = image
    }
}
