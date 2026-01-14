//
//  ShareSheet.swift
//  Wallpaper
//
//  Share sheet wrapper for exporting theme snapshots.
//
//  Created by Jake Bromberg on 01/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for UIActivityViewController.
public struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?

    public init(items: [Any], excludedActivityTypes: [UIActivity.ActivityType]? = nil) {
        self.items = items
        self.excludedActivityTypes = excludedActivityTypes
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
