//
//  WheaterWatchApp.swift
//  YumikoToysRRWatch
//
//  兔可可 · 腕上速览 watchOS App 入口（独立 App，不嵌入 iOS 包体）。
//  数据经 WatchConnectivity 由 iPhone 主 App 推送（WheaterWatch/ 设计见 WatchSession.swift）。
//

import SwiftUI

@main
struct WheaterWatchApp: App {
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
        }
    }
}
