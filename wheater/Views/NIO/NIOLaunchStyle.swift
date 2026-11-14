//
//  NIOLaunchStyle.swift
//  wheater
//
//  启动动画系统 v5.3 · 多风格可选
//  · 华丽甜品（默认）：每主题专属粒子秀 + 吉祥物弹性登场（见 NIODessertSplashView）
//  · 能量充能：电池环 0→100% 充能 + 电弧凝聚 Logo
//  · 像素重制：15x15 点阵波次点亮 → 高清 Logo（见 NIOPixelLaunchSplashView）
//  · 极简快启：Logo 淡入 + 细进度线，≤1.1s 直达看板
//  省电动效模式（nio_reduced_fx）开启时强制极简快启。
//

import SwiftUI
import UIKit

// MARK: - 设置键与工具

enum NIOBootSettings {
    static let styleKey = "nio_boot_style"
    static let paceKey = "nio_boot_pace"
    static let hapticsKey = "nio_boot_haptics"
    static let dailyOnceKey = "nio_boot_daily_once"
    static let lastShownKey = "nio_boot_last_shown"

    /// 今日戳格式化器（静态缓存，避免每次调用重复创建）
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 今日戳（用于"每日一次"判定）
    static var todayStamp: String {
        stampFormatter.string(from: Date())
    }
}

// MARK: - 启动动画风格

enum NIOBootStyle: String, CaseIterable, Codable, Identifiable {
    case celebration    // 华丽甜品（默认，每主题专属动效）
    case energyCharge   // 能量充能
    case pixelRemaster  // 像素重制 v5
    case minimalFast    // 极简快启

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .celebration:   return "华丽甜品"
        case .energyCharge:  return "能量充能"
        case .pixelRemaster: return "像素重制"
        case .minimalFast:   return "极简快启"
        }
    }

    var styleDescription: String {
        switch self {
        case .celebration:   return "十主题专属粒子 · 吉祥物登场"
        case .energyCharge:  return "电池环充能 · 星流汇聚"
        case .pixelRemaster: return "点阵点亮 · 复古像素"
        case .minimalFast:   return "一步到位 · 极速直达"
        }
    }

    var icon: String {
        switch self {
        case .celebration:   return "sparkles"
        case .energyCharge:  return "battery.100.bolt"
        case .pixelRemaster: return "square.grid.3x3.middle.filled"
        case .minimalFast:   return "hare.fill"
        }
    }

    /// 当前生效风格（省电动效强制极简）
    static var effective: NIOBootStyle {
        if UserDefaults.standard.bool(forKey: "nio_reduced_fx") { return .minimalFast }
        let raw = UserDefaults.standard.string(forKey: NIOBootSettings.styleKey)
        return NIOBootStyle(rawValue: raw ?? "") ?? .celebration
    }
}

// MARK: - 节奏（标准 / 疾速）

enum NIOBootPace: String, CaseIterable, Codable, Identifiable {
    case standard
    case swift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "标准"
        case .swift:    return "疾速"
        }
    }

    /// 时间缩放系数
    var scale: Double {
        switch self {
        case .standard: return 1.0
        case .swift:    return 0.55
        }
    }

    /// 缩放后的时长
    func t(_ seconds: Double) -> Double { seconds * scale }

    /// 当前生效节奏
    static var current: NIOBootPace {
        NIOBootPace(rawValue: UserDefaults.standard.string(forKey: NIOBootSettings.paceKey) ?? "") ?? .standard
    }
}

// MARK: - 触感反馈

@MainActor
enum NIOBootHaptics {
    /// 尊重用户开关的触感反馈（默认开启）
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let enabled = UserDefaults.standard.object(forKey: NIOBootSettings.hapticsKey) as? Bool ?? true
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - 主题开屏人设（三套风格共享）

struct NIOBootPersona {
    let topLabel: String
    let subtitle: String
    let statusEmoji: String
    let glowStrength: Double
    let subtitleMono: Bool

