//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/3/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import UIKit

protocol PlaylistServiceObserver {
    func updateWith(playcutResult: Result<Playcut>)
    func updateWith(artworkResult: Result<UIImage>)
}

final class PlaylistService {
    private let webservice = Webservice()
    private var observers: [PlaylistServiceObserver]
    private let playcutRequest: Future<Playcut>
    
    init(with initialObservers: PlaylistServiceObserver...) {
        self.observers = []
        for observer in initialObservers {
            self.observers.append(observer)
        }
        
        playcutRequest = Future.repeat(webservice.getCurrentPlaycut)
        playcutRequest.observe(with: self.updateWith(playcutResult:))
    }
    
    func add(_ observers: PlaylistServiceObserver...) {
        for observer in observers {
            self.observers.append(observer)
        }
    }
    
    func updateWith(playcutResult: Result<Playcut>) {
        if case let .error(error) = playcutResult, (error as? ServiceErrors) == .noNewData {
            return
        }
        
        for observer in observers {
            observer.updateWith(playcutResult: playcutResult)
        }
        
        guard case let .success(playcut) = playcutResult else {
            return
        }
        
        let imageRequest = playcut.getArtwork()
        imageRequest.observe(with: self.update(artworkResult:))
    }
    
    func update(artworkResult: Result<UIImage>) {
        if case let .error(error) = artworkResult, (error as? ServiceErrors) == .noNewData {
            return
        }
        
        for observer in observers {
            observer.updateWith(artworkResult: artworkResult)
        }
    }
}
