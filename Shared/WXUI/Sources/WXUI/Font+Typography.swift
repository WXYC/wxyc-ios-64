//
//  Font+Typography.swift
//  WXUI
//
//  Shared typography constants for the WXYC design system. Centralizes repeated font chains so detail views and section headers use a single source of truth.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

extension Font {
    /// Small-caps headline used for detail section headers ("About the Artist", "Add it to your library", "More Info", etc.).
    public static let detailSectionHeader: Font = .headline.smallCaps()
}
