import SwiftUI
import Core

struct PlayerHeaderView: View {
    private var radioPlayerController: RadioPlayerController {
        AppState.shared.radioPlayerController
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            cassetteContainer
                .aspectRatio(4.8546511628, contentMode: .fit)
        }
    }
    
    private var cassetteContainer: some View {
        GeometryReader { geometry in
            HStack(spacing: -1) {
                PlaybackButtonSwiftUI(
                    status: radioPlayerController.isPlaying ? .playing : .paused,
                    color: .primary,
                    action: { togglePlayback() }
                )
                .frame(width: geometry.size.height, height: geometry.size.height)
                
                CassetteView(isPlaying: radioPlayerController.isPlaying)
                    .background(.yellow)
                    .frame(height: geometry.size.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Playback Control
    
    private func togglePlayback() {
        try? radioPlayerController.toggle(reason: "player header play/pause button tapped")
    }
}

#Preview {
    PlayerHeaderView()

    Rectangle()
        .background(.pink)
}
