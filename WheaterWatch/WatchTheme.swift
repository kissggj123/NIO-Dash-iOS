//
//  WatchTheme.swift
//  YumikoToysRRWatch
//
//  watch 端轻量主题色表（与 iPhone 端 AnimeThemeToken 十套预设保持同色值）。
//  原令牌文件依赖 ActivityKit 无法在 watchOS 编译，此处按 themeRaw 解析取色；
//  未知名回退默认「草莓奶昔」。
//

import SwiftUI

struct WatchTheme {
    let accent: Color
    let glow: Color
    let gradientStart: Color
    let gradientEnd: Color
    let background: Color
    let text: Color
    let isDark: Bool

    private static let presets: [String: (a: String, g: String, s: String, e: String, bg: String, t: String, dark: Bool)] = [
        "strawberryShake":    ("FF6FA5", "B9A6FF", "FF8FBB", "A78BFF", "FFF4F1", "4A2E3A", false),
        "taroBoba":           ("9F6FE8", "FF9ED4", "B18CF7", "FF9ED4", "F4F0FB", "3A2E4D", false),
        "cloudGummy":         ("5FA8FF", "FFA9D4", "7DB9FF", "FFAFD8", "F0F6FF", "2E3D52", false),
        "peachOolong":        ("FF8A5C", "FFC25E", "FF9A66", "FFB84D", "FFF6EC", "4D3526", false),
        "mintMilk":           ("2FB37C", "6FD8BE", "52C98E", "9FE8B8", "EFFAF2", "263D2F", false),
        "lemonSoda":          ("F5A623", "FFD34D", "FFCC4D", "FFE38A", "FFFCEB", "4A3A1E", false),
        "strawberryNocturne": ("FF7FA8", "D9A0FF", "FF7FA8", "C77DFF", "1F1219", "FFF3F7", true),
        "taroPlanet":         ("B577FF", "F08AD8", "B577FF", "F08AD8", "191227", "F8F2FF", true),
        "nebulaMarshmallow":  ("6FB0FF", "C79BFF", "6FB0FF", "C79BFF", "121828", "F5F9FF", true),
        "caramelPudding":     ("FFB05C", "FFD493", "FFB05C", "E08B4A", "1E1712", "FFF6EA", true),
    ]

    static func theme(for raw: String?) -> WatchTheme {
        let p = presets[raw ?? ""] ?? presets["strawberryShake"]!
        return WatchTheme(
            accent: Color(hex: p.a), glow: Color(hex: p.g),
            gradientStart: Color(hex: p.s), gradientEnd: Color(hex: p.e),
            background: Color(hex: p.bg), text: Color(hex: p.t), isDark: p.dark
        )
    }

    /// 极光三色级联渐变（与 iPhone 端 NIOThemePaint.auroraGradient 同款）
    var auroraGradient: LinearGradient {
        LinearGradient(colors: [gradientStart, glow, gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: String) {
        let value = Int(hex.prefix(6), radix: 16) ?? 0xFF7FA5
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
