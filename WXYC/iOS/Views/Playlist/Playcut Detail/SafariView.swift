//
//  SafariView.swift
//  WXYC
//
//  SafariViewController wrapper for in-app browsing.
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#if canImport(SafariServices)
import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
