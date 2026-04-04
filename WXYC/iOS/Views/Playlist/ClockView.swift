//
//  ClockView.swift
//  WXYC
//
//  A clock glyph rendered as a compound path (circle with hand cutouts)
//  displayed inline with formatted time text, scaling with Dynamic Type.
//
//  Created by Jake Bromberg on 01/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import UIKit

/// Displays a clock glyph inline with formatted time text.
///
/// The clock face uses an even-odd compound path so the hands are transparent
/// cutouts through the circle. The image is rendered as a template so it
/// inherits the surrounding `foregroundStyle`. Size tracks Dynamic Type via
/// `@ScaledMetric`.
struct ClockView: View {
    /// Timestamp in milliseconds since epoch.
    let timeCreated: UInt64

    /// Clock face diameter, scaled with Dynamic Type relative to body text.
    @ScaledMetric(relativeTo: .body) private var clockSize: CGFloat = 14

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

    /// Hour hand angle (12 o'clock = 0 degrees, increasing clockwise).
    private var hourAngle: Angle {
        let hourIn12 = Double(hour % 12)
        let degrees = (hourIn12 * 30) + (Double(minute) * 0.5)
        return .degrees(degrees)
    }

    /// Minute hand angle (12 o'clock = 0 degrees, increasing clockwise).
    private var minuteAngle: Angle {
        .degrees(Double(minute) * 6)
    }

    var body: some View {
        Text("\(Image(uiImage: clockImage)) \(formattedTime)")
    }

    // MARK: - Clock Image Rendering

    /// Renders the clock face as a template image. A white circle is drawn first,
    /// then the hand shapes are erased with `.clear` blend mode inside a
    /// transparency layer, producing see-through cutouts.
    private var clockImage: UIImage {
        let size = clockSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2
            let handWidth = max(radius * 0.2, 1.0)
            let hourLength = radius * 0.5
            let minuteLength = radius * 0.7

            let hourTip = CGPoint(
                x: center.x + hourLength * sin(hourAngle.radians),
                y: center.y - hourLength * cos(hourAngle.radians)
            )
            let minuteTip = CGPoint(
                x: center.x + minuteLength * sin(minuteAngle.radians),
                y: center.y - minuteLength * cos(minuteAngle.radians)
            )

            gc.beginTransparencyLayer(auxiliaryInfo: nil)

            // Solid circle
            gc.setFillColor(UIColor.white.cgColor)
            gc.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))

            // Punch out hands as a single stroked path: hour tip → center → minute tip
            gc.setBlendMode(.clear)
            gc.setStrokeColor(UIColor.white.cgColor)
            gc.setLineWidth(handWidth)
            gc.setLineCap(.round)
            gc.setLineJoin(.round)
            gc.move(to: hourTip)
            gc.addLine(to: center)
            gc.addLine(to: minuteTip)
            gc.strokePath()

            gc.endTransparencyLayer()
        }

        return image.withRenderingMode(.alwaysTemplate)
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
