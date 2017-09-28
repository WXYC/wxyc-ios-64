//
//  NowPlayingViewController.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/22/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//

import UIKit
import MediaPlayer

//create custom notification
extension Notification.Name {
static let onPlaylistUpdate = Notification.Name("on-playlist-update")
}

//*****************************************************************
// Protocol
// Updates the StationsViewController when the track changes
//*****************************************************************

//protocol NowPlayingViewControllerDelegate: class {
//    func songMetaDataDidUpdate(track: Track)
//    func artworkDidUpdate(track: Track)
//    func trackPlayingToggled(track: Track)
//}

//*****************************************************************
// NowPlayingViewController
//*****************************************************************

class NowPlayingViewController: UIViewController {

    @IBOutlet weak var albumHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var albumImageView: SpringImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var stationDescLabel: UILabel!
    @IBOutlet weak var volumeParentView: UIView!
    @IBOutlet weak var slider = UISlider()
    
    var currentStation: RadioStation!
    var downloadTask: URLSessionDownloadTask?
    var iPhone4 = false
    var justBecameActive = false
    var newStation = true
    var nowPlayingImageView: UIImageView!
    let radioPlayer = Player.radio
    var track: Track!
    var mpVolumeSlider = UISlider()


    
    //weak var delegate: NowPlayingViewControllerDelegate?
    
    //*****************************************************************
    // MARK: - ViewDidLoad
    //*****************************************************************
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup handoff functionality - GH
        setupUserActivity()
        
        // Setup Radio Statio
        // Add your radio station information here:
        currentStation = RadioStation(
            name: "WXYC - Chapel Hill",
                streamURL: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3",
                imageURL: "",
                desc: "",
                longDesc: "WXYC 89.3 FM is the non-commercial student-run radio station of the University of North Carolina at Chapel Hill. We broadcast at 1100 watts from the student union on the UNC campus, 24 hours a day, 365 days a year. Our coverage area encompasses approximately 900 square miles in and around Chapel Hill, Durham, Pittsboro, Apex, and parts of Raleigh."
        )
        
        // Set AlbumArtwork Constraints
        optimizeForDeviceSize()

        // Set View Title
        self.title = currentStation.stationName
        
        // Create Now Playing BarItem
        createNowPlayingAnimation()
        
        // Setup MPMoviePlayerController
        // If you're building an app for a client, you may want to
        // replace the MediaPlayer player with a more robust 
        // streaming library/SDK. Preferably one that supports interruptions, etc.
        // Most of the good streaming libaries are in Obj-C, however they
        // will work nicely with this Swift code. There is a branch using RadioKit if 
        // you need an example of how nicely this code integrates with libraries.
        setupPlayer()
        
        // Notification for when app becomes active
        NotificationCenter.default.addObserver(self,
            selector: #selector(NowPlayingViewController.didBecomeActiveNotificationReceived),
            name: Notification.Name("UIApplicationDidBecomeActiveNotification"),
            object: nil)
        
        // Notification for MediaPlayer metadata updated
        NotificationCenter.default.addObserver(self,
            selector: #selector(NowPlayingViewController.metadataUpdated),
            name: Notification.Name.onPlaylistUpdate,
            object: nil)
        
        // Notification for AVAudioSession Interruption (e.g. Phone call)
        NotificationCenter.default.addObserver(self,
            selector: #selector(NowPlayingViewController.sessionInterrupted),
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance())
        
        // Check for station change
        if newStation {
            track = Track()
            stationDidChange()
        } else {
            updateLabels()
            albumImageView.image = track.artworkImage
            
            if !track.isPlaying {
                pausePressed()
            } else {
                nowPlayingImageView.startAnimating()
            }
        }
        
        // Setup slider
        setupVolumeSlider()
        
