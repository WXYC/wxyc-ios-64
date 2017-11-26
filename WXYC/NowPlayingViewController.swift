import UIKit
import MediaPlayer

//*****************************************************************
// NowPlayingViewController
//*****************************************************************

class NowPlayingViewController: UIViewController {
    let webservice = Webservice()

    @IBOutlet weak var albumImageView: UIImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var volumeParentView: UIView!
    @IBOutlet weak var slider = UISlider()
    
    var nowPlayingImageView: UIImageView!
    let radioPlayer = AVPlayer(url: URL.WXYCStream)
    var track: Track = Track()
    var mpVolumeSlider = UISlider()
    var obs: NSKeyValueObservation?
    
    //*****************************************************************
    // MARK: - ViewDidLoad
    //*****************************************************************

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup handoff functionality - GH
        setupUserActivity()
        
        // Set View Title
        self.title = RadioStation.WXYC.name
        
        // Create Now Playing BarItem
        createNowPlayingAnimation()
        
        // Notification for when app becomes active
        NotificationCenter.default.addObserver(self,
            selector: #selector(NowPlayingViewController.didBecomeActiveNotificationReceived),
            name: Notification.Name.UIApplicationDidBecomeActive,
            object: nil)
        
        
        // Notification for AVAudioSession Interruption (e.g. Phone call)
        NotificationCenter.default.addObserver(self,
            selector: #selector(NowPlayingViewController.sessionInterrupted),
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance())
        
        // Notification and Slider Updates for Volume Changes
        self.obs = AVAudioSession.sharedInstance().observe( \.outputVolume ) { (av, change) in
            self.slider?.setValue(av.outputVolume, animated: true)
        }
        
        updateLabels()
        
        if !radioPlayer.isPlaying {
            pausePressed()
        } else {
            nowPlayingImageView.startAnimating()
        }
        
        stationDidChange()
        
        // Setup slider
        setupVolumeSlider()
        
