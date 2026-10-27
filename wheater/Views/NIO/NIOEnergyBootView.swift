//
//  NIOEnergyBootView.swift
//  wheater
//
//  能量充能启动动画 v5.0（默认风格）
//  电池环 0→100% 充能 → 数字滚动定格 → 电弧向心凝聚 → 高清 Logo 亮起 → 主题文案浮现
//  节奏跟随"标准 / 疾速"设置；触感尊重用户开关。
//

import SwiftUI

struct NIOEnergyBootView: View {
    @Binding var isFinished: Bool
    @ObservedObject private var themeService = AnimeThemeService.shared

    // 主题令牌快捷取色
    private var token: AnimeThemeToken { themeService.currentToken }
    private var text: Color { Color(hex: token.textPrimary) }
    private var textSoft: Color { Color(hex: token.textSecondary) }
    private var accent: Color { Color(hex: token.accentColor) }
    private var glow: Color { Color(hex: token.glowColor) }
    private var warm: Color { Color(hex: token.warmAccent) }
    private var gradientEnd: Color { Color(hex: token.gradientEnd) }
    private var isDark: Bool { token.isDark }

    private var persona: NIOBootPersona { NIOBootPersona.forTheme(themeService.currentStyle) }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "5.0.0"
    }

    private var pace: NIOBootPace { NIOBootPace.current }

    // 动画状态
    @State private var chargeProgress: Double = 0.0
    @State private var chargeStarted = false
    @State private var showLogo = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var boltPulse = false
    @State private var logoPulse = false
    @State private var arcScale1: CGFloat = 1.45
    @State private var arcOpacity1: Double = 0.0
    @State private var arcScale2: CGFloat = 1.2
    @State private var arcOpacity2: Double = 0.0

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()

            NIOBootSkipOverlay(isFinished: $isFinished, visible: showLogo)
                .zIndex(10)

            VStack(spacing: 30) {
                Spacer()

                // MARK: 电池充能环
                ZStack {
                    // 氛围光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.32 * persona.glowStrength), glow.opacity(0.14 * persona.glowStrength), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 105
                            )
                        )
                        .frame(width: 210, height: 210)
                        .scaleEffect(logoPulse ? 1.1 : 0.95)

                    // 向心凝聚电弧（充能完成瞬间收拢）
                    Circle()
                        .stroke(
                            LinearGradient(colors: [glow.opacity(0.9), accent.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .scaleEffect(arcScale1)
                        .opacity(arcOpacity1)

                    Circle()
                        .stroke(
                            LinearGradient(colors: [warm.opacity(0.75), accent.opacity(0.35)], startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .scaleEffect(arcScale2)
                        .opacity(arcOpacity2)

                    // 环轨道底槽
                    Circle()
                        .stroke(
                            accent.opacity(isDark ? 0.14 : 0.1),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)

                    // 充能进度环
                    Circle()
                        .trim(from: 0, to: max(0.004, chargeProgress))
                        .stroke(
                            AngularGradient(
                                colors: [accent, glow, gradientEnd, accent],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: accent.opacity(0.55 * persona.glowStrength), radius: persona.glowStrength > 0 ? 9 : 0)

                    // 内芯
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.04)]
                                    : [Color.white.opacity(0.92), Color.white.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 134, height: 134)

                    // 中心内容：充能数字 ↔ 高清 Logo
                    ZStack {
                        if showLogo {
                            logoView
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        } else {
                            chargingCore
                                .transition(.opacity)
                        }
                    }
                }
                .frame(width: 210, height: 210)

                // MARK: 标题与状态
                VStack(spacing: 8) {
                    if showTitle {
                        VStack(spacing: 4) {
                            Text(persona.topLabel)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .tracking(4)
                                .foregroundStyle(
                                    LinearGradient(colors: [glow, warm], startPoint: .leading, endPoint: .trailing)
                                )

                            Text("蔚来 · 兔可可")
                                .font(.system(size: 27, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [text, accent], startPoint: .leading, endPoint: .trailing)
                                )
                                .shadow(color: accent.opacity(persona.glowStrength * 0.6), radius: persona.glowStrength * 10)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if showSubtitle {
                        HStack(spacing: 6) {
                            Text(persona.statusEmoji)
                                .font(.system(size: 13))
                            Text(persona.subtitle)
                                .font(.system(size: 12, weight: .bold, design: persona.subtitleMono ? .monospaced : .rounded))
                                .foregroundStyle(textSoft.opacity(0.95))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 0.8))
                        .shadow(color: accent.opacity(0.15 * persona.glowStrength), radius: 6)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .frame(height: 85)

                Spacer()

                Text("v\(appVersion) · NIO Space • Designed with 🐰兔可可 🥕")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(text.opacity(0.4))
                    .padding(.bottom, 24)
            }
        }
        .onAppear { runChargeSequence() }
    }

    // MARK: - 充能核心（数字 + 闪电）

    private var chargingCore: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [accent, glow], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: accent.opacity(0.6 * persona.glowStrength), radius: persona.glowStrength > 0 ? 6 : 0)
                .scaleEffect(boltPulse ? 1.18 : 0.92)
                .animation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true), value: boltPulse)

            Text("\(Int((chargeProgress * 100).rounded()))")
                .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(text)
                .contentTransition(.numericText(value: chargeProgress))

            Text("CHARGING")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(3)
                .foregroundStyle(accent.opacity(0.8))
        }
    }

    // MARK: - 高清 Logo

    private var logoView: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(colors: [accent, glow, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2.5
                )
                .frame(width: 104, height: 104)
                .shadow(color: accent.opacity(0.7 * persona.glowStrength), radius: persona.glowStrength > 0 ? 10 : 0)
                .scaleEffect(logoPulse ? 1.04 : 0.98)
                .animation(persona.glowStrength > 0 ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil, value: logoPulse)

            Circle()
                .fill(isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.65))
                .frame(width: 92, height: 92)

            Image("NIO_brand")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 62, height: 62)
                .clipShape(Circle())
                .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 4)
        }
    }

    // MARK: - 主题化背景

    private var splashBackground: some View {
        ZStack {
            Color(hex: token.backgroundPrimary)

            RadialGradient(
                colors: [accent.opacity(isDark ? 0.3 : 0.22), Color.clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 300
            )

            RadialGradient(
                colors: [glow.opacity(isDark ? 0.2 : 0.16), Color.clear],
                center: .bottomTrailing,
                startRadius: 50,
                endRadius: 350
            )
        }
    }

    // MARK: - 时序控制器

    private func runChargeSequence() {
        let chargeDuration = pace.t(1.5)

        // 1. 电池环充能 0→100%（数字同步滚动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            chargeStarted = true
            boltPulse = true
            withAnimation(.easeInOut(duration: chargeDuration)) {
                chargeProgress = 1.0
            }
        }

        // 2. 充能完成：电弧向心凝聚 + Logo 亮起
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + chargeDuration + 0.05) {
            NIOBootHaptics.impact(.medium)

            withAnimation(.spring(response: 0.46, dampingFraction: 0.68)) {
                showLogo = true
                logoPulse = true
            }

            withAnimation(.easeOut(duration: 0.32)) {
                arcScale1 = 0.94
                arcOpacity1 = 0.9
            }
            withAnimation(.easeOut(duration: 0.5)) {
                arcScale2 = 0.96
                arcOpacity2 = 0.7
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.6)) {
                    arcOpacity1 = 0.0
                }
                withAnimation(.easeOut(duration: 0.8)) {
                    arcOpacity2 = 0.0
                }
            }
        }

        // 3. 标题浮现
        DispatchQueue.main.asyncAfter(deadline: .now() + pace.t(2.0)) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                showTitle = true
            }
        }

        // 4. 副标浮现
        DispatchQueue.main.asyncAfter(deadline: .now() + pace.t(2.25)) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                showSubtitle = true
            }
        }

        // 5. 静置停留后进入看板
        DispatchQueue.main.asyncAfter(deadline: .now() + pace.t(3.1)) {
            withAnimation(.easeInOut(duration: 0.38)) {
                isFinished = true
            }
        }
    }
}
