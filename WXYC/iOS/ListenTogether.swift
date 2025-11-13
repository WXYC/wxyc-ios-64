//
//  ListenTogether.swift
//  WXYC
//
//  Created by Jake Bromberg on 5/14/25.
//

import Foundation
import GroupActivities
import Core
import CoreTransferable
import UIKit

struct ListenTogether: GroupActivity, Transferable {
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()

        metadata.title = RadioStation.WXYC.name
        metadata.subtitle = RadioStation.WXYC.secondaryName
        metadata.previewImage = UIImage(named: "AppIcon-Artwork")?.cgImage
        metadata.fallbackURL = RadioStation.WXYC.streamURL
        metadata.type = .listenTogether
        metadata.supportsContinuationOnTV = true
        metadata.lifetimePolicy = .automatic

        return metadata
    }

    private var radioPlayerController: RadioPlayerController {
        AppState.shared.radioPlayerController
    }

    func activate() async throws -> Bool {
        do {
            try await radioPlayerController.play(reason: "ListenTogether")
            return true
        } catch {
            return false
        }
    }
}
