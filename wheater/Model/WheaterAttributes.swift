//
//  WheaterAttributes.swift
//  wheater
//
//  蔚来车况 灵动岛 / 实时活动 (Live Activity) 数据属性模型
//  本文件同时编译进 App 与 Widget Extension 两个 target，
//  主题令牌（AnimeThemeToken）亦在此定义以供两端共享。
//

import SwiftUI
import ActivityKit

struct WheaterAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        // 车辆基础状态
        var vehicleName: String
        var soc: Double              // 电量百分比 e.g. 78.5
        var remainingRangeKm: Int     // 剩余续航 e.g. 420
        var actualRangeKm: Int?       // 实际估算续航 e.g. 330
        var mileageKm: Int?           // 总里程

        // 充电与行车状态
        var isCharging: Bool
        var chargeStateText: String  // e.g. "直流快充中", "慢充中", "未充电", "已充满"
        var chargingPowerKw: Double? // e.g. 68.5
        var isDriving: Bool?         // 是否行驶中

        // 车锁与车门车窗
        var isLocked: Bool
        var anyDoorOpen: Bool
        var anyWindowOpen: Bool?

        // 胎压 (bar)
        var tyrePressFL: Double?
        var tyrePressFR: Double?
        var tyrePressRL: Double?
        var tyrePressRR: Double?

        // 座舱与模式
        var insideTemp: Double?      // 车内温度
        var outsideTemp: Double?     // 车外温度
        var defenderActive: Bool     // 守卫模式
        var defenderWarnCount: Int?  // 守卫告警数
        var petModeActive: Bool      // 宠物模式
        var campModeActive: Bool     // 露营模式
        var powerHoldActive: Bool    // 离车不下电
        var frdgActive: Bool?        // 车载冰箱
        var frdgTemp: Double?        // 冰箱当前温
        var v2lActive: Bool?         // 对外放电
        // 特殊模式（可选字段，旧负载缺省安全解码为 nil）
        var hiDryActive: Bool?       // 超强干燥（座舱高温干燥）cbn_hi_t_dry_sts
        var defrostActive: Bool?     // 极速除霜 ccu_max_defrst_sts
        var overheatProtectActive: Bool? // 座舱过热保护 cbn_ovr_ht_act_sts

        // 更新时间
        var updateTimestamp: Date

        // v4.8 扩展字段（可选：兼容旧活动负载，缺省安全解码为 nil）
        var themeRaw: String?            // 当前主题 rawValue，Widget据此渲染主题色
        var chargingTargetSoc: Double?   // 充电目标电量（上限/锁电），e.g. 90
        var batteryCapacityKwh: Double?  // 电池包容量推算，e.g. 75
        var chargeEtaDate: Date?         // 预计充满时刻（用于免刷新实时倒计时）
        var lvBattSoc: Int?              // 12V 小电瓶电量 %
        var lvBattVolt: Double?          // 12V 小电瓶电压 V
        var vehicleVersion: String?      // 车机固件短版本号 (FOTA，e.g. "5.1.5"，取不到则 nil)
        var preferActualRange: Bool?     // 用户是否偏好实估续航展示模式
        var refreshNotice: String?       // 最近一次刷新结果标签（"已更新"/"无数据更新"），Widget 与锁屏实时活动展示
        var bgStamp: Int?                // 小组件/锁屏自定义背景版本号（背景变更时递增，驱动实时活动重绘换装）

        // 辅助格式化
        var socDisplay: String {
            guard soc.isFinite else { return "--" }
            if let whole = soc.safeInt, soc == soc.rounded() {
                return "\(whole)%"
            }
            return "\(String(format: "%.1f", soc))%"
        }

        var rangeDisplay: String {
            "\(remainingRangeKm)km"
        }

        var tempDisplay: String {
            if let t = insideTemp {
                return String(format: "%.1f℃", t)
            }
            return "—"
        }

        var powerDisplay: String? {
            guard let p = chargingPowerKw, p > 0 else { return nil }
            return String(format: "%.1f kW", p)
        }

        /// 充满剩余分钟数（依据功率与电池容量推算）
        var chargeEtaMinutes: Int? {
            guard isCharging, let p = chargingPowerKw, p > 0.3, p.isFinite else { return nil }
            let capacity = batteryCapacityKwh ?? 75.0
            let target = min(100.0, chargingTargetSoc ?? 100.0)
            let remainKwh = max(0.0, (target - soc) / 100.0 * capacity)
            guard remainKwh.isFinite, remainKwh > 0.2 else { return 0 }
            return (remainKwh / p * 60.0).rounded(.up).safeInt
        }

        /// 用于去重的"显著变化"指纹（忽略时间戳与主题等非关键差异）
        var significantFingerprint: String {
            [
                String(format: "%.1f", soc),
                "\(remainingRangeKm)",
                "\(actualRangeKm ?? -1)",
                isCharging ? "c" : "-",
                chargeStateText,
                String(format: "%.1f", chargingPowerKw ?? -1),
                isDriving.map { $0 ? "d" : "-" } ?? "?",
                isLocked ? "L" : "u",
                anyDoorOpen ? "D" : "-",
                (anyWindowOpen ?? false) ? "W" : "-",
                String(format: "%.1f", tyrePressFL ?? -1),
                String(format: "%.1f", tyrePressFR ?? -1),
                String(format: "%.1f", tyrePressRL ?? -1),
                String(format: "%.1f", tyrePressRR ?? -1),
                String(format: "%.1f", insideTemp ?? -99),
                String(format: "%.1f", outsideTemp ?? -99),
                defenderActive ? "G\(defenderWarnCount ?? 0)" : "-",
                petModeActive ? "P" : "-",
                campModeActive ? "C" : "-",
                "\(bgStamp ?? -1)",
                powerHoldActive ? "H" : "-",
                (frdgActive ?? false) ? "F" : "-",
                (v2lActive ?? false) ? "V" : "-",
                (hiDryActive ?? false) ? "Y" : "-",
                (defrostActive ?? false) ? "Z" : "-",
                (overheatProtectActive ?? false) ? "O" : "-",
                lvBattSoc.map { "\($0)" } ?? "-",
                vehicleVersion ?? "-",
                chargeEtaDate.map { "\(Int($0.timeIntervalSince1970 / 300))" } ?? "-",
                // 刷新结果标签纳入指纹：标签翻转（已更新↔无数据更新）即触发一次推送，
                // 保证 Widget / 锁屏实时活动的标签始终反映最近一轮拉取结果
                refreshNotice ?? "-"
            ].joined(separator: "|")
        }
    }

    // 静态标识属性
    var vehicleId: String
}

