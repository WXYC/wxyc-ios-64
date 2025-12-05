//
//  RequestSentHUD.swift
//  RequestService
//
//  Created by Jake Bromberg on 12/1/25.
//

import SwiftUI

public struct RequestSentHUD: View {
    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "phone.connection.fill")
                .font(.system(size: 40))
            
            Text("Request Sent")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .shadow(color: .white, radius: 1.125)
        .frame(width: 120, height: 120)
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 2.5, y: 1.5)
    }
}

// MARK: - ViewModifier

struct RequestSentHUDModifier: ViewModifier {
    @Binding var isPresented: Bool
    var autoDismissAfter = Duration.milliseconds(1500)
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                RequestSentHUD()
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        Task {
                            try await Task.sleep(until: .now + autoDismissAfter)
                            isPresented = false
                        }
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8),
                   value: isPresented)
    }
}

public extension View {
    func requestSentHUD(isPresented: Binding<Bool>,
                        autoDismissAfter: TimeInterval = 1.5) -> some View {
        modifier(
            RequestSentHUDModifier(isPresented: isPresented)
        )
    }
}

struct ContentView: View {
    @State private var showRequestSentHUD = true
    
    var body: some View {
        VStack(spacing: 20) {
            Button("Send Request") {
                // your networking logic here…
                withAnimation {
                    showRequestSentHUD = true
                }
            }
        }
        .requestSentHUD(isPresented: $showRequestSentHUD)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Gradient(colors: [.purple, .pink]))
    }
}

#Preview {
    ContentView()
}
