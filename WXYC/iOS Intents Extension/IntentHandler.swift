//
//  IntentHandler.swift
//  iOS Intents Extension
//
//  Created by Jake Bromberg on 12/12/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Intents

class IntentHandler: INExtension {
    
    override func handler(for intent: INIntent) -> Any {
        // This is the default implementation.  If you want different objects to handle different intents,
        // you can override this and return the handler you want for that particular intent.
        
        return self
    }
    
}