    static func forTheme(_ style: AnimeThemeStyle) -> NIOBootPersona {
        switch style {
        case .strawberryShake:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "草莓奶昔已摇匀，兔兔上线中…", statusEmoji: "🍓", glowStrength: 1.0, subtitleMono: false)
        case .taroBoba:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "香芋啵啵加料中，爱车吸一口就醒…", statusEmoji: "🧋", glowStrength: 1.0, subtitleMono: false)
        case .cloudGummy:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "云朵软糖充电桩已就绪…", statusEmoji: "☁️", glowStrength: 1.0, subtitleMono: false)
        case .peachOolong:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "蜜桃乌龙回温中，元气蓄满…", statusEmoji: "🍑", glowStrength: 1.0, subtitleMono: false)
        case .mintMilk:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "薄荷奶绿注入中，爱车苏醒…", statusEmoji: "🌿", glowStrength: 1.0, subtitleMono: false)
        case .lemonSoda:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "柠檬汽水冒泡中，电量满格…", statusEmoji: "🍋", glowStrength: 1.0, subtitleMono: false)
        case .strawberryNocturne:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "草莓夜曲奏响中，兔兔夜巡上线…", statusEmoji: "🌙", glowStrength: 1.0, subtitleMono: false)
        case .taroPlanet:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "芋泥星球信号锁定，爱车归航…", statusEmoji: "🪐", glowStrength: 1.0, subtitleMono: false)
        case .nebulaMarshmallow:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "星云棉花糖展开中，甜梦续航…", statusEmoji: "🌌", glowStrength: 1.0, subtitleMono: false)
        case .caramelPudding:
            return NIOBootPersona(topLabel: "YUMIKOTOYS", subtitle: "焦糖布丁凝固中，温柔暖夜上线…", statusEmoji: "🍮", glowStrength: 1.0, subtitleMono: false)
        }
    }
}

// MARK: - 共享跳过按钮（能量 / 极简风格用）

struct NIOBootSkipOverlay: View {
    @Binding var isFinished: Bool
    let visible: Bool
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var token: AnimeThemeToken { themeService.currentToken }
    private var text: Color { Color(hex: token.textPrimary) }
    private var accent: Color { Color(hex: token.accentColor) }
    private var isDark: Bool { token.isDark }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.28)) { isFinished = true }
                }) {
                    HStack(spacing: 4) {
                        Text("进入看板")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
                    .foregroundStyle(text.opacity(0.9))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.4), lineWidth: 0.8))
                }
            }
            .padding(.top, 50)
            .padding(.trailing, 20)
            Spacer()
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.3), value: visible)
    }
}

// MARK: - 启动动画路由器

/// 按设置路由到对应风格的开屏动画，含"每日一次"闸门。
struct NIOLaunchSplashView: View {
    @Binding var isFinished: Bool
    /// 预览模式：跳过每日一次闸门
    var bypassGate = false

    @AppStorage(NIOBootSettings.styleKey) private var styleRaw = NIOBootStyle.energyCharge.rawValue
    @AppStorage("nio_reduced_fx") private var reducedFx = false
    @AppStorage(NIOBootSettings.dailyOnceKey) private var dailyOnce = false
    @AppStorage(NIOBootSettings.lastShownKey) private var lastShown = ""
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var effectiveStyle: NIOBootStyle {
        if reducedFx { return .minimalFast }
        return NIOBootStyle(rawValue: styleRaw) ?? .energyCharge
    }

    private var gateAllowsShow: Bool {
        guard !bypassGate, dailyOnce else { return true }
        return lastShown != NIOBootSettings.todayStamp
    }

    var body: some View {
        ZStack {
            Color(hex: themeService.currentToken.backgroundPrimary)
                .ignoresSafeArea()

            if gateAllowsShow {
                content
                    .transition(.opacity)
            }
        }
        .onAppear {
            if gateAllowsShow {
                UserDefaults.standard.set(NIOBootSettings.todayStamp, forKey: NIOBootSettings.lastShownKey)
            } else {
                isFinished = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch effectiveStyle {
        case .celebration:
            NIODessertSplashView(isFinished: $isFinished)
        case .energyCharge:
            NIOEnergyBootView(isFinished: $isFinished)
        case .pixelRemaster:
            NIOPixelLaunchSplashView(isFinished: $isFinished)
        case .minimalFast:
            NIOMinimalBootView(isFinished: $isFinished)
        }
    }
}

// MARK: - 可取消的延时任务集合

/// 启动动画序列的延时调度助手：所有 `DispatchQueue.main.asyncAfter` 统一经此排队，
/// 视图消失（用户跳过开屏 / 预览结束）时整体 cancel，避免向已脱离层级的 @State 脏写
final class NIOScheduledWork: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DispatchWorkItem] = []

