//
//  NowPlayingWidget.swift
//  WXYC
//
//  Main widget definition and configuration.
//
//  Created by Jake Bromberg on 01/12/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import AppIntents
import Caching
import SwiftUI
import WidgetKit
import WXYCIntents

// MARK: - Widget Definitions

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            content(for: entry)
        }
        .configurationDisplayName("WXYC Now Playing")
        .description("See what's playing on WXYC 89.3 FM.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

struct PlaybackStateProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        UserDefaults.wxyc.bool(forKey: "isPlaying")
    }
}

struct NowPlayingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.wxyc.control", provider: PlaybackStateProvider()) { isPlaying in
            ControlWidgetToggle(isOn: isPlaying, action: ToggleWXYC(value: !isPlaying)) {
                Label {
                    Text("WXYC")
                } icon: {
                    Image(systemName: "radio")
                }
            }
        }
        .displayName("Play WXYC")
        .description("Toggle WXYC 89.3 FM playback.")
    }
}

// MARK: - Previews

#Preview("Large", as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemLarge)
}

#Preview("Medium", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemMedium)
}

#Preview("Small", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.placeholder(family: .systemSmall)
}

// MARK: - Empty State Previews

#Preview("Empty - Large", as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.emptyState(family: .systemLarge)
}

#Preview("Empty - Medium", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.emptyState(family: .systemMedium)
}

#Preview("Empty - Small", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingTimelineEntry.emptyState(family: .systemSmall)
}
