import UIKit

//*****************************************************************
// Track struct
//*****************************************************************

struct Track {
	var title: String = ""
	var artist: String = ""
	var album: String = ""
	var artworkURL: String = ""
	var artworkImage = UIImage(named: "albumArt")
	var artworkLoaded = false
	var isPlaying: Bool = false
	var id: String = ""
}
