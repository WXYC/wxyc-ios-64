//
//  MetadataItem.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

struct MetadataLabel: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.caption.smallCaps())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }
}

struct MetadataValue: View {
    let value: String
    
    var body: some View {
        Text(value)
            .multilineTextAlignment(.leading)
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}
