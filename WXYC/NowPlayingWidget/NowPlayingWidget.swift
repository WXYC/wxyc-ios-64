//
//  NowPlayingWidget.swift
//  NowPlayingWidget
//
//  Created by Jake Bromberg on 1/13/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Definitions

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            content(for: entry)
        }
        .contentMarginsDisabled()
    }
    
    @ViewBuilder
    private func content(for entry: NowPlayingTimelineEntry) -> some View {
        switch entry.family {
        case .systemSmall:
            SmallNowPlayingWidgetEntryView(entry: entry)
        case .systemMedium:
            MediumNowPlayingWidgetEntryView(entry: entry)
        default:
            LargeNowPlayingWidgetEntryView(entry: entry)
        }
    }
}

// MARK: - Widget Bundle

@main
struct NowPlayingWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingControl()
        NowPlayingWidget()
    }
}

// MARK: - Control Widget

@available(iOSApplicationExtension 18.0, *)
struct NowPlayingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "org.wxyc.control", intent: PlayWXYC.self) { config in
            ControlWidgetButton(action: config) {
                Label {
                    Text("WXYC")
                } icon: {
                    Image(systemName: "radio")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview(as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemLarge)
}
