//
//  mp3_playerApp.swift
//  mp3 player
//
//  Created by Ben Cross on 16.05.25.
//

import SwiftUI

@main
struct mp3_playerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 280, height: 300)
        .windowResizability(.contentMinSize)
    }
}