        var timer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(self.checkPlaylist), userInfo: nil, repeats: true)
        
    }
    
    @objc func didBecomeActiveNotificationReceived() {
        // View became active
        updateLabels()
        justBecameActive = true
        updateAlbumArtwork()
    }
    
    deinit {
        // Be a good citizen
        NotificationCenter.default.removeObserver(self,
            name: Notification.Name("UIApplicationDidBecomeActiveNotification"),
            object: nil)
        NotificationCenter.default.removeObserver(self,
            name: Notification.Name.onPlaylistUpdate,
            object: nil)
        NotificationCenter.default.removeObserver(self,
            name: Notification.Name.AVAudioSessionInterruption,
            object: AVAudioSession.sharedInstance())
    }
    

    @objc func checkPlaylist() {

        if track.isPlaying == true {
            let queryURL = "http://wxyc.info/playlists/recentEntries?v=2&n=15"
            let escapedURL = queryURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            // Query API
            DataManager.getPlaylistDataWithSuccess(queryURL: escapedURL!) { (data) in
                
                if kDebugLog {
                    print("API SUCCESSFUL RETURN")
                    print("url: \(escapedURL!)")
                }

            let json = JSON(data: data! as Data)
            let id = json["playcuts"][0]["id"].stringValue

            if id != self.track.id {
               NotificationCenter.default.post(name: .onPlaylistUpdate, object: nil)
            }

            } 
        }
    }

    //*****************************************************************
    // MARK: - Setup
    //*****************************************************************
    
    func setupPlayer() {
        radioPlayer.view.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
        radioPlayer.view.sizeToFit()
        radioPlayer.movieSourceType = MPMovieSourceType.streaming
        radioPlayer.isFullscreen = false
        radioPlayer.shouldAutoplay = true
        radioPlayer.prepareToPlay()
        radioPlayer.controlStyle = MPMovieControlStyle.none
    }
  
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
        
        let thumbImageNormal = UIImage(named: "slider-ball")
        slider?.setThumbImage(thumbImageNormal, for: .normal)
        
    }
    
    func stationDidChange() {
        radioPlayer.stop()
        
        radioPlayer.contentURL = URL(string: currentStation.stationStreamURL)
        radioPlayer.prepareToPlay()
        radioPlayer.play()
        startNowPlayingAnimation()
        
        updateLabels(statusMessage: "Loading Station...")
        
        // songLabel animate
        songLabel.animation = "flash"
        songLabel.repeatCount = 2
        songLabel.animate()
        
        resetAlbumArtwork()
        
        track.isPlaying = true
        NotificationCenter.default.post(name: .onPlaylistUpdate, object: nil)
    }
    
    //*****************************************************************
    // MARK: - Player Controls (Play/Pause/Volume)
    //*****************************************************************
    
    @IBAction func playPressed() {
        track.isPlaying = true
        playButtonEnable(enabled: false)
        radioPlayer.play()
        updateLabels()
        
        // songLabel Animation
        songLabel.animation = "flash"
        songLabel.animate()
        
        // Start NowPlaying Animation
        nowPlayingImageView.startAnimating()
        
        // Update StationsVC
        //self.delegate?.trackPlayingToggled(track: self.track)
    }
    
    @IBAction func pausePressed() {
        track.isPlaying = false
        
        playButtonEnable()
        
        radioPlayer.pause()
        updateLabels(statusMessage: "Station Paused...")
        nowPlayingImageView.stopAnimating()
        
        // Update StationsVC
        //self.delegate?.trackPlayingToggled(track: self.track)
    }
    
    @IBAction func volumeChanged(_ sender:UISlider) {
        mpVolumeSlider.value = sender.value
    }
    
    //*****************************************************************
    // MARK: - UI Helper Methods
    //*****************************************************************
    
    func optimizeForDeviceSize() {
        
        // Adjust album size to fit iPhone 4s, 6s & 6s+
        let deviceHeight = self.view.bounds.height
        
        if deviceHeight == 480 {
            iPhone4 = true
            albumHeightConstraint.constant = 106
            view.updateConstraints()
        } else if deviceHeight == 667 {
            albumHeightConstraint.constant = 230
            view.updateConstraints()
        } else if deviceHeight > 667 {
            albumHeightConstraint.constant = 260
            view.updateConstraints()
        }
    }
    
    func updateLabels(statusMessage: String = "") {
        
        if statusMessage != "" {
            // There's a an interruption or pause in the audio queue
            songLabel.text = statusMessage
            artistLabel.text = currentStation.stationName
            
        } else {
            // Radio is (hopefully) streaming properly
            if track != nil {
                songLabel.text = track.title
                artistLabel.text = track.artist
            }
        }
        
        // Hide station description when album art is displayed or on iPhone 4
        if track.artworkLoaded || iPhone4 {
            stationDescLabel.isHidden = true
        } else {
            stationDescLabel.isHidden = false
            stationDescLabel.text = currentStation.stationDesc
        }
    }
    
    func playButtonEnable(enabled: Bool = true) {
        if enabled {
            playButton.isEnabled = true
            pauseButton.isEnabled = false
            track.isPlaying = false
        } else {
            playButton.isEnabled = false
            pauseButton.isEnabled = true
            track.isPlaying = true
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
    
    func startNowPlayingAnimation() {
        nowPlayingImageView.startAnimating()
    }
    
    //*****************************************************************
    // MARK: - Album Art
    //*****************************************************************
    
    func resetAlbumArtwork() {
        track.artworkLoaded = false
        track.artworkURL = currentStation.stationImageURL
        updateAlbumArtwork()
        DispatchQueue.main.async(execute: {
            //self.albumImageView.image = nil
            self.stationDescLabel.isHidden = false
        })
    }
    
    func updateAlbumArtwork() {
        track.artworkLoaded = false
        if track.artworkURL.range(of: "http") != nil {
            
            // Hide station description
            DispatchQueue.main.async(execute: {
                //self.albumImageView.image = nil
                self.stationDescLabel.isHidden = false
            })
            
            // Attempt to download album art from an API
            if let url = URL(string: track.artworkURL) {
                
                self.downloadTask = self.albumImageView.loadImageWithURL(url: url) { (image) in
                    
                    // Update track struct
                    self.track.artworkImage = image
                    self.track.artworkLoaded = true
                    
                    // Turn off network activity indicator
                    UIApplication.shared.isNetworkActivityIndicatorVisible = false
                        
                    // Animate artwork
                    self.albumImageView.animation = "fadeIn"
                    self.albumImageView.duration = 2
                    self.albumImageView.animate()
                    self.stationDescLabel.isHidden = true

                    // Update lockscreen
                    self.updateLockScreen()
                    
                    // Call delegate function that artwork updated
                    //self.delegate?.artworkDidUpdate(track: self.track)
                }
            }
            
            // Hide the station description to make room for album art
            if track.artworkLoaded && !self.justBecameActive {
                self.stationDescLabel.isHidden = true
                self.justBecameActive = false
            }
            
        } else if track.artworkURL != "" {
            // Local artwork
            self.albumImageView.image = UIImage(named: track.artworkURL)
            track.artworkImage = albumImageView.image
            track.artworkLoaded = true
            
            // Call delegate function that artwork updated
            //self.delegate?.artworkDidUpdate(track: self.track)
            
        } else {
            // No Station or API art found, use default art
            DispatchQueue.main.async(execute: {
                self.albumImageView.image = UIImage(named: "albumArt")
                self.track.artworkImage = self.albumImageView.image
            })
        }
        
        // Force app to update display
        DispatchQueue.main.async(execute: {
            self.view.setNeedsDisplay()
        })
    }

    // Call LastFM or iTunes API to get album art url
    
    func getItunesArt() {
        let queryURL: String
        queryURL = String(format: "https://itunes.apple.com/search?term=%@+%@&entity=song", track.artist, track.title)
        let escapedURL = queryURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

        DataManager.getTrackDataWithSuccess(queryURL: escapedURL!) { (data) in
            
            if kDebugLog {
                print("API SUCCESSFUL RETURN")
                print("url: \(escapedURL!)")
            }
            
            let json = JSON(data: data! as Data)

            if let artURL = json["results"][0]["artworkUrl100"].string {
            
                if kDebugLog { print("iTunes artURL: \(artURL)") }
            
                self.track.artworkURL = artURL
                self.track.artworkLoaded = true
                self.updateAlbumArtwork()
            } else {
                self.resetAlbumArtwork()
                }
        }
    }

    func queryAlbumArt() {
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
                
        if useLastFM {
            let queryURL: String
            queryURL = String(format: "http://ws.audioscrobbler.com/2.0/?method=album.getInfo&api_key=%@&artist=%@&album=%@&format=json", apiKey, track.artist, track.album)
            let escapedURL = queryURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

            DataManager.getTrackDataWithSuccess(queryURL: escapedURL!) { (data) in
            
            if kDebugLog {
                print("API SUCCESSFUL RETURN")
                print("url: \(escapedURL!)")
            }
            
            let json = JSON(data: data! as Data)

            // Get Largest Sized LastFM Image
            if let imageArray = json["album"]["image"].array {
                
                let arrayCount = imageArray.count
                let lastImage = imageArray[arrayCount - 1]
                
                if let artURL = lastImage["#text"].string {

                    if kDebugLog { print("lastFM artURL: \(artURL)") }
                    
                    // Check for Default Last FM Image
                    if artURL.range(of: "/noimage/") != nil || artURL == "" {
                        self.getItunesArt()
                        
                    } else {
                        // LastFM image found!
                        self.track.artworkURL = artURL
                        self.track.artworkLoaded = true
                        self.updateAlbumArtwork()
                    }
                    
                } else {
                    self.getItunesArt()
                }
            } else {
                self.getItunesArt()
            }
        }


        } else {
            getItunesArt()
        }
    }
    
    //*****************************************************************
    // MARK: - Segue
    //*****************************************************************
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "InfoDetail" {
            let infoController = segue.destination as! InfoDetailViewController
            infoController.currentStation = currentStation
        }
    }
    
    @IBAction func infoButtonPressed(_ sender: UIButton) {
        performSegue(withIdentifier: "InfoDetail", sender: self)
    }
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        let songToShare = "I'm listening to \(track.title) on \(currentStation.stationName)"
        let activityViewController = UIActivityViewController(activityItems: [songToShare, track.artworkImage!], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }
    
    //*****************************************************************
    // MARK: - MPNowPlayingInfoCenter (Lock screen)
    //*****************************************************************
    
    func updateLockScreen() {
        
        // Update notification/lock screen
        let albumArtwork = MPMediaItemArtwork(image: track.artworkImage!)
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtwork: albumArtwork
        ]
    }
    
    override func remoteControlReceived(with receivedEvent: UIEvent?) {
        super.remoteControlReceived(with: receivedEvent)
        
        if receivedEvent!.type == UIEventType.remoteControl {
            
            switch receivedEvent!.subtype {
            case .remoteControlPlay:
                playPressed()
            case .remoteControlPause:
                pausePressed()
            default:
                break
            }
        }
    }
    
    //*****************************************************************
    // MARK: - MetaData Updated Notification
    //*****************************************************************

    @objc func metadataUpdated(n: NSNotification)
    {   
        print("metadata function running...")
        let queryURL = "http://wxyc.info/playlists/recentEntries?v=2&n=15"
        
        let escapedURL = queryURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        
        // Query API
        DataManager.getPlaylistDataWithSuccess(queryURL: escapedURL!) { (data) in
            
            if kDebugLog {
                print("API SUCCESSFUL RETURN")
                print("url: \(escapedURL!)")
            }
            
            let json = JSON(data: data! as Data)

            let artist = json["playcuts"][0]["artistName"].stringValue
            let song = json["playcuts"][0]["songTitle"].stringValue
            let id = json["playcuts"][0]["id"].stringValue
            let album = json["playcuts"][0]["releaseTitle"].stringValue

            print (artist)
            print (song)
            print (id)
            print (album)

            // Set artist & songvariables
            let currentSongName = self.track.title
            self.track.artist = artist
            self.track.title = song
            self.track.id = id
            self.track.album = album
            
            if self.track.artist == "" && self.track.title == "" {
                self.track.artist = self.currentStation.stationDesc
                self.track.title = self.currentStation.stationName
            }
            
            DispatchQueue.main.async(execute: {
                
                if currentSongName != self.track.title {
                    
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
                    
                    // Update Stations Screen
                    //self.delegate?.songMetaDataDidUpdate(track: self.track)
                    
                    // Query API for album art
                    self.queryAlbumArt()
                    self.resetAlbumArtwork()
                    self.updateLockScreen()
                    
                }
            })
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
                    // Add your code here
                } else{
                    print("interruption: ended")
                    // Add your code here
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
