//
//  NIOPixelLaunchSplashView.swift
//  wheater
//
//  蔚来像素风启动动画 · 主题化 v5.3
//  每套主题拥有专属开屏人设（配色 / 像素色板 / 文案 / 徽章 / 辉光强度）：
//  · 草莓奶昔 🍓 / 香芋啵啵 🧋 / 云朵软糖 ☁️ / 蜜桃乌龙 🍑（奶甜浅色系）
//  · 薄荷奶绿 🌿 / 柠檬汽水 🍋（清新浅色系）
//  · 草莓夜曲 🌙 / 芋泥星球 🪐 / 星云棉花糖 🌌 / 焦糖布丁 🍮（星夜深色系）
//  省电动效模式下自动跳过逐像素点亮并缩短停留。
//

import SwiftUI

struct NIOPixelLaunchSplashView: View {
    @Binding var isFinished: Bool
    @ObservedObject private var themeService = AnimeThemeService.shared
    @AppStorage("nio_reduced_fx") private var reducedFx = false

    // 主题令牌快捷取色
    private var token: AnimeThemeToken { themeService.currentToken }
    private var text: Color { Color(hex: token.textPrimary) }
    private var textSoft: Color { Color(hex: token.textSecondary) }
    private var accent: Color { Color(hex: token.accentColor) }
    private var glow: Color { Color(hex: token.glowColor) }
    private var warm: Color { Color(hex: token.warmAccent) }
    private var gradientStart: Color { Color(hex: token.gradientStart) }
    private var gradientEnd: Color { Color(hex: token.gradientEnd) }
    private var isDark: Bool { token.isDark }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "5.0.0"
    }

    // 动画状态引擎
    @State private var activePixelIndex = 0
    @State private var showHDLogo = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var rippleScale1: CGFloat = 0.6
    @State private var rippleOpacity1: Double = 0.0
    @State private var rippleScale2: CGFloat = 0.4
    @State private var rippleOpacity2: Double = 0.0
    @State private var logoPulse = false
    @State private var auraRotation: Double = 0.0
    @State private var badgeFlash: Double = 0.0  // 徽章点亮闪光 0→1→0
    @State private var pulseDots = false
    @State private var scheduledWork = NIOScheduledWork()

    // 15x15 矩阵中代表蔚来 Logo 的像素坐标 (row, col)
    // 蔚来标志由两部分组成：上方穹顶圆弧 (Top Arc) + 下方延伸之路 (Bottom Chevron)
    private let nioPixelCoords: [(row: Int, col: Int, section: Int)] = [
        // MARK: 上方圆弧 (Top Arc) - section 0
        (row: 2, col: 6, section: 0), (row: 2, col: 7, section: 0), (row: 2, col: 8, section: 0),
        (row: 3, col: 4, section: 0), (row: 3, col: 5, section: 0), (row: 3, col: 9, section: 0), (row: 3, col: 10, section: 0),
        (row: 4, col: 3, section: 0), (row: 4, col: 4, section: 0), (row: 4, col: 10, section: 0), (row: 4, col: 11, section: 0),
        (row: 5, col: 2, section: 0), (row: 5, col: 3, section: 0), (row: 5, col: 11, section: 0), (row: 5, col: 12, section: 0),
        (row: 6, col: 2, section: 0), (row: 6, col: 3, section: 0), (row: 6, col: 11, section: 0), (row: 6, col: 12, section: 0),
        (row: 7, col: 2, section: 0), (row: 7, col: 12, section: 0),

        // MARK: 下方延伸之路 (Bottom Chevron / Inverted V) - section 1
        (row: 8, col: 7, section: 1),
        (row: 9, col: 6, section: 1), (row: 9, col: 7, section: 1), (row: 9, col: 8, section: 1),
        (row: 10, col: 5, section: 1), (row: 10, col: 6, section: 1), (row: 10, col: 8, section: 1), (row: 10, col: 9, section: 1),
        (row: 11, col: 4, section: 1), (row: 11, col: 5, section: 1), (row: 11, col: 9, section: 1), (row: 11, col: 10, section: 1),
        (row: 12, col: 3, section: 1), (row: 12, col: 4, section: 1), (row: 12, col: 10, section: 1), (row: 12, col: 11, section: 1),
        (row: 13, col: 2, section: 1), (row: 13, col: 3, section: 1), (row: 13, col: 11, section: 1), (row: 13, col: 12, section: 1)
    ]

    var body: some View {
        ZStack {
            // 主题化启动背景（无缝过渡，杜绝黑屏）
            splashBackground
                .ignoresSafeArea()

            // 右上角优雅跳过按钮
            if showHDLogo {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                isFinished = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("进入看板")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(skipButtonBackground)
                            .foregroundStyle(text.opacity(0.9))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: 0.8))
                        }
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .zIndex(10)
            }

            VStack(spacing: 28) {
                Spacer()

                // MARK: - 像素 / 矢量动画矩阵容器
                ZStack {
                    // 背景旋转星环与氛围光晕
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.35 * glowStrength), glow.opacity(0.15 * glowStrength), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(logoPulse ? 1.08 : 0.95)

                    // 第一道扩散脉冲光环
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [accent.opacity(0.85), glow.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(rippleScale1)
                        .opacity(rippleOpacity1)

                    // 第二道扩散脉冲光环 (层次感)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [warm.opacity(0.7), accent.opacity(0.3)],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(rippleScale2)
                        .opacity(rippleOpacity2)

                    // 1. 像素矩阵网格 (15x15 动态点阵)
                    if !showHDLogo {
                        pixelGridView
                            .frame(width: 135, height: 135)
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }

                    // 2. 凝聚成高清发光蔚来 Logo 与主题徽章光圈
                    if showHDLogo {
                        hdLogoView
                            .transition(.scale(scale: 0.65).combined(with: .opacity))
                    }
                }
                .frame(width: 180, height: 180)

                // MARK: - 标题与状态文本
                VStack(spacing: 8) {
                    if showTitle {
                        VStack(spacing: 4) {
                            Text(topLabel)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .tracking(4)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [glow, warm],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            Text("蔚来 · 兔可可")
                                .font(.system(size: 27, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [text, accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: accent.opacity(glowStrength * 0.6), radius: glowStrength * 10)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if showSubtitle {
                        HStack(spacing: 6) {
                            Text(statusEmoji)
                                .font(.system(size: 13))
                            Text(subtitleText)
                                .font(.system(size: 12, weight: .bold, design: subtitleMono ? .monospaced : .rounded))
                                .foregroundStyle(textSoft.opacity(0.95))

                            // 呼吸三点指示器 (带动态交错脉冲动画)
                            HStack(spacing: 3.5) {
                                Circle().fill(glow).frame(width: 4, height: 4)
                                    .scaleEffect(pulseDots ? 1.3 : 0.8)
                                    .opacity(pulseDots ? 1.0 : 0.5)
                                Circle().fill(accent).frame(width: 4, height: 4)
                                    .scaleEffect(pulseDots ? 0.8 : 1.3)
                                    .opacity(pulseDots ? 0.5 : 1.0)
                                Circle().fill(warm).frame(width: 4, height: 4)
                                    .scaleEffect(pulseDots ? 1.2 : 0.9)
                                    .opacity(pulseDots ? 1.0 : 0.6)
                            }
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulseDots)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(chipBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 0.8))
                        .shadow(color: accent.opacity(0.15 * glowStrength), radius: 6)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .frame(height: 85)

                Spacer()

                // 底部轻量版本标
                Text("v\(appVersion) · NIO Space • Designed with 🐰兔可可 🥕")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(text.opacity(0.4))
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            runLaunchSequence()
        }
        .onDisappear { scheduledWork.cancelAll() }
    }

    // MARK: - 主题人设（每个主题一套开屏个性）

    /// 像素色板（4 色循环，全部由主题令牌驱动）
    private var pixelPalette: [Color] {
        [gradientStart, gradientEnd, warm, glow]
    }

    /// 顶部小标文案
    private var topLabel: String {
        "YUMIKOTOYS"
    }

    /// 状态副标文案
    private var subtitleText: String {
        switch themeService.currentStyle {
        case .strawberryShake:    return "草莓奶昔已摇匀，兔兔上线中…"
        case .taroBoba:           return "香芋啵啵加料中，爱车吸一口就醒…"
        case .cloudGummy:         return "云朵软糖充电桩已就绪…"
        case .peachOolong:        return "蜜桃乌龙回温中，元气蓄满…"
        case .mintMilk:           return "薄荷奶绿注入中，爱车苏醒…"
        case .lemonSoda:          return "柠檬汽水冒泡中，电量满格…"
        case .strawberryNocturne: return "草莓夜曲奏响中，兔兔夜巡上线…"
        case .taroPlanet:         return "芋泥星球信号锁定，爱车归航…"
        case .nebulaMarshmallow:  return "星云棉花糖展开中，甜梦续航…"
        case .caramelPudding:     return "焦糖布丁凝固中，温柔暖夜上线…"
        }
    }

    /// 状态表情徽章
    private var statusEmoji: String {
        switch themeService.currentStyle {
        case .strawberryShake:    return "🍓"
        case .taroBoba:           return "🧋"
        case .cloudGummy:         return "☁️"
        case .peachOolong:        return "🍑"
        case .mintMilk:           return "🌿"
        case .lemonSoda:          return "🍋"
        case .strawberryNocturne: return "🌙"
        case .taroPlanet:         return "🪐"
        case .nebulaMarshmallow:  return "🌌"
        case .caramelPudding:     return "🍮"
        }
    }

    /// 辉光强度（甜品系全主题统一柔和辉光）
    private var glowStrength: Double {
        1.0
    }

    /// 副标是否使用等宽字体（甜品系不使用终端感）
    private var subtitleMono: Bool {
        false
    }

    // MARK: - 15x15 像素点阵视图

    private var pixelGridView: some View {
        let gridSize = 15
        let cellSize: CGFloat = 7.5
        let spacing: CGFloat = 1.5
        let palette = pixelPalette

        return VStack(spacing: spacing) {
            ForEach(0..<gridSize, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(0..<gridSize, id: \.self) { c in
                        let activeIdx = nioPixelCoords.firstIndex { $0.row == r && $0.col == c }

                        if let idx = activeIdx, idx <= activePixelIndex {
                            let color = palette[idx % palette.count]

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(color)
                                .frame(width: cellSize, height: cellSize)
                                .shadow(color: color.opacity(0.8 * glowStrength), radius: glowStrength > 0 ? 3 : 0)
                                .scaleEffect(idx == activePixelIndex ? 1.4 : 1.0)
                        } else {
                            // 未点亮的暗色像素底点
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.05))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 高清 Logo 聚光展示视图

    private var hdLogoView: some View {
        ZStack {
            // 霓虹光芒底盘
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.5 * glowStrength), gradientEnd.opacity(0.2 * glowStrength), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // 双层外环
            Circle()
                .stroke(
                    ringGradient,
                    lineWidth: isMinimalPersona ? 1.5 : 2.5
                )
                .frame(width: 100, height: 100)
                .shadow(color: accent.opacity(0.7 * glowStrength), radius: glowStrength > 0 ? 10 : 0)
                .scaleEffect(logoPulse ? 1.05 : 0.98)
                .animation(glowStrength > 0 ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil, value: logoPulse)

            // 内层玻璃磨砂
            Circle()
                .fill(isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.65))
                .frame(width: 88, height: 88)

            // 蔚来品牌 Logo
            Image("NIO_brand")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 4)

            // 主题专属徽章（所有主题都有，点亮时闪光）
            logoBadgeView
        }
    }

    /// 高清 Logo 角标：极简主题用像素点阵绘制徽章，其余用萌系 emoji
    @ViewBuilder
    private var logoBadgeView: some View {
        Group {
            switch logoBadge {
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: 20))
            case .pixelCarrot:
                pixelBadgeView(pixels: Self.carrotPixels)
            case .pixelBolt:
                pixelBadgeView(pixels: Self.boltPixels)
            case .none:
                EmptyView()
            }
        }
        .offset(x: 36, y: -34)
        .shadow(color: accent.opacity(0.6 * glowStrength + 0.55 * badgeFlash), radius: 4 + 9 * badgeFlash)
        .scaleEffect(1.0 + 0.28 * badgeFlash)
    }

    private enum LogoBadge {
        case emoji(String)
        case pixelCarrot
        case pixelBolt
    }

    private var logoBadge: LogoBadge? {
        switch themeService.currentStyle {
        case .strawberryShake:    return .emoji("🐰")
        case .taroBoba:           return .emoji("🧋")
        case .cloudGummy:         return .emoji("☁️")
        case .peachOolong:        return .emoji("🍑")
        case .mintMilk:           return .emoji("🌿")
        case .lemonSoda:          return .emoji("🍋")
        case .strawberryNocturne: return .emoji("🌙")
        case .taroPlanet:         return .emoji("🪐")
        case .nebulaMarshmallow:  return .emoji("🌌")
        case .caramelPudding:     return .emoji("🍮")
        }
    }

    private var isMinimalPersona: Bool {
        false
    }

    // 像素徽章点阵（tone: 0 = 主强调色, 1 = 渐变次色）

    /// 像素胡萝卜 7x5（叶 + 渐细根身）· 云石膏
    private static let carrotPixels: [(row: Int, col: Int, tone: Int)] = [
        (row: 0, col: 1, tone: 1), (row: 0, col: 3, tone: 1),
        (row: 1, col: 1, tone: 1), (row: 1, col: 2, tone: 1), (row: 1, col: 3, tone: 1),
        (row: 2, col: 2, tone: 0), (row: 2, col: 3, tone: 0),
        (row: 3, col: 2, tone: 0), (row: 3, col: 3, tone: 0),
        (row: 4, col: 2, tone: 0),
        (row: 5, col: 2, tone: 0),
        (row: 6, col: 2, tone: 0)
    ]

    /// 像素闪电 7x4 · 曜石灰
    private static let boltPixels: [(row: Int, col: Int, tone: Int)] = [
        (row: 0, col: 2, tone: 0), (row: 0, col: 3, tone: 0),
        (row: 1, col: 2, tone: 0),
        (row: 2, col: 1, tone: 0), (row: 2, col: 2, tone: 0),
        (row: 3, col: 1, tone: 0), (row: 3, col: 2, tone: 0), (row: 3, col: 3, tone: 0),
        (row: 4, col: 2, tone: 0), (row: 4, col: 3, tone: 0),
        (row: 5, col: 1, tone: 0), (row: 5, col: 2, tone: 0),
        (row: 6, col: 0, tone: 0), (row: 6, col: 1, tone: 0)
    ]

    /// 迷你像素点阵徽章（与开屏像素矩阵同风格）
    private func pixelBadgeView(pixels: [(row: Int, col: Int, tone: Int)], cellSize: CGFloat = 4.5) -> some View {
        let rows = (pixels.map { $0.row }.max() ?? 0) + 1
        let cols = (pixels.map { $0.col }.max() ?? 0) + 1
        let toneColors = [accent, Color(hex: token.gradientEnd)]

        return VStack(spacing: 0.8) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0.8) {
                    ForEach(0..<cols, id: \.self) { c in
                        let hit = pixels.first { $0.row == r && $0.col == c }
                        RoundedRectangle(cornerRadius: 1)
                            .fill(hit.map { toneColors[$0.tone] } ?? .clear)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private var ringGradient: LinearGradient {
        if isMinimalPersona {
            return LinearGradient(colors: [accent, accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [accent, glow, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 动画时序控制器（省电模式自动缩短 / 节奏跟随设置）

    /// 节奏缩放（标准 / 疾速）
    private var pace: NIOBootPace { NIOBootPace.current }

    private func runLaunchSequence() {
        // 省电动效模式：跳过逐像素流水，直接亮 Logo，快速进看板
        if reducedFx {
            withAnimation(.easeOut(duration: 0.2)) {
                activePixelIndex = nioPixelCoords.count - 1
            }
            scheduledWork.schedule(after: 0.25) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    showHDLogo = true
                    showTitle = true
                    showSubtitle = true
                    pulseDots = true
                }
                withAnimation(.easeOut(duration: 0.15)) { badgeFlash = 1.0 }
                scheduledWork.schedule(after: 0.4) {
                    withAnimation(.easeOut(duration: 0.4)) { badgeFlash = 0.0 }
                }
            }
            scheduledWork.schedule(after: 1.4) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFinished = true
                }
            }
            return
        }

        // 1. 流水律动点亮像素矩阵（分 10 组波次顺滑绽放，0.0s ~ 0.85s）
        let totalPixels = nioPixelCoords.count
        let waveCount = 10
        let waveInterval = pace.t(0.82) / Double(waveCount)

        for w in 0..<waveCount {
            let targetIdx = min(totalPixels - 1, Int(Double(w + 1) * Double(totalPixels) / Double(waveCount)))
            scheduledWork.schedule(after: Double(w) * waveInterval) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    activePixelIndex = targetIdx
                }
            }
        }

        // 2. 像素聚合成高清 Logo 与双层脉冲光环爆炸 (约 0.9s)
        scheduledWork.schedule(after: pace.t(0.90)) {
            NIOBootHaptics.impact(.medium)

            withAnimation(.spring(response: 0.48, dampingFraction: 0.68)) {
                showHDLogo = true
                logoPulse = true
                pulseDots = true
                rippleScale1 = 2.1
                rippleOpacity1 = 0.92
                rippleScale2 = 1.65
                rippleOpacity2 = 0.75
            }

            // 徽章点亮闪光（点亮瞬间放大 + 辉光，随后回落）
            withAnimation(.easeOut(duration: 0.18)) { badgeFlash = 1.0 }
            scheduledWork.schedule(after: 0.5) {
                withAnimation(.easeOut(duration: 0.5)) { badgeFlash = 0.0 }
            }

            withAnimation(.easeOut(duration: 0.75)) {
                rippleOpacity1 = 0.0
            }
            withAnimation(.easeOut(duration: 0.95)) {
                rippleOpacity2 = 0.0
            }
        }

        // 3. 标题浮现 (约 1.25s)
        scheduledWork.schedule(after: pace.t(1.25)) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                showTitle = true
            }
        }

        // 4. 副标与连结提示浮现 (约 1.5s)
        scheduledWork.schedule(after: pace.t(1.50)) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                showSubtitle = true
            }
        }

        // 5. 动画静置停留与平滑过渡进入主看板 (约 2.9s)
        scheduledWork.schedule(after: pace.t(2.9)) {
            withAnimation(.easeInOut(duration: 0.38)) {
                isFinished = true
            }
        }
    }

    // MARK: - 主题化背景与小组件

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

    private var skipButtonBackground: Color {
        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.05)
    }

    private var chipBackground: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }
}
