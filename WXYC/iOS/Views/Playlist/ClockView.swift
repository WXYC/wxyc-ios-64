//
//  ClockView.swift
//  WXYC
//
//  Displays a flowsheet entry's timestamp as caption text.
//
//  Created by Jake Bromberg on 01/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// Displays the formatted time for a flowsheet entry.
struct ClockView: View {
    /// Timestamp in milliseconds since epoch.
    let timeCreated: UInt64

    private var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timeCreated) / 1000)
    }

    private var formattedTime: String {
        date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Text("\(formattedTime)")
            .font(.system(.caption))
    }
}

#Preview("9:00 AM") {
    ClockView(timeCreated: 1706526000000)
        .foregroundStyle(.white)
        .padding()
        .background(.black)
}

#Preview("3:30 PM") {
    ClockView(timeCreated: 1706549400000)
        .foregroundStyle(.white)
        .padding()
        .background(.black)
}

#Preview("Various Times") {
    VStack(spacing: 12) {
        ClockView(timeCreated: 1706490000000) // 12:00 AM
        ClockView(timeCreated: 1706500800000) // 3:00 AM
        ClockView(timeCreated: 1706522400000) // 9:00 AM
        ClockView(timeCreated: 1706544000000) // 3:00 PM
    }
    .foregroundStyle(.white)
    .padding()
    .background(.black)
}
