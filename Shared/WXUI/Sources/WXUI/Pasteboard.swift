//
//  Pasteboard.swift
//  WXUI
//
//  Cross-platform clipboard writes over UIPasteboard / NSPasteboard, so shared
//  code can copy text without a per-call-site #if branch.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cross-platform clipboard writes.
///
/// A thin namespace over `UIPasteboard.general` (iOS/visionOS/Mac Catalyst) and
/// `NSPasteboard.general` (macOS). On platforms without a general pasteboard —
/// watchOS and tvOS — the operations are no-ops.
public enum Pasteboard {
    /// Copies `string` to the system pasteboard as plain text, replacing its
    /// current contents.
    ///
    /// A no-op on platforms without a general pasteboard (watchOS, tvOS).
    public static func copy(_ string: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
