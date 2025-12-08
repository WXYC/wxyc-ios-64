//
//  StreamingButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Metadata
import Playlist

struct StreamingButton: View {
    let service: StreamingService
    let url: URL?
    let isLoading: Bool
    var onTap: ((StreamingService) -> Void)?
    
    @State private var showingSafari = false
    
    var body: some View {
        Group {
            if let url = url {
                Button {
                    onTap?(service)
                    if service.opensInBrowser {
                        showingSafari = true
                    } else {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    buttonContent
                }
                .sheet(isPresented: $showingSafari) {
                    SafariView(url: url)
                }
            } else {
                buttonContent
                    .opacity(isLoading ? 0.5 : 0.3)
            }
        }
    }
    
    private var buttonContent: some View {
        HStack(spacing: 8) {
            Group {
                if service.hasCustomIcon {
                    Image(service.iconName, bundle: .playlist)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: service.systemIcon)
                        .font(.body)
                }
            }
            .frame(width: 20, height: 16)
            
            Text(service.name)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(service.color.opacity(url != nil ? 1.0 : 0.3))
        )
    }
}

