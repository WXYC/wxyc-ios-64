import Foundation

struct RadioStation {
    let name     : String
    let streamURL: String
    let imageURL : String
    let desc     : String
    let longDesc : String
}

extension RadioStation {
    static var WXYC: RadioStation {
        return RadioStation(
            name: "WXYC - Chapel Hill",
            streamURL: URL.WXYCStream.absoluteString,
            imageURL: "",
            desc: "",
            longDesc: "WXYC 89.3 FM is the non-commercial student-run radio station of the University of North Carolina at Chapel Hill. We broadcast at 1100 watts from the student union on the UNC campus, 24 hours a day, 365 days a year. Our coverage area encompasses approximately 900 square miles in and around Chapel Hill, Durham, Pittsboro, Apex, and parts of Raleigh."
        )
    }
}