// MARK: - 主题令牌（App 与 Widget 共享的唯一定义）
// 字段以 hex 字符串存储，两端各自解析，避免依赖 app-only 的扩展。

public struct AnimeThemeToken: Codable, Sendable, Equatable {
    public var backgroundPrimary: String
    public var backgroundSecondary: String
    public var accentColor: String
    public var glowColor: String
    public var warmAccent: String
    public var gradientStart: String
    public var gradientEnd: String
    public var cardBackground: String
    public var cardBorder: String
    public var textPrimary: String
    public var textSecondary: String
    public var isDark: Bool

    public init(
        backgroundPrimary: String,
        backgroundSecondary: String,
        accentColor: String,
        glowColor: String,
        warmAccent: String,
        gradientStart: String,
        gradientEnd: String,
        cardBackground: String,
        cardBorder: String,
        textPrimary: String,
        textSecondary: String,
        isDark: Bool
    ) {
        self.backgroundPrimary = backgroundPrimary
        self.backgroundSecondary = backgroundSecondary
        self.accentColor = accentColor
        self.glowColor = glowColor
        self.warmAccent = warmAccent
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.isDark = isDark
    }

    // ── 奶甜系（浅色粉紫蓝橘）────────────────────────────

    /// 草莓奶昔 · 浅色（默认，奶油粉底 + 樱花粉，甜度最高）
    public static let strawberryShake = AnimeThemeToken(
        backgroundPrimary:   "FFF4F1",
        backgroundSecondary: "FFE9E4",
        accentColor:         "FF7FA5",
        glowColor:           "C3B8FF",
        warmAccent:          "FFC94D",
        gradientStart:       "FFA8C5",
        gradientEnd:         "C3B8FF",
        cardBackground:      "FFFFFF",
        cardBorder:          "FFE0D9",
        textPrimary:         "4A2E3A",
        textSecondary:       "8C5F72",
        isDark:              false
    )

