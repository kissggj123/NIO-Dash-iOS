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

    // 华丽特效层状态（v5.1）
    @State private var orbitSpinning = false          // 轨道电子旋转
    @State private var dustDrift = false              // 背景星尘漂浮
    @State private var shockwaveScale1: CGFloat = 0.5 // 冲击波 1
    @State private var shockwaveOpacity1: Double = 0.0
    @State private var shockwaveScale2: CGFloat = 0.5 // 冲击波 2
    @State private var shockwaveOpacity2: Double = 0.0
    @State private var flashOpacity: Double = 0.0     // 全屏辉光脉冲
    @State private var shinePhase = false             // Logo 光泽扫过

    /// 背景星尘粒子（确定性伪随机分布，避免每次启动闪变）
    private let dustParticles: [(x: Double, y: Double, size: Double, delay: Double)] = (0..<14).map { i in
        let f = sin(Double(i) * 12.9898) * 43758.5453
        let g = sin(Double(i) * 78.233) * 12345.6789
        return (abs(f - f.rounded()) , abs(g - g.rounded()), 1.5 + abs(f - f.rounded()) * 2.2, Double(i) * 0.18)
    }

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()

            // 背景星尘：缓慢上浮 + 闪烁
            dustLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 充能完成全屏辉光脉冲
            if flashOpacity > 0.001 {
                RadialGradient(
                    colors: [Color.white.opacity(0.5), accent.opacity(0.18), Color.clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)
            }

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

                    // 充能完成冲击波：两道扩散环
                    shockwaveRing(scale: shockwaveScale1, opacity: shockwaveOpacity1, width: 2.2, color: glow)
                    shockwaveRing(scale: shockwaveScale2, opacity: shockwaveOpacity2, width: 1.4, color: warm)

                    // 轨道电子：3 颗光点沿环旋转（充能期），完成时随轨道隐去
                    if !showLogo {
                        ForEach(0..<3, id: \.self) { idx in
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 5, height: 5)
                                .shadow(color: glow.opacity(0.9), radius: 4)
                                .offset(x: 0, y: -80)
                                .rotationEffect(.degrees(orbitSpinning ? 360 + Double(idx) * 120 : Double(idx) * 120))
                                .animation(
                                    .linear(duration: 2.4).repeatForever(autoreverses: false).delay(Double(idx) * -0.8),
                                    value: orbitSpinning
                                )
                        }
                    }

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
                .overlay(
                    // 光泽扫过：斜向高光条掠过 Logo
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.55), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 26, height: 96)
                        .rotationEffect(.degrees(18))
                        .offset(x: shinePhase ? 70 : -70)
                        .blendMode(.screen)
                        .clipped()
                )
        }
    }

    // MARK: - 华丽特效层

    /// 背景星尘：确定性分布的小光点，缓慢上浮 + 呼吸闪烁
    private var dustLayer: some View {
        ZStack {
            ForEach(0..<dustParticles.count, id: \.self) { idx in
                let p = dustParticles[idx]
                Circle()
                    .fill(glow.opacity(0.55))
                    .frame(width: p.size, height: p.size)
                    .blur(radius: 0.6)
                    .offset(
                        x: (p.x - 0.5) * UIScreen.main.bounds.width,
                        y: (p.y - 0.5) * UIScreen.main.bounds.height + (dustDrift ? -26 : 26)
                    )
                    .opacity(dustDrift ? 0.75 : 0.2)
                    .animation(
                        .easeInOut(duration: 2.8 + p.delay).repeatForever(autoreverses: true).delay(p.delay),
                        value: dustDrift
                    )
            }
        }
    }

    /// 冲击波扩散环
    private func shockwaveRing(scale: CGFloat, opacity: Double, width: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: width, lineCap: .round))
            .frame(width: 150, height: 150)
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: color.opacity(0.5), radius: 6)
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

        // 0. 氛围层：星尘漂浮 + 轨道电子开转
        dustDrift = true
        orbitSpinning = true

        // 1. 电池环充能 0→100%（数字同步滚动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            chargeStarted = true
            boltPulse = true
            withAnimation(.easeInOut(duration: chargeDuration)) {
                chargeProgress = 1.0
            }
        }

        // 2. 充能完成：全屏辉光 + 冲击波 + 电弧向心凝聚 + Logo 亮起 + 光泽扫过
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + chargeDuration + 0.05) {
            NIOBootHaptics.impact(.medium)

            // 全屏辉光脉冲（快闪快消）
            withAnimation(.easeOut(duration: 0.18)) { flashOpacity = 0.85 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.5)) { flashOpacity = 0.0 }
            }

            // 双冲击波扩散
            withAnimation(.easeOut(duration: 0.85)) {
                shockwaveScale1 = 2.3
                shockwaveOpacity1 = 0.8
            }
            withAnimation(.easeOut(duration: 1.05).delay(0.08)) {
                shockwaveScale2 = 2.1
                shockwaveOpacity2 = 0.65
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                withAnimation(.easeIn(duration: 0.3)) { shockwaveOpacity1 = 0.0 }
                withAnimation(.easeIn(duration: 0.35)) { shockwaveOpacity2 = 0.0 }
            }

            withAnimation(.spring(response: 0.46, dampingFraction: 0.68)) {
                showLogo = true
                logoPulse = true
            }

            // Logo 光泽扫过（右入左出一次）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.7)) { shinePhase = true }
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
