//
//  ShareViewController.swift
//  WXYC
//
//  View controller for share extension entry point.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import AppServices
import UIKit
import SwiftUI
import MusicShareKit
import Logger

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Log(.info, "ShareViewController viewDidLoad started")

        // Configure MusicShareKit
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: AppConfiguration.defaults.requestOMaticUrl,
            authBaseURL: AppConfiguration.defaults.apiBaseUrl,
            analyticsService: StructuredPostHogAnalytics.shared
        ))

        // Create SwiftUI view with extension context
        Log(.info, "extensionContext: \(String(describing: extensionContext))")
        let shareView = ShareExtensionView(extensionContext: extensionContext)
        let hostingController = UIHostingController(rootView: shareView)
        Log(.info, "Created UIHostingController")
        
        // Embed the hosting controller
        addChild(hostingController)
        view.addSubview(hostingController.view)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hostingController.didMove(toParent: self)

        // Make the hosting controller's view transparent so our SwiftUI background shows
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        view.backgroundColor = .clear
        view.isOpaque = false
    }
}
