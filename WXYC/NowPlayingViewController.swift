import UIKit
import MediaPlayer

class NowPlayingViewController: UIViewController {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var playbackButton: PlaybackButton!
    
    let radioPlayer = RadioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.albumImageView.layer.cornerRadius = 6.0
        self.albumImageView.layer.masksToBounds = true
        
        self.playbackButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        self.playbackButton.adjustMargin = 1
        self.playbackButton.backgroundColor = UIColor.clear
        self.playbackButton.addTarget(self, action: #selector(playPauseTapped(_:)), for: .touchUpInside)
        self.playbackButton.setButtonColor(.white)
        
        // Remote events for play/pause taps on headphones
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        if !radioPlayer.isPlaying {
            pausePressed()
        }
    }
    
    // MARK: - Player Controls (Play/Pause)
    
    @IBAction @objc func playPauseTapped(_ sender: PlaybackButton) {
        switch playbackButton.buttonState {
        case .paused:
            playPressed()
        case .playing:
            pausePressed()
        default:
            break
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
        playbackButton.setButtonState(.playing, animated: true)
        radioPlayer.play()
        
        songLabel.animation = Spring.AnimationPreset.Flash.rawValue
        songLabel.animate()
    }
    
    func pausePressed() {
        playbackButton.setButtonState(.paused, animated: true)
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

extension NowPlayingViewController: NowPlayingServiceDelegate {
    func update(nowPlayingInfo: NowPlayingInfo) {
        self.songLabel.text = nowPlayingInfo.primaryHeading
        self.artistLabel.text = nowPlayingInfo.secondaryHeading
    }
    
    func update(artwork: UIImage) {
        UIView.transition(
            with: self.albumImageView,
            duration: 0.25,
            options: [.transitionCrossDissolve],
            animations: { self.albumImageView.image = artwork },
            completion: nil
        )
    }
    
    func update(userActivityState: NSUserActivity) {
        self.userActivity = userActivityState
        self.userActivity?.becomeCurrent()
    }
}