    func schedule(after seconds: TimeInterval, _ body: @escaping () -> Void) {
        let work = DispatchWorkItem(block: body)
        lock.lock()
        items.append(work)
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// 取消此前所有未触发任务后再调度（防连点堆叠定时器）
    func scheduleReplacing(after seconds: TimeInterval, _ body: @escaping () -> Void) {
        cancelAll()
        schedule(after: seconds, body)
    }

    func cancelAll() {
        lock.lock()
        let all = items
        items.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }
}

// MARK: - 华丽甜品开屏（v5.3 · 每主题专属动效）
// 主题切换即换一场"甜品秀"：粒子形态（表情雨 / 珍珠升流 / 轨道星尘 / 星光闪烁）、
// 运动方向、氛围光斑漂移全部由主题令牌驱动，吉祥物弹性登场 + 涟漪光环 + 触感。

struct NIODessertSplashView: View {
    @Binding var isFinished: Bool
    @ObservedObject private var themeService = AnimeThemeService.shared
    @State private var mascotScale: CGFloat = 0.25
    @State private var mascotOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 14
    @State private var subtitleOpacity: Double = 0
    @State private var exitOpacity: Double = 1
    @State private var ringProgress: [Double] = [0, 0, 0]
    @State private var skipVisible = false
    private let scheduledWork = NIOScheduledWork()

    private var style: AnimeThemeStyle { themeService.currentStyle }
    private var token: AnimeThemeToken { themeService.currentToken }
    private var persona: NIOBootPersona { NIOBootPersona.forTheme(style) }
    private var pace: NIOBootPace { NIOBootPace.current }

