//
//  PlayerHeaderRepresentable.swift
//  WXYC
//
//  SwiftUI wrapper for the UIKit PlayerHeader view
//

import SwiftUI
import UIKit

struct PlayerHeaderRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerHeader {
        // Load the PlayerHeader from its XIB
        let nib = UINib(nibName: NSStringFromClass(PlayerHeader.self), bundle: nil)
        guard let header = nib.instantiate(withOwner: nil, options: nil).first as? PlayerHeader else {
            fatalError("Could not load PlayerHeader from XIB")
        }

        return header
    }

    func updateUIView(_ uiView: PlayerHeader, context: Context) {
        // PlayerHeader manages its own state via RadioPlayerController
        // No updates needed from SwiftUI
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PlayerHeader, context: Context) -> CGSize? {
        // Get the proposed width, defaulting to screen width if not provided
        let width = proposal.width ?? UIScreen.main.bounds.width

        // The cassette has a 4.5:1 aspect ratio (width:height)
        // With 16pt horizontal margins on each side (32 total)
        // And 8pt bottom margin (0 top to safe area)
        let horizontalMargins: CGFloat = 32
        let bottomMargin: CGFloat = 8
        let cassetteAspectRatio: CGFloat = 4.5

        let cassetteWidth = width - horizontalMargins
        let cassetteHeight = cassetteWidth / cassetteAspectRatio
        let totalHeight = cassetteHeight + bottomMargin

        return CGSize(width: width, height: totalHeight)
    }
}
