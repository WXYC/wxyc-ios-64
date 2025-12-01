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
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial) // or Color.black.opacity(0.8) if you prefer
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 2.5, y: 1.5)
    }
}

// MARK: - ViewModifier

struct RequestSentHUDModifier: ViewModifier {
    @Binding var isPresented: Bool
    var autoDismissAfter: TimeInterval = 1.5
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                RequestSentHUD()
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        // auto dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter) {
                            withAnimation {
                                isPresented = false
                            }
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
        modifier(RequestSentHUDModifier(isPresented: isPresented,
                                        autoDismissAfter: autoDismissAfter))
    }
}

struct ContentView: View {
    @State private var showRequestSentHUD = false
    
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
        .background(.green)
    }
}

#Preview {
    ContentView()
}
