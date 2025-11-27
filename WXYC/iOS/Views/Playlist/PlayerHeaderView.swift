import SwiftUI
import Core

struct PlayerHeaderView: View {
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: -1) {
                PlaybackButton {
                    try? RadioPlayerController.shared.toggle(reason: "player header play/pause button tapped")
                }
                .frame(width: geometry.size.height, height: geometry.size.height)
                
                CassetteView(isPlaying: RadioPlayerController.shared.isPlaying)
                    .frame(height: geometry.size.height)
            }
        }
        .aspectRatio(4.8546511628, contentMode: .fit)
        .background(BackgroundLayer())
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @Environment(\.colorScheme) private var colorScheme
}

#Preview {
    PlayerHeaderView()

    Rectangle()
        .background(.pink)
}
