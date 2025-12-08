//
//  RequestSentHUD.swift
//  RequestService
//
//  Created by Jake Bromberg on 12/1/25.
//

import SwiftUI

struct RequestSentHUD: View {
    @State private var contentSize: CGSize = .zero

    public var body: some View {
        VStack(spacing: 8) {
            Spacer()
            
            Image(systemName: "phone.connection.fill")
                .font(.system(size: 40))
            
            Spacer()
            
            Text("Request Sent")
                .font(.headline)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { size in
            contentSize = size
        }
        .frame(
            width: max(contentSize.width, contentSize.height),
            height: max(contentSize.width, contentSize.height)
        )
        .background(.ultraThinMaterial) // or Color.black.opacity(0.8) if you prefer
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 2.5, y: 1.5)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
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
    func requestSentHUD(
        isPresented: Binding<Bool>,
        autoDismissAfter: TimeInterval = 1.5
    ) -> some View {
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
