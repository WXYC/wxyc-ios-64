//
//  CGImageToImageTests.swift
//  Artwork
//
//  Tests for the cross-platform CGImage.toImage() helper that bridges a decoded
//  CGImage to the platform Image type (UIImage/NSImage) on both iOS and macOS.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
import Core
@testable import Artwork

@Suite("CGImage.toImage")
struct CGImageToImageTests {

    private func makeCGImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test("produces a platform Image at the CGImage's pixel dimensions")
    func producesImageAtPixelSize() throws {
        let cg = try makeCGImage(width: 12, height: 8)
        let image: Core.Image = cg.toImage()
        #expect(image.size.width == 12)
        #expect(image.size.height == 8)
    }
}