    /// 香芋啵啵 · 浅色（芋泥紫 + 泡泡糖粉，梦幻软糯）
    public static let taroBoba = AnimeThemeToken(
        backgroundPrimary:   "F4F0FB",
        backgroundSecondary: "EAE3F7",
        accentColor:         "A97FE8",
        glowColor:           "FFB3D9",
        warmAccent:          "FFC48A",
        gradientStart:       "C3A8F5",
        gradientEnd:         "FFB3D9",
        cardBackground:      "FFFFFF",
        cardBorder:          "E2DAF2",
        textPrimary:         "3A2E4D",
        textSecondary:       "7A6B95",
        isDark:              false
    )

    /// 云朵软糖 · 浅色（云朵蓝 + 蜜桃粉，清爽软萌）
    public static let cloudGummy = AnimeThemeToken(
        backgroundPrimary:   "F0F6FF",
        backgroundSecondary: "E2EDFB",
        accentColor:         "7EB6FF",
        glowColor:           "FFB3D9",
        warmAccent:          "FFD37A",
        gradientStart:       "9CC8FF",
        gradientEnd:         "FFC2DC",
        cardBackground:      "FFFFFF",
        cardBorder:          "DAE7F5",
        textPrimary:         "2E3D52",
        textSecondary:       "64798F",
        isDark:              false
    )

    /// 蜜桃乌龙 · 浅色（蜜桃橘粉 + 焦糖奶，温暖元气）
    public static let peachOolong = AnimeThemeToken(
        backgroundPrimary:   "FFF6EC",
        backgroundSecondary: "FFEAD6",
        accentColor:         "FF9D76",
        glowColor:           "F7C873",
        warmAccent:          "FFB84D",
        gradientStart:       "FFA97E",
        gradientEnd:         "F7C873",
        cardBackground:      "FFFFFF",
        cardBorder:          "F8E3CE",
        textPrimary:         "4D3526",
        textSecondary:       "96755E",
        isDark:              false
    )

    // ── 清新系（浅色绿黄）────────────────────────────────

    /// 薄荷奶绿 · 浅色（薄荷绿 + 奶绿渐变，清新治愈）
    public static let mintMilk = AnimeThemeToken(
        backgroundPrimary:   "EFFAF2",
        backgroundSecondary: "DEF2E6",
        accentColor:         "4FC48F",
        glowColor:           "8FD8C8",
        warmAccent:          "FFC48A",
        gradientStart:       "7FD9A8",
        gradientEnd:         "BFEFC9",
        cardBackground:      "FFFFFF",
        cardBorder:          "D5EBDD",
        textPrimary:         "263D2F",
        textSecondary:       "5F7F6C",
        isDark:              false
    )

    /// 柠檬汽水 · 浅色（柠檬黄 + 奶黄渐变，活泼气泡）
    public static let lemonSoda = AnimeThemeToken(
        backgroundPrimary:   "FFFCEB",
        backgroundSecondary: "FFF5CC",
        accentColor:         "F2B737",
        glowColor:           "FFDF7E",
        warmAccent:          "FF9D76",
        gradientStart:       "FFD97A",
        gradientEnd:         "FFE9A8",
        cardBackground:      "FFFFFF",
        cardBorder:          "F3EAC4",
        textPrimary:         "4A3A1E",
        textSecondary:       "94805A",
        isDark:              false
    )

