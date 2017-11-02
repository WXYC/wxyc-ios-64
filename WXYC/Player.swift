import AVFoundation

//*****************************************************************
// This is a singleton struct using Swift
//*****************************************************************

let streamURL = URL(string: "http://audio-mp3.ibiblio.org:8000/wxyc.mp3")

struct Player {
    static let radio = AVPlayer(url: streamURL!)
}
