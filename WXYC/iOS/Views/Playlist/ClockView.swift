//
//  ClockView.swift
//  WXYC
//
//  A clock icon that displays hour and minute hands based on a timestamp,
//  with formatted time text underneath.
//
//  Created by Jake Bromberg on 01/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A clock view that shows hour/minute hands and formatted time based on a timestamp.
struct ClockView: View {
    /// Timestamp in milliseconds since epoch
    let timeCreated: UInt64

    /// Size of the clock face
    var size: CGFloat = 32

    /// Color for the clock face background
    var backgroundColor: Color = .white

    /// Color for the clock hands
    var handColor: Color = .black

    private var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timeCreated) / 1000)
    }

    private var hour: Int {
        Calendar.current.component(.hour, from: date)
    }

    private var minute: Int {
        Calendar.current.component(.minute, from: date)
    }

    private var formattedTime: String {
        date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 4) {
            ClockFace(
                hour: hour,
                minute: minute,
                backgroundColor: backgroundColor,
                handColor: handColor
            )
            .frame(width: size, height: size)

            Text(formattedTime)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// The clock face with hour and minute hands
private struct ClockFace: View {
    let hour: Int
    let minute: Int
    let backgroundColor: Color
    let handColor: Color

    /// Hour hand angle (12 o'clock = 0 degrees, clockwise)
    private var hourAngle: Angle {
        // Hour hand moves 30 degrees per hour (360/12) plus 0.5 degrees per minute
        let hourIn12 = Double(hour % 12)
        let degrees = (hourIn12 * 30) + (Double(minute) * 0.5)
        return .degrees(degrees)
    }

    /// Minute hand angle (12 o'clock = 0 degrees, clockwise)
    private var minuteAngle: Angle {
        // Minute hand moves 6 degrees per minute (360/60)
        .degrees(Double(minute) * 6)
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            // Draw clock face background
            let circlePath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(circlePath, with: .color(backgroundColor))

            // Hand dimensions relative to clock size
            let hourHandLength = radius * 0.5
            let minuteHandLength = radius * 0.7
            let handWidth = radius * 0.12

            // Draw hour hand
            drawHand(
                context: context,
                center: center,
                length: hourHandLength,
                width: handWidth,
                angle: hourAngle,
                color: handColor
            )

            // Draw minute hand
            drawHand(
                context: context,
                center: center,
                length: minuteHandLength,
                width: handWidth,
                angle: minuteAngle,
                color: handColor
            )
        }
    }

    private func drawHand(
        context: GraphicsContext,
        center: CGPoint,
        length: CGFloat,
        width: CGFloat,
        angle: Angle,
        color: Color
    ) {
        var path = Path()

        // Start from center, draw to the end point
        // Angle 0 = 12 o'clock, so we need to offset by -90 degrees
        let adjustedAngle = angle - .degrees(90)
        let endX = center.x + length * cos(adjustedAngle.radians)
        let endY = center.y + length * sin(adjustedAngle.radians)

        path.move(to: center)
        path.addLine(to: CGPoint(x: endX, y: endY))

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
    }
}

#Preview("9:00 AM") {
    ClockView(timeCreated: 1706526000000) // 9:00 AM
        .padding()
        .background(.black)
}

#Preview("3:30 PM") {
    ClockView(timeCreated: 1706549400000) // 3:30 PM
        .padding()
        .background(.black)
}

#Preview("Various Times") {
    HStack(spacing: 20) {
        ClockView(timeCreated: 1706490000000) // 12:00 AM
        ClockView(timeCreated: 1706500800000) // 3:00 AM
        ClockView(timeCreated: 1706522400000) // 9:00 AM
        ClockView(timeCreated: 1706544000000) // 3:00 PM
    }
    .padding()
    .background(.black)
}
