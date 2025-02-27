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
            .background(.green)
            .clipShape(Circle())
            .padding(20)
            Text("Dial a DJ")
                .font(.headline)
            Text("make a request")
                .font(.caption)
        }
        .padding()
    }
}
