import UIKit
import MediaPlayer
import UI
import Core
import Spring

final class NowPlayingViewController: UIViewController, NowPlayingPresentable, PlaylistServiceObserver {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var playbackButton: PlaybackButton!
    
    let radioPlayer = RadioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        // Remote events for play/pause taps on headphones
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }
    
    // MARK: - Player Controls (Play/Pause)
    
    @IBAction func playPauseTapped(_ sender: UIButton) {
        switch playbackButton.status {
        case .paused:
            playPressed()
        case .playing:
            pausePressed()
        }
    }
    
    override func remoteControlReceived(with receivedEvent: UIEvent?) {
        super.remoteControlReceived(with: receivedEvent)
        
        guard let receivedEvent = receivedEvent else {
            return
        }
        
        switch receivedEvent.subtype {
        case .remoteControlPlay:
            playPressed()
        case .remoteControlPause:
            pausePressed()
        case .remoteControlTogglePlayPause:
            radioPlayer.isPlaying ? pausePressed() : playPressed()
        default:
            break
        }
    }
    
    func playPressed() {
        playbackButton.status = .playing
        radioPlayer.play()
        
        songLabel.animation = Spring.AnimationPreset.Flash.rawValue
        songLabel.animate()
    }
    
    func pausePressed() {
        playbackButton.status = .paused
        radioPlayer.pause()
    }
    
    // MARK: - Sharing
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        // TODO: Extract
        let songToShare = "I'm listening to [song] on \(RadioStation.WXYC.name)"
        let activityViewController = UIActivityViewController(activityItems: [songToShare, self.albumImageView.image ?? UIImage()], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }
    
    // MARK: - Handoff
    
    override func updateUserActivityState(_ activity: NSUserActivity) {
        activity.webpageURL = self.userActivity?.webpageURL
        super.updateUserActivityState(activity)
    }
}
