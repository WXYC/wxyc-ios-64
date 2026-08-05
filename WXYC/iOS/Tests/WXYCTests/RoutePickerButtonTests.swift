//
//  RoutePickerButtonTests.swift
//  WXYCTests
//
//  Pins the two undocumented AVRoutePickerView behaviours that the Station tab's
//  "Listening" row is built on. Neither is promised by AVKit, and if either
//  changes the row goes dead SILENTLY — it would still build, still lay out, and
//  simply stop opening the picker. These fail loudly instead.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AVKit
import Testing
import UIKit

@MainActor
@Suite("RoutePickerButton foundations")
struct RoutePickerButtonTests {

    /// StationRow's content width on a 393pt phone: 393 − 18×2 (StationView's
    /// horizontal padding) − 14×2 (StationRowContent's).
    private static let rowWidth: CGFloat = 329
    private static let rowHeight: CGFloat = 54

    private func hostedPicker(width: CGFloat, height: CGFloat = rowHeight) -> AVRoutePickerView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.addSubview(picker)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        picker.layoutIfNeeded()
        return picker
    }

    @Test("The picker's tap target spans the whole row, not just a centred glyph")
    func tapTargetFillsTheRow() {
        let picker = hostedPicker(width: Self.rowWidth)
        let y = Self.rowHeight / 2

        for x in stride(from: 4.0, through: Double(Self.rowWidth) - 4.0, by: 8.0) {
            let hit = picker.hitTest(CGPoint(x: x, y: y), with: nil)
            #expect(
                hit is UIControl,
                "x=\(x) hit \(hit.map { String(describing: type(of: $0)) } ?? "nil"), not a control — the overlay row would be dead here"
            )
        }
    }

    @Test(
        "The tap target tracks the view's width",
        arguments: [44.0, 160.0, 329.0] as [CGFloat]
    )
    func tapTargetTracksWidth(_ width: CGFloat) {
        let picker = hostedPicker(width: width)
        let widest = picker.subviews.map(\.frame.width).max() ?? 0

        #expect(
            abs(widest - width) < 1,
            "widest subview \(widest) does not track picker width \(width)"
        )
    }

    @Test("A clear tint renders nothing, so the row's own content shows through")
    func clearTintIsInvisible() {
        // `drawHierarchy` needs a render server the test host may not have;
        // `layer.render` rasterizes locally. The default-tint case is the
        // control — if IT reads zero, rasterization failed and the assertion
        // about `.clear` would be vacuous.
        func visiblePixels(tint: UIColor) -> Int {
            let picker = hostedPicker(width: 44, height: 44)
            picker.tintColor = tint
            picker.layoutIfNeeded()

            let image = UIGraphicsImageRenderer(bounds: picker.bounds).image { ctx in
                picker.layer.render(in: ctx.cgContext)
            }
            guard let cg = image.cgImage else { return 0 }

            let (w, h) = (cg.width, cg.height)
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let context = CGContext(
                data: &pixels, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

            return stride(from: 0, to: pixels.count, by: 4).count { pixels[$0 + 3] > 8 }
        }

        let opaque = visiblePixels(tint: .systemRed)
        #expect(opaque > 0, "control failed: the picker rendered nothing even with a visible tint")

        #expect(visiblePixels(tint: .clear) == 0, "a clear tint still painted a glyph")
    }
}