        _ = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.checkPlaylist), userInfo: nil, repeats: true)
        
        self.albumImageView.image = UIImage(named: "logo")
    }
    
    @objc func didBecomeActiveNotificationReceived() {
        // View became active
        updateLabels()
        if !radioPlayer.isPlaying {
            resetStream()
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    deinit {
        // Be a good citizen
        NotificationCenter.default.removeObserver(self,
            name: Notification.Name.UIApplicationDidBecomeActive,
            object: nil)
        NotificationCenter.default.removeObserver(self,
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance())
        //TODO figure out how to deinit the volume change observer!
    }
    
    @objc func checkPlaylist() {
        let playcutRequest = webservice.getCurrentPlaycut()
        playcutRequest.observe(with: self.updateWith(playcutResult:))
        
        let imageRequest = playcutRequest.getArtwork()
        imageRequest.observe(with: self.update(artworkResult:))
    }
    
    func update(artworkResult: Result<UIImage>) {
        if case let .success(image) = artworkResult {
            DispatchQueue.main.async {
                self.albumImageView.image = image
            }
        }
    }

    //*****************************************************************
    // MARK: - Setup
    //*****************************************************************
  
    func setupVolumeSlider() {
        // Note: This slider implementation uses a MPVolumeView
        // The volume slider only works in devices, not the simulator.
        volumeParentView.backgroundColor = UIColor.clear
        let volumeView = MPVolumeView(frame: volumeParentView.bounds)
        for view in volumeView.subviews {
            let uiview: UIView = view as UIView
            if (uiview.description as NSString).range(of: "MPVolumeSlider").location != NSNotFound {
                mpVolumeSlider = (uiview as! UISlider)
            }
        }
        
        slider?.setValue(AVAudioSession.sharedInstance().outputVolume, animated: true)
        let thumbImageNormal = UIImage(named: "slider-ball")
        slider?.setThumbImage(thumbImageNormal, for: .normal)
        
    }
    
    func stationDidChange() {
        radioPlayer.pause()
        resetStream()
        playButtonEnable()
        
        updateLabels(statusMessage: "Loading...")
        
        // songLabel animate
        songLabel.animation = "flash"
        songLabel.animate()
        
        self.checkPlaylist()
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
    
    @IBAction func playPressed() {
        playButtonEnable(enabled: false)
        radioPlayer.play()
        updateLabels()
        
        // songLabel Animation
        songLabel.animation = "flash"
        songLabel.animate()
        
        // Start NowPlaying Animation
        nowPlayingImageView.startAnimating()
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime(_:)), name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
       }
    
    @IBAction func pausePressed() {
        playButtonEnable()
        
        radioPlayer.pause()
        resetStream()
        updateLabels(statusMessage: "Station Paused...")
        nowPlayingImageView.stopAnimating()
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil)
    }
    
    @IBAction func volumeChanged(_ sender:UISlider) {
        mpVolumeSlider.value = sender.value
    }
    
    //*****************************************************************
    // MARK: - UI Helper Methods
    //*****************************************************************
    
    func updateLabels(statusMessage: String? = nil) {
        if let statusMessage = statusMessage {
            // There's a an interruption or pause in the audio queue
            songLabel.text = statusMessage
            artistLabel.text = RadioStation.WXYC.name
        } else {
            // Radio is (hopefully) streaming properly
            songLabel.text = track.title
            artistLabel.text = track.artist
        }
    }
    
    func playButtonEnable(enabled: Bool = true) {
        if enabled {
            playButton.isEnabled = true
            pauseButton.isEnabled = false
        } else {
            playButton.isEnabled = false
            pauseButton.isEnabled = true
        }
    }
    
    func createNowPlayingAnimation() {
        
        // Setup ImageView
        nowPlayingImageView = UIImageView(image: UIImage(named: "NowPlayingBars-3"))
        nowPlayingImageView.autoresizingMask = []
        nowPlayingImageView.contentMode = UIViewContentMode.center
        
        // Create Animation
        nowPlayingImageView.animationImages = AnimationFrames.createFrames()
        nowPlayingImageView.animationDuration = 0.7
        
        // Create Top BarButton
        let barButton = UIButton(type: UIButtonType.custom)
        barButton.frame = CGRect(x: 0,y: 0,width: 40,height: 40);
        barButton.addSubview(nowPlayingImageView)
        nowPlayingImageView.center = barButton.center
        
        let barItem = UIBarButtonItem(customView: barButton)
        self.navigationItem.rightBarButtonItem = barItem
    }
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        let songToShare = "I'm listening to \(track.title) on \(RadioStation.WXYC.name)"
        let activityViewController = UIActivityViewController(activityItems: [songToShare, track.artworkImage], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }
    
    //*****************************************************************
    // MARK: - MPNowPlayingInfoCenter (Lock screen)
    //*****************************************************************
    
    func updateLockScreen() {
        
        // Update notification/lock screen
        
        let image:UIImage = track.artworkImage
        let albumArtwork = MPMediaItemArtwork.init(boundsSize: image.size, requestHandler: { (size) -> UIImage in
            return image
        })
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtwork: albumArtwork,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: radioPlayer.rate
        ]
    }
    
    override func remoteControlReceived(with receivedEvent: UIEvent?) {
        super.remoteControlReceived(with: receivedEvent)
        
        guard let receivedEvent = receivedEvent else {
            return
        }
        
        switch (receivedEvent.subtype) {
        case (.remoteControlPlay):
            playPressed()
        case (.remoteControlPause):
            pausePressed()
        case (.remoteControlTogglePlayPause):
            radioPlayer.isPlaying ? pausePressed() : playPressed()
        default:
            break
        }
    }
    
    func updateWith(playcutResult result: Result<Playcut>) {
        guard case let .success(playcut) = result else {
            return
        }
        
        let currentSongName = self.track.title
        
        self.track.artist = playcut.artistName
        self.track.title = playcut.songTitle
        self.track.id = "\(playcut.id)"
        self.track.album = playcut.releaseTitle
        
        if self.track.artist == "" && self.track.title == "" {
            self.track.artist = RadioStation.WXYC.desc
            self.track.title = RadioStation.WXYC.name
        }
        
        guard currentSongName != self.track.title else {
            return
        }
        
        DispatchQueue.main.async {
            if kDebugLog {
                print("METADATA artist: \(self.track.artist) | title: \(self.track.title) | album: \(self.track.album)")
            }
            
            // Update Labels
            self.artistLabel.text = self.track.artist
            self.songLabel.text = self.track.title
            self.updateUserActivityState(self.userActivity!)
            
            // songLabel animation
            self.songLabel.animation = "zoomIn"
            self.songLabel.duration = 1.5
            self.songLabel.damping = 1
            self.songLabel.animate()
            
            // Query API for album art
            self.updateLockScreen()
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
                    stationDidChange()
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
        return rate == 0.0
    }
}
