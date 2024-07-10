public struct RadioStation : Sendable {
    public let name: String
    public let secondaryName: String
    public let description: String
    public let requestLine: URL
}

public extension RadioStation {
    static let WXYC = RadioStation(
        name: "WXYC",
        secondaryName: "89.3 Chapel Hill",
        description: "WXYC 89.3 FM is the non-commercial student-run radio station of the University of North Carolina at Chapel Hill. We broadcast at 1100 watts from the student union on the UNC campus, 24 hours a day, 365 days a year. Our coverage area encompasses approximately 900 square miles in and around Chapel Hill, Durham, Pittsboro, Apex, and parts of Raleigh.",
        requestLine: URL(string: "tel://9199628989")!
    )
}
