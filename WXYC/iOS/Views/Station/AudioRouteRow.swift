//
//  AudioRouteRow.swift
//  WXYC
//
//  The Station tab's "Listening" row: where audio is playing, and a tap that
//  opens the system output picker.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A ``StationRow``-shaped control that reports the current audio route and
/// opens the system picker when tapped.
///
/// Unlike every other row in the Station tab this is not a `Button`:
/// `AVRoutePickerView` has no API to present the picker, so the picker itself
/// must receive the touch. It is stretched over the row with a clear tint and
/// the visible content is drawn underneath — see ``RoutePickerButton``.
struct AudioRouteRow: View {
    let monitor: AudioRouteMonitor

    private static let title = "Play on a speaker"

    var body: some View {
        ZStack {
            StationRowContent(
                title: Self.title,
                subtitle: monitor.label.name,
                // The tile colour doubles as the active tint, so a live route
                // reads as "this row is doing something" without a new colour.
                subtitleColor: monitor.label.isExternal ? .cyan : .white.opacity(0.55),
                systemImage: "airplayaudio",
                iconColor: .cyan
            )
            // The picker below carries this row's accessibility, so the visual
            // content must not also publish elements.
            .accessibilityHidden(true)

            RoutePickerButton(
                accessibilityLabel: Self.title,
                accessibilityValue: monitor.label.name
            )
        }
        .task {
            await monitor.observeRouteChanges()
        }
    }
}
