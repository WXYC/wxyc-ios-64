import UIKit
import MediaPlayer
import UI
import Core
import Spring

final class NowPlayingViewController: UIViewController, NowPlayingPresentable, NowPlayingServiceObserver {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var playbackButton: PlaybackButton!
    
    var radioPlayerStateObservation: Any?
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        self.radioPlayerStateObservation = RadioPlayerController.shared.observePlaybackState(self.playbackStateChanged)
    }
    
    // MARK: Private
    
    private func playbackStateChanged(playbackState: PlaybackState) {
        switch playbackState {
        case .paused:
            playbackButton.set(status: .paused, animated: self.shouldAnimateButtonTransition)
        case .playing:
            playbackButton.set(status: .playing, animated: self.shouldAnimateButtonTransition)
            
            songLabel.animation = .Flash
            songLabel.animate()
        }
    }
    
    private var shouldAnimateButtonTransition: Bool {
        return UIApplication.shared.applicationState == .active
    }
    
    // MARK: Player Controls (Play/Pause)
    
    @IBAction private func playPauseTapped(_ sender: UIButton) {
        switch playbackButton.status {
        case .paused:
            RadioPlayerController.shared.play()
        case .playing:
            RadioPlayerController.shared.pause()
        }
    }
    
    // MARK: - Sharing
    
    @IBAction private func shareButtonPressed(_ sender: UIButton) {
        let activityItems: [Any] = [
            "I'm listening to [song] on \(RadioStation.WXYC.name)",
            self.albumImageView.image ?? UIImage()
        ]
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        present(activityViewController, animated: true, completion: nil)
    }
    
    // MARK: - Handoff
    
    override func updateUserActivityState(_ activity: NSUserActivity) {
        activity.webpageURL = self.userActivity?.webpageURL
        super.updateUserActivityState(activity)
    }
}
