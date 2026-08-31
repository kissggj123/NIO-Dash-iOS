//
//  wheaterApp.swift
//  wheater
//
//  Created by Hanif Fadillah Amrynudin on 31/08/22.
//

import SwiftUI
import UserNotifications

@main
struct wheaterApp: App {
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                print("[Notification] Push notification permissions granted")
            }
        }
    }
  
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
