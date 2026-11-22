//
//  ContentView.swift
//  wheater
//
//  NIO vehicle dashboard entry point
//

import SwiftUI

struct ContentView: View {
    @State private var isSplashFinished = false
    @State private var showOnboarding = false
    @ObservedObject private var themeService = AnimeThemeService.shared

    var body: some View {
        ZStack {
            IOSNIODashboardView()

            if !isSplashFinished {
                NIOLaunchSplashView(isFinished: $isSplashFinished)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(1)
            }

            // 版本更新引导页（每个版本只弹一次，首次安装为欢迎引导）
            if showOnboarding {
                NIOReleaseOnboardingView(isWelcome: NIOReleaseOnboardingGate.isWelcome) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showOnboarding = false
                    }
                    NIOReleaseOnboardingGate.markSeen()
                }
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: isSplashFinished)
        .animation(.easeInOut(duration: 0.28), value: themeService.currentStyle)
        .tint(themeService.accentColor())
        .preferredColorScheme(themeService.currentToken.isDark ? .dark : .light)
        .onChange(of: isSplashFinished) { _, finished in
            // 开屏动画结束后检查版本引导门控
            if finished, NIOReleaseOnboardingGate.shouldShow() {
                withAnimation(.easeIn(duration: 0.35)) {
                    showOnboarding = true
                }
            }
        }
    }
}
