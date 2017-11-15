import UIKit

//*****************************************************************
// Track struct
//*****************************************************************

struct Track {
	var title: String = ""
	var artist: String = ""
	var album: String = ""
	var artworkURL: String = ""
	var artworkImage = UIImage(named: "logo")
	var isPlaying: Bool = false
	var id: String = ""
}
