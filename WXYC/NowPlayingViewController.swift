import UIKit
import MediaPlayer

class NowPlayingViewController: UIViewController {
    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var playbackButton: PlaybackButton!
    
    let radioPlayer = RadioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.playbackButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        self.playbackButton.adjustMargin = 1
        self.playbackButton.backgroundColor = UIColor.clear
        playbackButton.addTarget(self, action: #selector(playPauseTapped(_:)), for: .touchUpInside)
        playbackButton.setButtonColor(.black)
        
        // Setup handoff functionality - GH
        setupUserActivity()
        
        // Remote events for play/pause taps on headphones
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        if !radioPlayer.isPlaying {
            pausePressed()
        }
    }
    
    // MARK: - Player Controls (Play/Pause/Volume)
    
    @objc func playPauseTapped(_ sender: PlaybackButton) {
        switch playbackButton.buttonState {
        case .pausing:
            playbackButton.setButtonState(.playing, animated: true)
        case .playing:
            playbackButton.setButtonState(.pausing, animated: true)
        default:
            break
        }
    }
    
    @IBAction func playPressed() {
        playButtonEnable(enabled: false)
        radioPlayer.play()
        
        // songLabel Animation
        songLabel.animation = "flash"
        songLabel.animate()
    }
    
    @IBAction func pausePressed() {
        playButtonEnable()
        radioPlayer.pause()
    }
    
    // MARK: - UI Helper Methods
    
    func playButtonEnable(enabled: Bool = true) {
        playButton.isEnabled = enabled
        pauseButton.isEnabled = !enabled
    }
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        // TODO: Extract
        let songToShare = "I'm listening to [song] on \(RadioStation.WXYC.name)"
        let activityViewController = UIActivityViewController(activityItems: [songToShare, self.albumImageView.image ?? UIImage()], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
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
    
    // MARK: - Handoff Functionality - GH
    
    func setupUserActivity() {
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb ) //"com.graemeharrison.handoff.googlesearch" //NSUserActivityTypeBrowsingWeb
        userActivity = activity
        let url = "https://www.google.com/search?q=\(self.artistLabel.text!)+\(self.songLabel.text!)"
        let urlStr = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let searchURL : URL = URL(string: urlStr!)!
        activity.webpageURL = searchURL
        userActivity?.becomeCurrent()
    }
    
    override func updateUserActivityState(_ activity: NSUserActivity) {
        let url = "https://www.google.com/search?q=\(self.artistLabel.text!)+\(self.songLabel.text!)"
        let urlStr = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let searchURL : URL = URL(string: urlStr!)!
        activity.webpageURL = searchURL
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
}
