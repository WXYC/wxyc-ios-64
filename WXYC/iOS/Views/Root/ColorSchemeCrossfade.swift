//
//  ColorSchemeCrossfade.swift
//  WXYC
//
//  Cross-fades the window when the system switches between light and dark mode,
//  instead of letting the appearance change snap instantaneously. Snapshots the
//  window before iOS commits the new trait, overlays the snapshot, and fades it
//  out over the freshly-rendered new appearance.
//
//  Created by Jake Bromberg on 5/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import UIKit

extension View {
    /// Cross-fades the window when the system switches between light and dark mode.
    /// Attach once near the root of the scene.
    func crossfadeColorSchemeTransitions(duration: TimeInterval = 0.4) -> some View {
        background(ColorSchemeCrossfadeAnchor(duration: duration).allowsHitTesting(false))
    }
}

private struct ColorSchemeCrossfadeAnchor: UIViewRepresentable {
    let duration: TimeInterval

    func makeUIView(context: Context) -> CrossfadeAnchorView {
        CrossfadeAnchorView(duration: duration)
    }

    func updateUIView(_ uiView: CrossfadeAnchorView, context: Context) {
        uiView.duration = duration
    }
}

private final class CrossfadeAnchorView: UIView {
    var duration: TimeInterval
    private var registration: (any UITraitChangeRegistration)?
    private weak var registeredWindow: UIWindow?

    init(duration: TimeInterval) {
        self.duration = duration
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let registration, let registeredWindow {
            registeredWindow.unregisterForTraitChanges(registration)
        }
        registration = nil
        registeredWindow = nil

        guard let window else { return }
        registration = window.registerForTraitChanges(
            [UITraitUserInterfaceStyle.self]
        ) { [weak self] (window: UIWindow, _: UITraitCollection) in
            self?.crossfade(in: window)
        }
        registeredWindow = window
    }

    private func crossfade(in window: UIWindow) {
        // `afterScreenUpdates: false` captures the layer tree as it was committed
        // before iOS redraws with the new trait, giving us the old appearance.
        guard let snapshot = window.snapshotView(afterScreenUpdates: false) else { return }
        snapshot.isUserInteractionEnabled = false
        snapshot.frame = window.bounds
        window.addSubview(snapshot)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }
}