    // ── 星夜系（深色 · 文字全部高对比提亮）──────────────

    /// 草莓夜曲 · 深色（莓果深夜，软萌不刺眼）
    public static let strawberryNocturne = AnimeThemeToken(
        backgroundPrimary:   "1F1219",
        backgroundSecondary: "2A1822",
        accentColor:         "FF8FB2",
        glowColor:           "C99AE8",
        warmAccent:          "FFC94D",
        gradientStart:       "FF8FB2",
        gradientEnd:         "C99AE8",
        cardBackground:      "2B1A24",
        cardBorder:          "4A2A3D",
        textPrimary:         "FFF3F7",
        textSecondary:       "F0C6D8",
        isDark:              true
    )

    /// 芋泥星球 · 深色（芋泥深空，梦幻夜巡）
    public static let taroPlanet = AnimeThemeToken(
        backgroundPrimary:   "191227",
        backgroundSecondary: "241A38",
        accentColor:         "B78BF0",
        glowColor:           "E8A0D8",
        warmAccent:          "FFC48A",
        gradientStart:       "B78BF5",
        gradientEnd:         "E8A0D8",
        cardBackground:      "231836",
        cardBorder:          "41305E",
        textPrimary:         "F8F2FF",
        textSecondary:       "DFC9F5",
        isDark:              true
    )

    /// 星云棉花糖 · 深色（星云蓝紫，夜空甜梦）
    public static let nebulaMarshmallow = AnimeThemeToken(
        backgroundPrimary:   "121828",
        backgroundSecondary: "1A2338",
        accentColor:         "8CC0FF",
        glowColor:           "D4B8FF",
        warmAccent:          "FFC48A",
        gradientStart:       "8CC0FF",
        gradientEnd:         "D4B8FF",
        cardBackground:      "1C2542",
        cardBorder:          "33436B",
        textPrimary:         "F5F9FF",
        textSecondary:       "C6D6EF",
        isDark:              true
    )

    /// 焦糖布丁 · 深色（焦糖琥珀，温柔暖夜）
    public static let caramelPudding = AnimeThemeToken(
        backgroundPrimary:   "1E1712",
        backgroundSecondary: "2A2117",
        accentColor:         "EFB478",
        glowColor:           "F7CE9E",
        warmAccent:          "F0B45C",
        gradientStart:       "EFB478",
        gradientEnd:         "D98E5A",
        cardBackground:      "2C2216",
        cardBorder:          "4C3A24",
        textPrimary:         "FFF6EA",
        textSecondary:       "EFD6B8",
        isDark:              true
    )

    public static let defaultToken: AnimeThemeToken = .strawberryShake

    /// 旧版主题 rawValue → 新主题兼容映射（老用户存档自动落到最接近的新主题）
    public static func legacyAlias(named raw: String) -> AnimeThemeToken? {
        switch raw {
        case "kawaiiLight":  return .strawberryShake       // 蜜桃兔兔 → 草莓奶昔
        case "kawaii":       return .strawberryNocturne    // 樱夜粉兔 → 草莓夜曲
        case "healing":      return .mintMilk              // 抹茶奶盖 → 薄荷奶绿
        case "minimalLight": return .cloudGummy            // 云石膏 → 云朵软糖
        case "minimalDark", "cyber", "makoto": return .nebulaMarshmallow // 曜石灰/赛博/暮光 → 星云棉花糖
        default:             return nil
        }
    }

    /// 以 rawValue 字符串取预设（未知名先查旧值兼容映射，再回退默认主题）
    public static func preset(named raw: String?) -> AnimeThemeToken {
        guard let raw, !raw.isEmpty else { return .defaultToken }
        switch raw {
        case "strawberryShake":     return .strawberryShake
        case "taroBoba":            return .taroBoba
        case "cloudGummy":          return .cloudGummy
        case "peachOolong":         return .peachOolong
        case "mintMilk":            return .mintMilk
        case "lemonSoda":           return .lemonSoda
        case "strawberryNocturne":  return .strawberryNocturne
        case "taroPlanet":          return .taroPlanet
        case "nebulaMarshmallow":   return .nebulaMarshmallow
        case "caramelPudding":      return .caramelPudding
        default:                    return legacyAlias(named: raw) ?? .defaultToken
        }
    }
}

