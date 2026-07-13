//
//  TicketShape.swift
//  WXYC
//
//  The perforated-ticket outline: a rounded rectangle with two circular notches
//  cut into the side edges at the perforation line (`stubHeight` up from the
//  bottom). Used as a clip shape so the notches punch clean through to the
//  wallpaper behind the card, and as a stroke for the hairline rim. Shared by the
//  real Box Office ticket (``BoxOfficeTicketView``) and the discovery CTA that
//  teaches it (``TicketFeatureCTAView``) so both carry one identical geometry.
//
//  Created by Jake Bromberg on 07/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A rounded-rectangle ticket outline with two circular notches cut into the
/// side edges at the perforation line (`stubHeight` up from the bottom). Used as
/// the clip shape so the notches punch through to the wallpaper behind the card.
struct TicketShape: Shape {
    let cornerRadius: CGFloat
    let stubHeight: CGFloat
    let notchRadius: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var shape = Path(roundedRect: rect, cornerRadius: cornerRadius)
        let notchCenterY = rect.maxY - stubHeight
        let leftNotch = Path(ellipseIn: CGRect(
            x: rect.minX - notchRadius, y: notchCenterY - notchRadius,
            width: notchRadius * 2, height: notchRadius * 2
        ))
        let rightNotch = Path(ellipseIn: CGRect(
            x: rect.maxX - notchRadius, y: notchCenterY - notchRadius,
            width: notchRadius * 2, height: notchRadius * 2
        ))
        shape = shape.subtracting(leftNotch)
        shape = shape.subtracting(rightNotch)
        return shape
    }
}