    var body: some View {
        ZStack {
            backdrop
            TimelineView(.animation) { timeline in
                ZStack {
                    particleField(date: timeline.date)
                    orbitLayer(date: timeline.date)
                }
            }
            VStack(spacing: 18) {
                Spacer()
                mascot
                VStack(spacing: 6) {
                    Text("YUMIKOTOYS")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: token.gradientStart), Color(hex: token.gradientEnd)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Text(persona.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: token.textSecondary))
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)
                Spacer()
                Text(persona.statusEmoji)
                    .font(.system(size: 22))
                    .opacity(subtitleOpacity)
                    .padding(.bottom, 34)
            }
            NIOBootSkipOverlay(isFinished: $isFinished, visible: skipVisible)
        }
        .background(Color(hex: token.backgroundPrimary).ignoresSafeArea())
        .opacity(exitOpacity)
        .onAppear(perform: runSequence)
        .onDisappear { scheduledWork.cancelAll() }
    }

    // MARK: 主题专属动效配置

    private enum ParticleMotion { case falling, rising, orbit, twinkle }

    private struct ParticleConfig {
        let glyphs: [String]?      // 表情粒子（雨 / 升流）
        let dotColors: [Color]?    // 色点粒子（珍珠 / 气泡 / 星尘）
        let motion: ParticleMotion
        let sway: CGFloat          // 横向摆幅
        let speed: Double          // 粒子时长（秒，越大越慢）
    }

    private var particles: ParticleConfig {
        let accent = Color(hex: token.accentColor)
        let glow = Color(hex: token.glowColor)
        let warm = Color(hex: token.warmAccent)
        switch style {
        case .strawberryShake:    return ParticleConfig(glyphs: ["🍓", "🥛", "🌸", "🍒"], dotColors: nil, motion: .falling, sway: 22, speed: 3.6)
        case .taroBoba:           return ParticleConfig(glyphs: nil, dotColors: [Color(hex: "A97A55"), accent, glow], motion: .rising, sway: 10, speed: 4.2)
        case .cloudGummy:         return ParticleConfig(glyphs: ["☁️", "🍬", "🫧", "🍭"], dotColors: nil, motion: .falling, sway: 30, speed: 5.0)
        case .peachOolong:        return ParticleConfig(glyphs: nil, dotColors: [accent, glow, warm], motion: .rising, sway: 14, speed: 3.8)
        case .mintMilk:           return ParticleConfig(glyphs: ["🌿", "🍃", "💧"], dotColors: nil, motion: .falling, sway: 34, speed: 4.4)
        case .lemonSoda:          return ParticleConfig(glyphs: nil, dotColors: [accent, glow, warm], motion: .rising, sway: 8, speed: 3.0)
        case .strawberryNocturne: return ParticleConfig(glyphs: ["🌙", "✨", "🍓", "⭐️"], dotColors: nil, motion: .falling, sway: 40, speed: 4.8)
        case .taroPlanet:         return ParticleConfig(glyphs: nil, dotColors: [accent, glow, Color(hex: "8FB8F5")], motion: .orbit, sway: 0, speed: 9.0)
        case .nebulaMarshmallow:  return ParticleConfig(glyphs: nil, dotColors: [accent, glow, warm], motion: .twinkle, sway: 0, speed: 2.4)
        case .caramelPudding:     return ParticleConfig(glyphs: ["🍮", "🍯", "✨"], dotColors: nil, motion: .falling, sway: 18, speed: 5.4)
        }
    }

    // MARK: 氛围光斑（主题三色慢漂移）

    private var backdrop: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                blob(Color(hex: token.gradientStart).opacity(0.20),
                     center: CGPoint(x: 0.24 + 0.05 * sin(t * 0.35), y: 0.22 + 0.04 * cos(t * 0.28)),
                     radius: 230)
                blob(Color(hex: token.gradientEnd).opacity(0.16),
                     center: CGPoint(x: 0.82 + 0.05 * cos(t * 0.30), y: 0.66 + 0.04 * sin(t * 0.33)),
                     radius: 260)
                blob(Color(hex: token.warmAccent).opacity(0.10),
                     center: CGPoint(x: 0.55 + 0.06 * sin(t * 0.26), y: 0.92 + 0.03 * cos(t * 0.31)),
                     radius: 200)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, center: CGPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: .center, startRadius: radius * 0.12, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: center.x * UIScreen.main.bounds.width,
                      y: center.y * UIScreen.main.bounds.height)
    }

    // MARK: 粒子场（TimelineView 驱动，确定性相位，无逐粒子状态）

    @ViewBuilder
    private func particleField(date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let config = particles
        let screen = UIScreen.main.bounds.size
        if config.motion == .twinkle {
            // 星光闪烁：固定散布 + 呼吸明灭
            ForEach(0..<22, id: \.self) { i in
                let seed = pseudoRandom(i)
                let alpha = 0.25 + 0.75 * abs(sin(t / (config.speed * (0.6 + seed.2)) + Double(i)))
                if let colors = config.dotColors {
                    Circle()
                        .fill(colors[i % colors.count].opacity(alpha))
                        .frame(width: CGFloat(2.5 + 2.5 * seed.2), height: CGFloat(2.5 + 2.5 * seed.2))
                        .position(x: seed.0 * screen.width, y: seed.1 * screen.height)
                }
            }
        } else {
            ForEach(0..<16, id: \.self) { i in
                let m = flowMetrics(i: i, t: t, config: config, screen: screen)
                Group {
                    if let glyphs = config.glyphs {
                        Text(glyphs[i % glyphs.count])
                            .font(.system(size: CGFloat(14 + 10 * m.seed2)))
                            .rotationEffect(.degrees(config.motion == .falling ? sin(t + Double(i)) * 14 : 0))
                    } else if let colors = config.dotColors {
                        let size = CGFloat(6 + 8 * m.seed2)
                        Circle()
                            .fill(colors[i % colors.count].opacity(0.75))
                            .frame(width: size, height: size)
                            .shadow(color: colors[i % colors.count].opacity(0.6), radius: 3)
                    }
                }
                .opacity(m.alpha)
                .position(x: m.x, y: m.y)
            }
        }
    }

    /// 流式粒子（雨 / 升流）的确定性相位坐标：独立于 ViewBuilder 计算，避免赋值语句被构建器解析
    private func flowMetrics(i: Int, t: Double, config: ParticleConfig, screen: CGSize)
        -> (x: CGFloat, y: CGFloat, alpha: Double, seed2: Double) {
        let seed = pseudoRandom(i)
        let phase = (t / (config.speed * (0.75 + 0.5 * seed.2)) + seed.2 * 7.3)
            .truncatingRemainder(dividingBy: 1)
        let x = seed.0 * screen.width + config.sway * sin(t * 0.9 + Double(i) * 1.7)
        switch config.motion {
        case .falling:
            return (x, -40 + (screen.height + 80) * CGFloat(phase),
                    min(phase / 0.12, 1) * min((1 - phase) / 0.12, 1), seed.2)
        case .rising:
            return (x, screen.height + 40 - (screen.height + 80) * CGFloat(phase),
                    min(phase / 0.12, 1) * min((1 - phase) / 0.12, 1), seed.2)
        default:
            return (x, seed.1 * screen.height, 1, seed.2)
        }
    }

    /// 轨道星尘（芋泥星球 / 星云系）：绕中心旋转的亮点环
    @ViewBuilder
    private func orbitLayer(date: Date) -> some View {
        if particles.motion == .orbit {
            let t = date.timeIntervalSinceReferenceDate
            let screen = UIScreen.main.bounds.size
            ForEach(0..<10, id: \.self) { i in
                let seed = pseudoRandom(i + 40)
                let angle = t / particles.speed * (1.2 + 0.6 * seed.2) + Double(i) * .pi * 2 / 10
                let r = 90 + 70 * seed.0
                if let colors = particles.dotColors {
                    Circle()
                        .fill(colors[i % colors.count].opacity(0.8))
                        .frame(width: 4 + 3 * seed.2, height: 4 + 3 * seed.2)
                        .position(x: screen.width / 2 + CGFloat(cos(angle)) * r,
                                  y: screen.height * 0.42 + CGFloat(sin(angle)) * r * 0.55)
                }
            }
        }
    }

    /// 稳定伪随机（0 ~ 1 三元组：x / y / size 相位）
    private func pseudoRandom(_ i: Int) -> (CGFloat, CGFloat, Double) {
        var state = UInt64(i) &+ 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFF_FFFF) / Double(0xFFFF_FFFF)
        }
        return (CGFloat(next()), CGFloat(next()), next())
    }

    // MARK: 吉祥物与编排

    private var mascot: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .stroke(Color(hex: idx % 2 == 0 ? token.gradientStart : token.gradientEnd).opacity(0.55 * (1 - ringProgress[idx])), lineWidth: 1.6)
                    .frame(width: 130, height: 130)
                    .scaleEffect(0.55 + ringProgress[idx] * 1.15)
            }
            Text(persona.statusEmoji)
                .font(.system(size: 58))
                .shadow(color: Color(hex: token.accentColor).opacity(0.55), radius: 14)
        }
        .scaleEffect(mascotScale)
        .opacity(mascotOpacity)
    }

    private func runSequence() {
        let t = pace.t
        scheduledWork.schedule(after: 0) {
            NIOBootHaptics.impact(.medium)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                mascotScale = 1.0
                mascotOpacity = 1
            }
        }
        scheduledWork.schedule(after: t(0.35)) {
            withAnimation(.easeOut(duration: 0.45)) {
                titleOpacity = 1
                titleOffset = 0
            }
        }
        scheduledWork.schedule(after: t(0.55)) {
            withAnimation(.easeOut(duration: 0.5)) { subtitleOpacity = 1 }
        }
        // 三圈涟漪：错峰扩散
        for idx in 0..<3 {
            scheduledWork.schedule(after: t(0.4 + Double(idx) * 0.2)) {
                withAnimation(.easeOut(duration: 0.95)) { ringProgress[idx] = 1 }
            }
        }
        scheduledWork.schedule(after: t(0.8)) {
            withAnimation(.easeIn(duration: 0.25)) { skipVisible = true }
        }
        scheduledWork.schedule(after: t(2.1)) {
            withAnimation(.easeInOut(duration: 0.35)) { exitOpacity = 0 }
        }
        scheduledWork.schedule(after: t(2.5)) {
            isFinished = true
        }
    }
}
