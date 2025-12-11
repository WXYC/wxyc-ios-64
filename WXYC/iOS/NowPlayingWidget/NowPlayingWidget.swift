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

#if DEBUG
@main
struct NowPlayingWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        NowPlayingWidget()
    }
}
#else
@main
struct NowPlayingWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        NowPlayingControl()
        NowPlayingWidget()
    }
}
#endif

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
