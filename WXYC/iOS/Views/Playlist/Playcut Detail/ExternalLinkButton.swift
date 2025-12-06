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
    var onTap: ((String) -> Void)?
    
    var body: some View {
        Button {
            onTap?(title)
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 12) {
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

