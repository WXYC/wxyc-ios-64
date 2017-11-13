import UIKit

//*****************************************************************
// Radio Station
//*****************************************************************

// Class inherits from NSObject so that you may easily add features
// i.e. Saving favorite stations to CoreData, etc

class RadioStation: NSObject {
    
    var stationName     : String
    var stationStreamURL: String
    var stationImageURL : String
    var stationDesc     : String
    var stationLongDesc : String
    
    init(name: String, streamURL: String, imageURL: String, desc: String, longDesc: String) {
        self.stationName      = name
        self.stationStreamURL = streamURL
        self.stationImageURL  = imageURL
        self.stationDesc      = desc
        self.stationLongDesc  = longDesc
    }
    
    // Convenience init without longDesc
    convenience init(name: String, streamURL: String, imageURL: String, desc: String) {
        self.init(name: name, streamURL: streamURL, imageURL: imageURL, desc: desc, longDesc: "")
    }
}
