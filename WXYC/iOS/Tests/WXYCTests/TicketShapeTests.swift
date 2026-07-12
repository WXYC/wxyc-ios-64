//
//  TicketShapeTests.swift
//  WXYC
//
//  Verifies the ticket outline carves its two notches at the perforation seam —
//  `stubHeight` up from the bottom edge — and nowhere else, so the body above the
//  seam stays solid and the wallpaper only shows through at the notches.
//
//  Created by Jake Bromberg on 07/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import WXYC

@Suite("TicketShape")
struct TicketShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
    private let stubHeight: CGFloat = 96
    private let notchRadius: CGFloat = 11

    private var shape: TicketShape {
        TicketShape(cornerRadius: 16, stubHeight: stubHeight, notchRadius: notchRadius)
    }

    private var seamY: CGFloat { rect.maxY - stubHeight } // 304

    private func contains(_ point: CGPoint) -> Bool {
        shape.path(in: rect).contains(point)
    }

    @Test("The left notch is carved out at the seam")
    func leftNotchCarved() {
        // A point a few points inside the left edge, level with the seam, lands
        // inside the notch circle centered on (minX, seamY) and is cut away.
        #expect(contains(CGPoint(x: 4, y: seamY)) == false)
    }

    @Test("The right notch is carved out at the seam")
    func rightNotchCarved() {
        #expect(contains(CGPoint(x: rect.maxX - 4, y: seamY)) == false)
    }

    @Test("The body stays solid along the same edges above the seam")
    func bodySolidAboveSeam() {
        // Same horizontal inset as the notch probes, but well above the seam:
        // proves the carve is localized to the perforation, not the whole edge.
        #expect(contains(CGPoint(x: 4, y: seamY - 60)) == true)
        #expect(contains(CGPoint(x: rect.maxX - 4, y: seamY - 60)) == true)
    }

    @Test("The interior is filled and points outside the rect are not")
    func interiorAndExterior() {
        #expect(contains(CGPoint(x: rect.midX, y: rect.midY)) == true)
        #expect(contains(CGPoint(x: rect.minX - 20, y: rect.midY)) == false)
    }

    @Test("Notch height follows stubHeight")
    func notchTracksStubHeight() {
        // A taller stub moves the seam — and therefore the notch — further up.
        let tall = TicketShape(cornerRadius: 16, stubHeight: 150, notchRadius: notchRadius)
        let tallSeamY = rect.maxY - 150 // 250
        #expect(tall.path(in: rect).contains(CGPoint(x: 4, y: tallSeamY)) == false)
        // At the original seam the taller ticket is solid again.
        #expect(tall.path(in: rect).contains(CGPoint(x: 4, y: seamY)) == true)
    }
}