// MARK: - Widget 侧主题色解析

public struct WheaterThemeColors: Sendable {
    public let background: Color
    public let backgroundSoft: Color
    public let accent: Color
    public let glow: Color
    public let warm: Color
    public let gradientStart: Color
    public let gradientEnd: Color
    public let cardFill: Color
    public let cardStroke: Color
    public let text: Color
    public let textSoft: Color
    public let isDark: Bool

    public init(token: AnimeThemeToken) {
        background = Color(wheaterHex: token.backgroundPrimary)
        backgroundSoft = Color(wheaterHex: token.backgroundSecondary)
        accent = Color(wheaterHex: token.accentColor)
        glow = Color(wheaterHex: token.glowColor)
        warm = Color(wheaterHex: token.warmAccent)
        gradientStart = Color(wheaterHex: token.gradientStart)
        gradientEnd = Color(wheaterHex: token.gradientEnd)
        cardFill = Color(wheaterHex: token.cardBackground)
        cardStroke = Color(wheaterHex: token.cardBorder)
        text = Color(wheaterHex: token.textPrimary)
        textSoft = Color(wheaterHex: token.textSecondary)
        isDark = token.isDark
    }

    public init(themeRaw: String?) {
        self.init(token: .preset(named: themeRaw))
    }

    /// 完整拷贝构造（供自定义背景遮罩下的文字色调翻转）
    public init(background: Color, backgroundSoft: Color, accent: Color, glow: Color, warm: Color,
                gradientStart: Color, gradientEnd: Color, cardFill: Color, cardStroke: Color,
                text: Color, textSoft: Color, isDark: Bool) {
        self.background = background
        self.backgroundSoft = backgroundSoft
        self.accent = accent
        self.glow = glow
        self.warm = warm
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.cardFill = cardFill
        self.cardStroke = cardStroke
        self.text = text
        self.textSoft = textSoft
        self.isDark = isDark
    }

    /// 强制翻转文字明暗（深底浅字 / 浅底深字），主题色保持不变
    public func overridingTextTone(dark: Bool) -> WheaterThemeColors {
        guard dark != isDark else { return self }
        if dark {
            return WheaterThemeColors(
                background: background, backgroundSoft: backgroundSoft,
                accent: accent, glow: glow, warm: warm,
                gradientStart: gradientStart, gradientEnd: gradientEnd,
                cardFill: Color.white.opacity(0.14), cardStroke: Color.white.opacity(0.20),
                text: .white, textSoft: Color.white.opacity(0.72), isDark: true
            )
        } else {
            return WheaterThemeColors(
                background: background, backgroundSoft: backgroundSoft,
                accent: accent, glow: glow, warm: warm,
                gradientStart: gradientStart, gradientEnd: gradientEnd,
                cardFill: Color.black.opacity(0.06), cardStroke: Color.black.opacity(0.10),
                text: Color(red: 0.10, green: 0.10, blue: 0.12),
                textSoft: Color(red: 0.30, green: 0.30, blue: 0.36), isDark: false
            )
        }
    }

    /// 电量进度条用渐变
    public var socGradient: [Color] { [gradientStart, gradientEnd] }
}

public extension Double {
    /// NaN / Infinity / 越界安全转 Int：脏数据返回 nil 而非直接 trap
    /// （`Int(Double)` 对非有限值会崩溃；服务端脏字段（"nan"/"1e400"）经此防护）
    var safeInt: Int? {
        guard isFinite, self >= Double(Int.min), self <= Double(Int.max) else { return nil }
        return Int(self)
    }
}

public extension Color {
    /// 独立命名的 hex 初始化器，避免与 app target 既有 Color(hex:) 冲突
    init(wheaterHex hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}
