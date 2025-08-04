//
//  lora_datasetApp.swift
//  lora-dataset
//
//  Created by Rui Holdorf on 03/08/25.
//

import SwiftUI

@main
struct lora_datasetApp: App {
    
    init() {
        // Suprime logs de sistema desnecessários durante desenvolvimento
        #if DEBUG
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        setenv("CFNETWORK_DIAGNOSTICS", "0", 1)
        setenv("OS_SIGNPOST_ENABLED", "0", 1)
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
