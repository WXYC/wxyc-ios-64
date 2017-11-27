import UIKit
import MediaPlayer

//*****************************************************************
// NowPlayingViewController
//*****************************************************************

class NowPlayingViewController: UIViewController, NowPlayingServiceDelegate {
    func update(nowPlayingInfo: NowPlayingInfo) {
        self.songLabel.text = nowPlayingInfo.primaryHeading
        self.artistLabel.text = nowPlayingInfo.secondaryHeading
    }
    
    func update(artwork: UIImage) {
        UIView.animate(withDuration: 0.25, animations: {
            self.albumImageView.image = artwork
        })
    }

    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var songLabel: SpringLabel!
    
    // TODO: this is getting axed when I replace the play/pause button. Plus all the notification handlers below.
    let radioPlayer = AVPlayer(url: URL.WXYCStream)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup handoff functionality - GH
        setupUserActivity()
        
        // Notification for AVAudioSession Interruption (e.g. Phone call)
        NotificationCenter.default.addObserver(self,
            selector: #selector(NowPlayingViewController.sessionInterrupted),
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance())
        
        // Remote events for play/pause taps on headphones
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        if !radioPlayer.isPlaying {
            pausePressed()
        }
    }
    
    deinit {
        // Be a good citizen
        NotificationCenter.default.removeObserver(self,
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance())
    }
    
    func resetStream() {
        let asset = AVAsset(url: URL.WXYCStream)
        let playerItem = AVPlayerItem(asset: asset)
        radioPlayer.replaceCurrentItem(with: playerItem)
    }
    
    @objc internal func playerItemFailedToPlayToEndTime(_ aNotification: Notification) {
        if kDebugLog {
            print("Network ERROR")
        }
        resetStream()
    }
    //*****************************************************************
    // MARK: - Player Controls (Play/Pause/Volume)
    //*****************************************************************
    // TODO: Combine into play/pause button and extract AVPlayer into its own object handled by the RootViewController
    @IBAction func playPressed() {
        playButtonEnable(enabled: false)
        radioPlayer.play()
        
        // songLabel Animation
        songLabel.animation = "flash"
        songLabel.animate()
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime(_:)), name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
       }
    
    @IBAction func pausePressed() {
        playButtonEnable()
        
        radioPlayer.pause()
        resetStream()
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
    }
    
    //*****************************************************************
    // MARK: - UI Helper Methods
    //*****************************************************************
    
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
    
    //*****************************************************************
    // MARK: - AVAudio Sesssion Interrupted
    //*****************************************************************
    
    // Example code on handling AVAudio interruptions (e.g. Phone calls)
    @objc func sessionInterrupted(notification: NSNotification) {
        if let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber{
            if let type = AVAudioSessionInterruptionType(rawValue: typeValue.uintValue){
                if type == .began {
                    print("interruption: began")
                } else{
                    print("interruption: ended")
                    playPressed()
                }
            }
        }
    }
    
    //*****************************************************************
    // MARK: - Handoff Functionality - GH
    //*****************************************************************
    
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

private extension AVPlayer {
    var isPlaying: Bool {
        return rate > 0.0
    }
}
