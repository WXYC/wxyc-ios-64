//
//  PasteboardTests.swift
//  WXUI
//
//  Tests for the cross-platform Pasteboard.copy(_:) shim.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

@Suite("Pasteboard", .serialized)
struct PasteboardTests {

    @Test("copy writes the string to the system pasteboard, replacing its contents")
    @MainActor
    func copyWritesString() throws {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previous { pasteboard.setString(previous, forType: .string) }
        }

        Pasteboard.copy("wxyc-pasteboard-roundtrip")
        #expect(pasteboard.string(forType: .string) == "wxyc-pasteboard-roundtrip")
        #elseif os(iOS) || os(visionOS)
        let pasteboard = UIPasteboard.general
        let previous = pasteboard.string
        defer { pasteboard.string = previous }

        Pasteboard.copy("wxyc-pasteboard-roundtrip")
        #expect(pasteboard.string == "wxyc-pasteboard-roundtrip")
        #else
        // No general pasteboard on this platform (watchOS/tvOS); copy is a
        // documented no-op. Assert only that it doesn't trap.
        Pasteboard.copy("noop")
        #endif
    }
}
