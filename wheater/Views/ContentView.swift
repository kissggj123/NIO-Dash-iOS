//
//  ContentView.swift
//  wheater
//
//  YumikoToys 蔚来看板（iOS 二次元专属萌动版）
//

import SwiftUI

struct ContentView: View {
    @State private var isSplashFinished = false
    @ObservedObject private var themeService = AnimeThemeService.shared

    var body: some View {
        ZStack {
            // 主看板界面（在后台提前预加载渲染，彻底杜绝黑屏与卡顿）
            IOSNIODashboardView()

            // 像素萌动开屏启动动画层（像素绘制蔚来 Logo 与兔可可唤醒）
            if !isSplashFinished {
                NIOPixelLaunchSplashView(isFinished: $isSplashFinished)
                    .transition(
                        .asymmetric(
                            insertion: .identity,
                            removal: .opacity.combined(with: .scale(scale: 1.06))
                        )
                    )
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: isSplashFinished)
        .animation(.easeInOut(duration: 0.28), value: themeService.currentStyle)
        // 全局外观跟随 App 主题深浅（而非手机系统）：
        // 修复系统深色模式 + 浅色主题时导航栏/工具胶囊发灰、输入文字发白等问题
        .preferredColorScheme(themeService.currentToken.isDark ? .dark : .light)
    }
}
