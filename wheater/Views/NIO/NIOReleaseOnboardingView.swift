//
//  NIOReleaseOnboardingView.swift
//  wheater
//
//  版本更新引导页（OOTD · Onboarding of the Day）：
//  · 首次安装 → 欢迎引导（欢迎语 + 最新版特性速览）
//  · 版本更新后首次启动 → 本版新特性引导
//  每个版本只弹一次，看完即记录，不再打扰。
//

import SwiftUI

struct NIOReleaseOnboardingView: View {
    let isWelcome: Bool
    let onDismiss: () -> Void

    @ObservedObject private var themeService = AnimeThemeService.shared

    private var token: AnimeThemeToken { themeService.currentToken }
    private var accent: Color { Color(hex: token.accentColor) }
    private var glow: Color { Color(hex: token.glowColor) }
    private var gradientStart: Color { Color(hex: token.gradientStart) }
    private var gradientEnd: Color { Color(hex: token.gradientEnd) }
    private var textPrimary: Color { Color(hex: token.textPrimary) }

    private var release: NIOAboutRelease? { NIOAboutReleases.all.first }

    var body: some View {
        ZStack {
            // 主题色背景 + 极光光晕
            Color(hex: token.backgroundPrimary).ignoresSafeArea()
            RadialGradient(
                colors: [gradientStart.opacity(0.35), .clear],
                center: .topLeading, startRadius: 40, endRadius: 420
            ).ignoresSafeArea()
            RadialGradient(
                colors: [glow.opacity(0.28), .clear],
                center: .bottomTrailing, startRadius: 40, endRadius: 460
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                header

                if let release {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(release.items.indices, id: \.self) { idx in
                                let item = release.items[idx]
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.category)
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(accent)
                                    ForEach(item.points, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(glow.opacity(0.85))
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 6)
                                            Text(point)
                                                .font(.subheadline)
                                                .foregroundStyle(textPrimary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: token.cardBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                }

                Spacer(minLength: 12)

                Button(action: onDismiss) {
                    Text(isWelcome ? "开始体验" : "看看更新了什么")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            LinearGradient(colors: [gradientStart, gradientEnd], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .shadow(color: glow.opacity(0.45), radius: 10, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .transition(.opacity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            // App 图标（阴影随主题光晕）
            Group {
                if let icon = UIImage(named: "AppIconPreview") {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: isWelcome ? "sparkles" : "arrow.up.circle.fill")
                        .font(.system(size: 42, weight: .bold))
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(gradientStart.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: glow.opacity(0.5), radius: 10, y: 4)
            Text(isWelcome ? "欢迎来到蔚来看板" : "蔚来看板已更新")
                .font(.title.weight(.heavy))
                .foregroundStyle(textPrimary)
            Text(isWelcome ? "专为蔚来车主打造的二次元萌系车况看板" : release?.version ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - 弹出门控（每个版本只弹一次；首次安装走欢迎分支）

enum NIOReleaseOnboardingGate {
    private static let seenVersionKey = "nio_onboarding_seen_version"

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// 是否需要弹出（首次安装 = 欢迎引导；版本变化 = 更新引导）
    static func shouldShow() -> Bool {
        UserDefaults.standard.string(forKey: seenVersionKey) != currentVersion
    }

    static var isWelcome: Bool {
        UserDefaults.standard.string(forKey: seenVersionKey) == nil
    }

    static func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: seenVersionKey)
    }
}
