//
//  ShareViewController.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import UIKit
import SwiftUI
import MusicShareKit
import Logger
import Secrets

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        Log(.info, "ShareViewController viewDidLoad started")

        // Configure MusicShareKit with secrets
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: Secrets.requestOMatic,
            spotifyClientId: Secrets.spotifyClientId,
            spotifyClientSecret: Secrets.spotifyClientSecret
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
