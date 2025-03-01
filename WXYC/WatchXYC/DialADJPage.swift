//
//  DialADJPage.swift
//  WatchXYC App
//
//  Created by Jake Bromberg on 2/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Core
import UIKit

struct DialADJPage: View {
    let gradient = LinearGradient(
        colors: [.brightGreen, .blue],
        startPoint: .init(x: 0.25, y: 0.25),
        endPoint: .init(x: 0.75, y: 0.75)
    )
    
    var body: some View {
        VStack {
            Button(action: {
                WKExtension.shared().openSystemURL(RadioStation.WXYC.requestLine)
            }) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(20)
            }
            .background(self.gradient)
            .clipShape(Circle())
            .padding(20)
            
            Text("Dial a DJ")
                .font(.headline)
            
            Text("make a request")
                .font(.caption)
                .foregroundStyle(Color.gray)
        }
        .padding()
    }
}

extension Color {
    static var brightGreen: Color {
        .init(red: 0, green: 1, blue: 0)
    }
}

#Preview {
    DialADJPage()
}
