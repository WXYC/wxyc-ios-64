//
//  ExternalLinkButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core

struct ExternalLinkButton: View {
    let title: String
    let imageName: String
    let url: URL
    
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(imageName, bundle: .core)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 16)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(0.15))
            )
        }
    }
}

