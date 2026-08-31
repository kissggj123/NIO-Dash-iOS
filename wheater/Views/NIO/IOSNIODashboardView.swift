//
//  IOSNIODashboardView.swift
//  wheater
//
//  蔚来车况看板（iOS 二次元专属萌动可爱版 🌸🐰✨）
//
//  注意：所有卡片均拆分为独立子 View struct。若把卡片以计算属性内联回 body，
//  Debug 构建生成的巨型泛型类型会在真机（主线程栈仅 1MB）实例化时栈溢出闪退
//  （EXC_BAD_ACCESS code=2 @ swift_getTypeByMangledName）。
//

import SwiftUI
import MapKit
import Charts

// MARK: - 主题色集合（由 AnimeThemeService 派生，随主题切换实时刷新）

struct NIOAnimeColors {
    let sakuraPink: Color
    let mintCyan: Color
    let lavenderDream: Color
    let pastelYellow: Color

    @MainActor
    static func resolve(_ theme: AnimeThemeService) -> NIOAnimeColors {
        NIOAnimeColors(
            sakuraPink: theme.accentColor(),
            mintCyan: theme.glowColor(),
            lavenderDream: Color(hex: theme.currentToken.gradientEnd),
            pastelYellow: Color(hex: theme.currentToken.warmAccent)
        )
    }
}

// MARK: - 文件级小工具

private func nioFormatDateTime(_ date: Date) -> String {
    NIOFormatters.dateTimeFull.string(from: date)
}

private func nioToJSON<T: Encodable>(_ value: T?) -> String? {
    guard let value = value else { return nil }
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

// MARK: - 入场动画修饰（offset + fade + spring delay）

private extension View {
    func nioEntry(hasAppeared: Bool, delay: Double, lift: CGFloat = 25) -> some View {
        offset(y: hasAppeared ? 0 : lift)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(delay), value: hasAppeared)
    }
}

// MARK: - 萌系徽章

@MainActor
private struct NIOAnimeBadge: View {
    let text: String
    let active: Bool
    let activeColor: Color

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(active ? activeColor : NIOThemePaint.text.opacity(0.3))
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(active ? activeColor : NIOThemePaint.text.opacity(0.5))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(active ? activeColor.opacity(0.18) : NIOThemePaint.fill)
        .clipShape(Capsule())
    }
}

// MARK: - 萌系卡片容器

@MainActor
private struct NIOAnimeCardContainer<Content: View>: View {
    let title: String
    let icon: String
    let colors: NIOAnimeColors
    var jsonProvider: (() -> String?)?
    var onShowJSON: (String?, String?) -> Void
    private let content: () -> Content

    init(
        title: String,
        icon: String,
        colors: NIOAnimeColors,
        jsonProvider: (() -> String?)? = nil,
        onShowJSON: @escaping (String?, String?) -> Void = { _, _ in },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.colors = colors
        self.jsonProvider = jsonProvider
        self.onShowJSON = onShowJSON
        self.content = content
    }

    private var sakuraPink: Color { colors.sakuraPink }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(sakuraPink)
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                }

                Spacer()

                if let provider = jsonProvider {
                    Button(action: {
                        onShowJSON(title, provider())
                    }) {
                        Text("{ }")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(lavenderDream)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NIOThemePaint.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            content()
        }
        .padding(14)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [NIOThemePaint.stroke, NIOThemePaint.fill],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - 梦幻二次元背景

@MainActor
private struct NIOAnimeBackground: View {
    let colors: NIOAnimeColors

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        ZStack {
            AnimeThemeService.shared.backgroundPrimary()

            // 柔和光晕
            RadialGradient(
                colors: [sakuraPink.opacity(0.25), Color.clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 280
            )

            RadialGradient(
                colors: [lavenderDream.opacity(0.22), Color.clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 260
            )

            RadialGradient(
                colors: [mintCyan.opacity(0.18), Color.clear],
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 320
            )
        }
    }
}

// MARK: - 1. 萌宠气泡对话框

@MainActor
private struct NIOAnimeMascotHeader: View {
    let status: NIOVehicleStatus?
    let isLoadingVehicle: Bool
    let lastVehicleFetch: Date?
    let colors: NIOAnimeColors

    @State private var mascotTapCount = 0
    @State private var isMascotBouncing = false
    @State private var customMascotText: String?

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    isMascotBouncing = true
                }
                mascotTapCount += 1
                let quotes = [
                    "主人今天也要元气满满地出发喵！🌸✨",
                    "爱车已进入最优电能守护状态~ ⚡️",
                    "要经常来看看兔可可喔，我会一直在这里等你！🐰💖",
                    "座舱空气已达到森林级清新标准啦！🍃",
                    "戳我干嘛喵？快去开车兜风啦~ 🚗💨"
                ]
                customMascotText = quotes[mascotTapCount % quotes.count]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isMascotBouncing = false
                }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [sakuraPink.opacity(0.8), lavenderDream.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: sakuraPink.opacity(0.4), radius: 6, y: 2)

                    Text("🐰")
                        .font(.system(size: 24))
                        .scaleEffect(isMascotBouncing ? 1.25 : 1.0)
                        .rotationEffect(.degrees(isMascotBouncing ? 12 : 0))
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 6) {
                // 对话气泡
                Text(customMascotText ?? mascotDialogue)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .lineLimit(2)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(sakuraPink.opacity(0.3), lineWidth: 0.8)
                    )

                // 底部刷新时间小胶囊
                refreshTimeBadge
            }

            Spacer()
        }
    }

    @MainActor
    @ViewBuilder
    private var refreshTimeBadge: some View {
        HStack(spacing: 4) {
            if isLoadingVehicle {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 8, height: 8)
                Text("拉取中…")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(mintCyan)
            } else {
                Circle()
                    .fill(mintCyan)
                    .frame(width: 5, height: 5)
                    .shadow(color: mintCyan.opacity(0.8), radius: 3)
                if let lastTime = lastVehicleFetch {
                    Text("刷新于 " + nioFormatDateTime(lastTime))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                } else {
                    Text("未刷新")
                        .font(.system(size: 9))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(NIOThemePaint.fill)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(NIOThemePaint.stroke, lineWidth: 0.8))
    }

    private var mascotDialogue: String {
        guard let soc = status?.socStatus?.soc else {
            return "主人好呀！点击右上角设置配置车辆参数，让我为你守护爱车喵~ 💖"
        }
        let offcar = status?.offcarModeStatus ?? [:]
        let isRealCharging = NIOVehicleLib.isRealCharging(socStatus: status?.socStatus, offcarStatus: offcar)
        let defender = NIOVehicleLib.defenderModeActive(offcar).isActive
        let pet = NIOVehicleLib.modeActive(offcar["pet_mode_status"] ?? offcar["pet_mode"])
        let camping = NIOVehicleLib.modeActive(offcar["camping_mode_status"] ?? offcar["camping_mode"])
        let powerHold = NIOVehicleLib.modeActive(offcar["power_hold_mode_status"] ?? offcar["power_hold_mode"])
        let temp = status?.hvacStatus?.temperature ?? 25.0

        let hvac = status?.hvacStatus
        let isDry = (hvac?.cbnHiTDrySts ?? 0) == 1
        let isDefrost = (hvac?.ccuMaxDefrstSts ?? 0) == 1

        if isDry {
            return "座舱高温超强干燥运行中！正在为您抑菌烘干座舱空调系统~ ♨️✨"
        } else if isDefrost {
            return "极速除雾除霜运行中！全功率扫清车窗视野~ ❄️💨"
        } else if isRealCharging {
            return "爱车正在全力补能中⚡️ 兔可可为你时刻关注充电进度喵~ 🌸"
        } else if defender {
            return "守卫模式全天候警戒中！任何风吹草动我都会帮你盯紧哒~ 🛡️✨"
        } else if pet {
            return "宠物关怀模式开启中🐾 车内温度保持舒适，宝贝很安全哦~"
        } else if camping {
            return "露营模式已就绪⛺️ 享受静谧舒适的座舱时光吧~ 🌙"
        } else if powerHold {
            return "离车不下电模式已开启！空调与车载用电器持续供电中~ ⚡️"
        } else if temp > 30 {
            return "车里温度达到 \(String(format: "%.1f℃", temp)) 啦，出发前记得提前开空调降温哦~ 🍧"
        } else {
            return "爱车电量 \(Int(soc))% 能量满满！雪豹与海獭陪你开心出发~ 🐆🦦💨"
        }
    }
}

// MARK: - 鉴权失效提示卡片

@MainActor
private struct NIOAnimeAuthExpiredCard: View {
    let colors: NIOAnimeColors
    let onUpdate: () -> Void

    private var sakuraPink: Color { colors.sakuraPink }

    var body: some View {
        HStack(spacing: 10) {
            Text("⚠️")
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("鉴权 Token 已在其他设备失效")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(sakuraPink)
                Text("如果在其他手机重新登录过蔚来，点击右侧按钮重新粘贴即可恢复。")
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.7))
            }

            Spacer()

            Button("一键更新", action: onUpdate)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(sakuraPink)
                .foregroundStyle(Color.white)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(sakuraPink.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(sakuraPink.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - 未配置欢迎卡片

@MainActor
private struct NIOWelcomeSetupCard: View {
    let colors: NIOAnimeColors
    let onConfigure: () -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [sakuraPink, mintCyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 70, height: 70)
                    .shadow(color: sakuraPink.opacity(0.5), radius: 12)

                Text("✨🚗")
                    .font(.system(size: 32))
            }

            Text("欢迎绑定你的蔚来座驾")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            Text("只需粘贴一次抓包链接或运行 sniff.sh，就能开启灵动岛续航、车门车窗全景与座舱模式！")
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)

            Button(action: onConfigure) {
                HStack(spacing: 6) {
                    Text("⚡️")
                    Text("一键识别并配置参数")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: sakuraPink.opacity(0.4), radius: 6)
            }
        }
        .padding(20)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }
}

// MARK: - 2. 爱车萌动形象卡片 (3D 车图 + 状态胶囊 + 总里程)

@MainActor
private struct NIOAnimeHeroVehicleCard: View {
    let status: NIOVehicleStatus?
    let lastVehicleFetch: Date?
    let colors: NIOAnimeColors

    @State private var isVehicleFloating = false
    @AppStorage("nio_reduced_fx") private var reducedFx = false
    @State private var isCarSparkling = false
    @AppStorage("nio_vehicle_selected_model") private var selectedModelSlug = "et5_special"
    @AppStorage("nio_vehicle_selected_color") private var selectedColorSlug = "nature_wonder"

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let socVal = status?.socStatus?.soc ?? 0.0
        let actualRange = status?.socStatus?.remainingActualRange ?? 0.0
        let nominalRange = status?.socStatus?.remainingRange ?? 0.0
        let displayRange = actualRange > 0 ? actualRange : nominalRange
        let offcar = status?.offcarModeStatus ?? [:]
        let isRealCharging = NIOVehicleLib.isRealCharging(socStatus: status?.socStatus, offcarStatus: offcar)
        let isDriving = (status?.exteriorStatus?.vehicleState == 1)
        let isSleeping = (status?.connectionStatus?.connected == false || (status?.exteriorStatus?.vehicleState ?? 0) <= 0 || (status?.exteriorStatus?.vehicleState ?? 0) == 3)
        let isLocked = (status?.doorStatus?["vehicle_lock_status"]?.intValue ?? 1) == 1
        let windows = status?.windowStatus ?? [:]
        let winOpen = (windows["win_posn_fl"]?.intValue ?? 0) > 0 || (windows["win_posn_fr"]?.intValue ?? 0) > 0 || (windows["win_posn_rl"]?.intValue ?? 0) > 0 || (windows["win_posn_rr"]?.intValue ?? 0) > 0 || (windows["sun_roof_posn"]?.intValue ?? 0) > 0
        let allDoorsClosed = (status?.doorStatus?["door_ajar_front_left_status"]?.intValue ?? 1) == 1 && (status?.doorStatus?["door_ajar_front_right_status"]?.intValue ?? 1) == 1

        return VStack(spacing: 10) {
            // 车型徽章与总里程
            HStack {
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [sakuraPink.opacity(0.4), lavenderDream.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 18, height: 18)

                        Image("NIO_brand")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 12)
                            .clipShape(Circle())
                    }

                    Text(currentVehicleTitle)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(pastelYellow)
                }
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(NIOThemePaint.fill)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(NIOThemePaint.stroke, lineWidth: 0.8))

                Spacer()

                if let mileage = status?.exteriorStatus?.mileage {
                    Text("🚗 总里程 \(Int(round(mileage))) km")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NIOThemePaint.stroke)
                        .foregroundStyle(NIOThemePaint.text)
                        .clipShape(Capsule())
                }
            }

            // 车辆 3D 浮动图像 + 交互触感
            VStack(spacing: 6) {
                ZStack {
                    currentVehicleImageView
                        .frame(maxHeight: 125)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .shadow(color: mintCyan.opacity(0.3), radius: 10, y: 4)
                        .offset(y: isVehicleFloating ? -3 : 3)
                        .scaleEffect(isCarSparkling ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isCarSparkling)

                    if isCarSparkling {
                        HStack(spacing: 16) {
                            Text("✨")
                                .font(.system(size: 18))
                            Spacer()
                            Text("🐆")
                                .font(.system(size: 18))
                            Spacer()
                            Text("🦦")
                                .font(.system(size: 18))
                        }
                        .padding(.horizontal, 30)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isCarSparkling = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            isCarSparkling = false
                        }
                    }
                }
            }

            // 经典 nio-dash / ha-nio 5 联快捷状态栏（使用实估续航）
            HStack(alignment: .center) {
                // 左侧：NIO Logo + 车型 - 实估续航
                HStack(spacing: 5) {
                    Image("NIO_brand")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                    
                    Text("\(shortModelName) · \(Int(round(displayRange))) km")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                }

                Spacer()

                // 右侧：5 联快捷状态图标
                HStack(spacing: 11) {
                    // 1. 电量
                    quickStatusColumn(
                        icon: batteryIcon(for: Int(socVal)),
                        label: "\(Int(socVal))%",
                        tint: socVal < 20 ? sakuraPink : (isRealCharging ? .green : mintCyan)
                    )

                    // 2. 停放/行驶/充电
                    quickStatusColumn(
                        icon: isRealCharging ? "bolt.car.fill" : (isDriving ? "car.side.fill" : "car.fill"),
                        label: isRealCharging ? "充电" : (isDriving ? "行驶" : "停放"),
                        tint: isDriving ? pastelYellow : (isRealCharging ? .green : NIOThemePaint.text.opacity(0.85))
                    )

                    // 3. 休眠/在线
                    quickStatusColumn(
                        icon: "zzz",
                        label: isSleeping ? "休眠" : "在线",
                        tint: isSleeping ? lavenderDream : mintCyan
                    )

                    // 4. 车锁/车门
                    quickStatusColumn(
                        icon: isLocked ? "lock.fill" : "lock.open.fill",
                        label: (isLocked && allDoorsClosed) ? "已关" : (isLocked ? "已锁" : "未锁"),
                        tint: isLocked ? mintCyan : sakuraPink
                    )

                    // 5. 车窗
                    quickStatusColumn(
                        icon: !winOpen ? "square.split.2x2.fill" : "square.split.2x2",
                        label: !winOpen ? "已关" : "开启",
                        tint: !winOpen ? mintCyan : sakuraPink
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(NIOThemePaint.bar)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
        .onAppear {
            guard !reducedFx else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isVehicleFloating = true
            }
        }
    }

    @MainActor
    @ViewBuilder
    private func quickStatusColumn(icon: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(height: 14)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(tint.opacity(0.9))
        }
    }

    private func batteryIcon(for soc: Int) -> String {
        if soc >= 85 { return "battery.100percent" }
        if soc >= 60 { return "battery.75percent" }
        if soc >= 35 { return "battery.50percent" }
        if soc >= 10 { return "battery.25percent" }
        return "battery.0percent"
    }

    private var shortModelName: String {
        if selectedModelSlug == "et5_special" { return "ET5" }
        if let model = NIOVehicleModelLib.findModel(by: selectedModelSlug) {
            return model.name
        }
        return "ET5"
    }

    private var currentVehicleTitle: String {
        if selectedModelSlug == "et5_special" {
            return "蔚来 2026款 ET5 · 自然奇境版"
        }
        if let model = NIOVehicleModelLib.findModel(by: selectedModelSlug) {
            let color = model.colors.first(where: { $0.slug == selectedColorSlug }) ?? model.colors.first
            let colorName = color?.name ?? ""
            return "蔚来 \(model.name) · \(colorName)"
        }
        return "蔚来 2026款 ET5 · 自然奇境版"
    }

    @ViewBuilder
    private var currentVehicleImageView: some View {
        if selectedModelSlug == "et5_special" {
            Image("ET5_CleanPark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else if let model = NIOVehicleModelLib.findModel(by: selectedModelSlug) {
            let color = model.colors.first(where: { $0.slug == selectedColorSlug }) ?? model.colors.first
            if let fileName = color?.fileName, let uiImg = NIOVehicleModelLib.loadCarImage(named: fileName) {
                Image(uiImage: uiImg)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image("ET5_CleanPark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        } else {
            Image("ET5_CleanPark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - 3. ⚡️ 超能萌动电量与续航

@MainActor
private struct NIOAnimeBatteryCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    @AppStorage("nio_prefer_actual_range") private var preferActualRange = false
    @State private var energyShimmer = false
    @AppStorage("nio_reduced_fx") private var reducedFx = false

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        NIOAnimeCardContainer(
            title: "⚡️ 萌动超能电量 & 续航",
            icon: "bolt.heart.fill",
            colors: colors,
            jsonProvider: { nioToJSON(status?.socStatus) },
            onShowJSON: onShowJSON
        ) {
            if let soc = status?.socStatus {
                let socVal = soc.soc ?? 0
                let socStr = (socVal.truncatingRemainder(dividingBy: 1) == 0) ? "\(Int(socVal))" : String(format: "%.1f", socVal)
                let cltcKm = soc.remainingRange
                let actKm = soc.remainingActualRange
                let hasAct = (actKm ?? 0) > 0
                let stdRange = Int(round(cltcKm ?? 0))

                // bestRange: 有实估用实估，没有则 CLTC × 0.795 推算
                let best = NIOVehicleLib.bestRange(cltcKm: cltcKm, actualKm: actKm)
                let mainRange = best?.km ?? stdRange
                let isCalcEstimate = best?.isEstimated ?? false

                // 副标签：主显示是实估时显示 CLTC，主显示是 CLTC 时显示推算实估
                let subRangeText: String? = {
                    if preferActualRange && hasAct {
                        return "🌸 预估工况 \(stdRange) km"
                    } else if hasAct {
                        return "🎯 实估续航 \(Int(round(actKm!))) km"
                    } else if isCalcEstimate {
                        return "≈ 实估推算 \(mainRange) km (×0.795)"
                    }
                    return nil
                }()

                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        // 电量百分比 (干净整数或一位小数，绝不出现 .000)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(soc.soc != nil ? socStr : "—")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [mintCyan, sakuraPink], startPoint: .leading, endPoint: .trailing)
                                )
                            Text("%")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(sakuraPink)
                        }

                        Spacer()

                        // 续航里程 (首选实估 / 标准，干净整数绝无多余小数)
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(preferActualRange && hasAct ? Int(round(actKm!)) : (hasAct ? stdRange : mainRange))")
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                    .foregroundStyle(NIOThemePaint.text)
                                Text("km")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                            }
                            if let sub = subRangeText {
                                Text(sub)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(isCalcEstimate ? sakuraPink.opacity(0.8) : lavenderDream)
                            }
                        }
                    }

                    // 萌系双色能量槽 + 流光能量波
                    GeometryReader { geo in
                        let w = max(8, geo.size.width * CGFloat(min(100.0, max(0.0, socVal))) / 100.0)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(NIOThemePaint.stroke)

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [mintCyan, sakuraPink],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: w)
                                    .shadow(color: sakuraPink.opacity(0.6), radius: 4)

                                // 动态能量流光
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.clear, NIOThemePaint.text.opacity(0.6), Color.clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(12, w * 0.35))
                                    .offset(x: energyShimmer ? (w * 0.7) : 0)
                                    .mask(Capsule().frame(width: w))
                            }
                        }
                    }
                    .frame(height: 8)

                    // 充电状态与电池包推算
                    HStack {
                        let isRealCharging = NIOVehicleLib.isRealCharging(socStatus: soc, offcarStatus: status?.offcarModeStatus)
                        let chargeDesc = NIOVehicleLib.smartChargeStateDescription(socStatus: soc, offcarStatus: status?.offcarModeStatus)
                        let isCamping = NIOVehicleLib.modeActive(status?.offcarModeStatus?["camping_mode_status"] ?? status?.offcarModeStatus?["camping_mode"])
                        let isPowerHold = NIOVehicleLib.modeActive(status?.offcarModeStatus?["power_hold_mode_status"] ?? status?.offcarModeStatus?["power_hold_mode"])
                        let isV2L = (soc.v2lStatus ?? 0) == 1

                        NIOAnimeBadge(text: chargeDesc, active: isRealCharging || isCamping || isPowerHold || isV2L, activeColor: isRealCharging ? .green : (isCamping ? lavenderDream : mintCyan))

                        if let type = soc.chargerType, type > 0, isRealCharging {
                            NIOAnimeBadge(text: NIOVehicleLib.chargerTypeLabel(type), active: true, activeColor: mintCyan)
                        }

                        Spacer()

                        if let p = soc.chargingPower, p > 0 {
                            Text(verbatim: "⚡️ \(String(format: "%.1f", p / 1000.0)) kW")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(mintCyan)
                        }

                        if let full = soc.remainingRange.flatMap({ r in soc.soc.map { NIOVehicleLib.fullChargeRangeKm(remainingRange: r, soc: $0) } }), let f = full {
                            Text("满电预估 \(f)km" + NIOVehicleLib.batteryPackLabel(fullRangeKm: f))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        }
                    }

                    // 达成率与 12V 小电瓶系统
                    let lvBatt = status?.lvBattStatus ?? [:]
                    let lvSoc = lvBatt["lv_batt_soc"]?.intValue
                    let lvVolt = lvBatt["lv_batt_volt"]?.numberValue
                    let achieveRate = NIOVehicleLib.rangeAchievementRatio(actual: soc.remainingActualRange, standard: soc.remainingRange)

                    HStack(spacing: 8) {
                        if let rate = achieveRate {
                            HStack(spacing: 3) {
                                Text("达成率")
                                    .font(.system(size: 9))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                                Text(verbatim: "\(String(format: "%.1f", rate))%")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(mintCyan)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(mintCyan.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        if let maxSoc = soc.maxSoc, maxSoc > 0 {
                            Text("上限 \(Int(maxSoc))%")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        }

                        if let lockSoc = soc.lockSoc, lockSoc > 0 {
                            Text("锁电 \(Int(lockSoc))%")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                        }

                        Spacer()

                        if let lvS = lvSoc {
                            HStack(spacing: 2) {
                                Image(systemName: "car.side.fill")
                                    .font(.system(size: 8))
                                Text("12V电瓶 \(lvS)%")
                                    .font(.system(size: 9, weight: .medium))
                                if let volt = lvVolt {
                                    Text(verbatim: "\(String(format: "%.1f", volt))V")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                            }
                            .foregroundStyle(lvS > 50 ? NIOThemePaint.text.opacity(0.7) : sakuraPink)
                        }
                    }
                }
            } else {
                Text("暂无电池数据").font(.footnote).foregroundStyle(NIOThemePaint.text.opacity(0.5))
            }
        }
        .onAppear {
            guard !reducedFx else { return }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                energyShimmer = true
            }
        }
    }
}

// MARK: - 3.5 ⚡️ 充电大屏与高压快充详情

@MainActor
private struct NIOAnimeChargingDetailCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let soc = status?.socStatus
        let portRaw = status?.doorStatus?["second_charge_port_ajar_status"]?.intValue ?? status?.doorStatus?["charge_port_status"]?.intValue
        let isPortOpen = (portRaw != nil && portRaw != 1)
        let powerW = soc?.chargingPower ?? 0
        let realCur = soc?.chargerRealCurA ?? 0
        let realVol = soc?.chargerRealVolV ?? 0
        let targetSoc = soc?.targetSocPercentage ?? soc?.maxSoc
        let chargerType = soc?.chargerType ?? 0
        let isRealCharging = NIOVehicleLib.isRealCharging(socStatus: soc, offcarStatus: status?.offcarModeStatus) || (powerW > 0)

        if soc != nil {
            NIOAnimeCardContainer(
                title: "⚡️ 高压充电与功率实时大屏",
                icon: isRealCharging ? "bolt.badge.clock.fill" : "bolt.badge.automatic.fill",
                colors: colors,
                jsonProvider: { nioToJSON(status?.socStatus) },
                onShowJSON: onShowJSON
            ) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        // 1. 补能功率
                        VStack(alignment: .leading, spacing: 2) {
                            Text("补能功率")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            Text(verbatim: isRealCharging && powerW > 0 ? "\(String(format: "%.1f", Double(powerW) / 1000.0)) kW" : (isRealCharging ? "通电中…" : "待机 0.0 kW"))
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundStyle(isRealCharging ? mintCyan : NIOThemePaint.text.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // 2. 实时电压与电流
                        VStack(alignment: .leading, spacing: 2) {
                            Text("高压电网")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            Text(verbatim: (realVol > 0 || realCur > 0) ? "\(Int(realVol))V · \(String(format: "%.1f", realCur))A" : (isRealCharging ? "通电中 ⚡️" : "未通电 (0V·0A)"))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle((realVol > 0 || isRealCharging) ? pastelYellow : NIOThemePaint.text.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // 3. 目标限充
                        if let target = targetSoc, target > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("目标限充")
                                    .font(.system(size: 9))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                                Text("\(Int(target))%")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(lavenderDream)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(NIOThemePaint.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // 底部状态栏与倒计时
                    HStack(spacing: 6) {
                        if isRealCharging {
                            NIOAnimeBadge(text: NIOVehicleLib.chargerTypeLabel(chargerType), active: true, activeColor: mintCyan)
                            if isPortOpen {
                                NIOAnimeBadge(text: "充电口盖已开 🔌", active: true, activeColor: sakuraPink)
                            }
                        } else if isPortOpen {
                            NIOAnimeBadge(text: "充电口盖已打开 🔌", active: true, activeColor: sakuraPink)
                        } else if chargerType > 0 {
                            NIOAnimeBadge(text: "上次充电: " + NIOVehicleLib.chargerTypeLabel(chargerType), active: false, activeColor: mintCyan)
                        }

                        Spacer()

                        if isRealCharging {
                            if let remaining = NIOVehicleLib.chargeRemainingTimeText(estimateEndTimeMs: soc?.estimateChargeEndTime) {
                                Text(remaining)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(mintCyan)
                            } else if let est = soc?.estimateChargeEndTime, est > 0 {
                                Text("预计 " + NIOVehicleLib.fmtTime(est) + " 充满")
                                    .font(.system(size: 9))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            }
                        } else {
                            Text("插枪后将自动显示实时补能参数")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 4. 💻 车机系统与固件版本 (FOTA)

@MainActor
private struct NIOAnimeFotaCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        let fota = status?.fotaStatus
        let currentVer = fota?.currentVersion ?? ""
        let info = NIOVehicleLib.parseFotaInfo(version: currentVer)
        let shortVer = info.shortVer
        let currentPart = fota?.currentPartNo
        let lastVer = fota?.lastVersion
        let fotaSts = fota?.fotaStatus ?? 0
        let fotaDesc = fotaSts == 0 ? "已是最新版本 ✨" : (fotaSts == 1 ? "升级准备中 🚀" : "固件下载中 📥")

        return NIOAnimeCardContainer(
            title: "⚡️ 车机固件版本 (FOTA)",
            icon: "laptopcomputer.and.iphone",
            colors: colors,
            jsonProvider: { nioToJSON(fota) },
            onShowJSON: onShowJSON
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前版本号")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(!shortVer.isEmpty ? shortVer : "—")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(mintCyan)
                            if !currentVer.isEmpty && currentVer != shortVer {
                                Text("(\(currentVer))")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(lavenderDream.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    NIOAnimeBadge(text: fotaDesc, active: true, activeColor: fotaSts == 0 ? .green : sakuraPink)
                }

                HStack(spacing: 12) {
                    if let part = currentPart, !part.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("零件号")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                            Text(part)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                        }
                    }

                    if let last = lastVer, !last.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("上一版本")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                            Text(last)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                        }
                    }

                    Spacer()

                    if let st = fota?.sampleTime {
                        Text("采样于 " + NIOVehicleLib.fmtTime(st))
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                    }
                }
            }
        }
    }
}

// MARK: - 5. 📍 停车位置与寻车导航卡片

@MainActor
private struct NIOAnimeLocationCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    @AppStorage("nio_hide_location_coords") private var hideLocationCoords = false

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        if let pos = status?.positionStatus, let lat = pos.latitude, let lng = pos.longitude, lat != 0, lng != 0 {
            let wgs = NIOVehicleLib.gcj02ToWgs84(lat: lat, lng: lng)
            NIOAnimeCardContainer(
                title: "📍 停车位置与寻车导航",
                icon: "location.north.circle.fill",
                colors: colors,
                jsonProvider: { nioToJSON(pos) },
                onShowJSON: onShowJSON
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("当前停车坐标 (WGS-84 精准纠偏)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))

                                Button(action: {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        hideLocationCoords.toggle()
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: hideLocationCoords ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 8))
                                        Text(hideLocationCoords ? "已脱敏" : "隐藏坐标")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .foregroundStyle(hideLocationCoords ? sakuraPink : mintCyan)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(NIOThemePaint.fill)
                                    .clipShape(Capsule())
                                }
                            }

                            if hideLocationCoords {
                                HStack(spacing: 4) {
                                    Text("***.*****, ***.*****")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(sakuraPink)
                                    Text("🙈 隐私保护")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(sakuraPink.opacity(0.8))
                                }
                            } else {
                                Text(verbatim: "\(String(format: "%.5f", wgs.lat)), \(String(format: "%.5f", wgs.lng))")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(mintCyan)
                            }
                        }
                        Spacer()
                        if let st = pos.sampleTime {
                            Text("定位于 " + NIOVehicleLib.fmtTime(st))
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            if let appleMapUrl = URL(string: "http://maps.apple.com/?daddr=\(wgs.lat),\(wgs.lng)&dirflg=d") {
                                UIApplication.shared.open(appleMapUrl)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "map.fill")
                                Text("苹果地图")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                        }

                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            if let amapUrl = URL(string: "iosamap://viewMap?sourceApplication=wheater&poiname=爱车位置&lat=\(lat)&lon=\(lng)&dev=0") {
                                if UIApplication.shared.canOpenURL(amapUrl) {
                                    UIApplication.shared.open(amapUrl)
                                } else if let webAmap = URL(string: "https://uri.amap.com/marker?position=\(lng),\(lat)&name=爱车位置") {
                                    UIApplication.shared.open(webAmap)
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                Text("高德地图")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(mintCyan.opacity(0.25))
                            .foregroundStyle(mintCyan)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(mintCyan.opacity(0.5), lineWidth: 0.8))
                        }

                        Spacer()

                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            UIPasteboard.general.string = "\(wgs.lat),\(wgs.lng)"
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                                .padding(6)
                                .background(NIOThemePaint.fill)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 6. 🚪 守护结界 · 车门车锁动态全景

@MainActor
private struct NIOAnimeDoorsCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }

    var body: some View {
        let items = NIOVehicleLib.parseAvailableDoors(doorStatus: status?.doorStatus, windowStatus: status?.windowStatus)
        return NIOAnimeCardContainer(
            title: "🚪 雪豹与海獭守护结界 · 车门车况全景",
            icon: "lock.shield.fill",
            colors: colors,
            jsonProvider: { nioToJSON(status?.doorStatus) },
            onShowJSON: onShowJSON
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items) { item in
                    doorTile(item: item)
                }
            }
        }
    }

    @MainActor
    @ViewBuilder
    private func doorTile(item: NIOVehicleLib.ParsedDoorItem) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.isClosed ? mintCyan : sakuraPink)
                Text(item.title)
                    .font(.system(size: 9))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
            }
            Text(item.isClosed ? item.customClosedLabel : item.customOpenLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(item.isClosed ? NIOThemePaint.text : sakuraPink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(item.isClosed ? NIOThemePaint.fill : sakuraPink.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(item.isClosed ? NIOThemePaint.fill : sakuraPink.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - 6.5 🪟 车窗与天幕开度全景透视

@MainActor
private struct NIOAnimeWindowsCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let win = status?.windowStatus ?? [:]
        let fl = win["win_posn_fl"]?.intValue ?? 0
        let fr = win["win_posn_fr"]?.intValue ?? 0
        let rl = win["win_posn_rl"]?.intValue ?? 0
        let rr = win["win_posn_rr"]?.intValue ?? 0
        let sunRoof = win["sun_roof_posn"]?.intValue ?? 0
        let mirrorFold = win["rearview_mirror_fold"]?.intValue == 1

        let anyWinOpen = fl > 0 || fr > 0 || rl > 0 || rr > 0 || sunRoof > 0

        NIOAnimeCardContainer(
            title: "🪟 车窗与天幕开度透视",
            icon: "macwindow.badge.plus",
            colors: colors,
            jsonProvider: { nioToJSON(status?.windowStatus) },
            onShowJSON: onShowJSON
        ) {
            VStack(spacing: 8) {
                HStack {
                    Text(anyWinOpen ? "⚠️ 有车窗处于开启状态" : "🔒 全车车窗与天幕已完全关闭")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(anyWinOpen ? sakuraPink : mintCyan)
                    Spacer()
                    NIOAnimeBadge(text: mirrorFold ? "后视镜已折叠 🔒" : "后视镜展开", active: mirrorFold, activeColor: mintCyan)
                }

                // 2x2 四门车窗开度进度条
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    windowTile(name: "左前车窗", pos: fl)
                    windowTile(name: "右前车窗", pos: fr)
                    windowTile(name: "左后车窗", pos: rl)
                    windowTile(name: "右后车窗", pos: rr)
                }

                if sunRoof > 0 || win["sun_roof_posn"] != nil {
                    HStack {
                        Text("全景天窗/天幕")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        Spacer()
                        Text(sunRoof > 0 ? "开启 \(sunRoof)%" : "已完全关闭")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(sunRoof > 0 ? sakuraPink : mintCyan)
                    }
                    .padding(6)
                    .background(NIOThemePaint.well.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func windowTile(name: String, pos: Int) -> some View {
        let isOpen = pos > 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(.system(size: 9))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                Spacer()
                Text(isOpen ? "开启 \(pos)%" : "已关严")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isOpen ? sakuraPink : mintCyan)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(NIOThemePaint.well)
                    if isOpen {
                        Capsule()
                            .fill(LinearGradient(colors: [sakuraPink, pastelYellow], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, g.size.width * CGFloat(min(100, pos)) / 100.0))
                    }
                }
            }
            .frame(height: 4)
        }
        .padding(6)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 6.6 🚗 驾驶模式、行车与泊车详情

@MainActor
private struct NIOAnimeDrivingParkingCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let ext = status?.exteriorStatus
        let vehlMode = ext?.vehlMode ?? 0
        let vehlState = ext?.vehicleState ?? 0
        let tripShare = status?.tripShareStatus?["trip_share_status"]?.intValue ?? 0
        let isRpa = (status?.specialStatus?["rvs_rpa_out"]?.intValue == 1) || (vehlState == 5)

        let modeDesc: String = {
            let base = NIOVehicleLib.vehlModeLabel(vehlMode)
            return vehlState == 2 ? "上次设定: \(base)" : "\(base) ⚡️"
        }()

        let stateDesc: String = {
            switch vehlState {
            case 1: return "行驶中 · D 挡"
            case 2: return "驻车停放 · P 挡"
            case 3: return "休眠待机 💤"
            case 4: return "充电连接中 ⚡️"
            case 5: return "遥控泊车进行中 🅿️"
            default: return "安全驻车 · P 挡"
            }
        }()

        NIOAnimeCardContainer(
            title: "🚗 驾驶模式与行车泊车全景",
            icon: "steeringwheel.and.key",
            colors: colors,
            jsonProvider: { nioToJSON(status?.exteriorStatus) },
            onShowJSON: onShowJSON
        ) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("驾驶模式")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        Text(modeDesc)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(mintCyan)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("车辆挡位与状态")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        Text(stateDesc)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(vehlState == 1 ? pastelYellow : (vehlState == 5 ? sakuraPink : lavenderDream))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 6) {
                    NIOAnimeBadge(text: isRpa ? "遥控泊车进行中 🅿️" : "遥控泊车待命", active: isRpa, activeColor: .orange)
                    NIOAnimeBadge(text: tripShare > 0 ? "行程分享中 📍" : "行程分享关闭", active: tripShare > 0, activeColor: sakuraPink)
                    Spacer()
                    if let spd = ext?.speed, spd > 0 {
                        Text(verbatim: "\(Int(spd)) km/h")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(mintCyan)
                    }
                }
            }
        }
    }
}

// MARK: - 7. 🛞 萌爪胎压与温度监测

@MainActor
private struct NIOAnimeTyreGridCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }

    var body: some View {
        NIOAnimeCardContainer(
            title: "🛞 萌爪胎压与温度监测",
            icon: "circle.grid.cross.fill",
            colors: colors,
            jsonProvider: {
                if let direct = nioToJSON(status?.tyreStatus), !direct.isEmpty && direct != "{}" && direct != "{\n\n}" {
                    return direct
                }
                if let maint = nioToJSON(status?.maintainStatus), !maint.isEmpty && maint != "{}" {
                    return "/* maintain_status */\n" + maint
                }
                return nioToJSON(status) ?? "{\"tip\": \"暂无抓取到的原始数据\"}"
            },
            onShowJSON: onShowJSON
        ) {
            let tyre = NIOVehicleLib.extractTyreInfo(from: status)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tyreTile(pos: "左前轮", info: tyre.fl)
                    tyreTile(pos: "右前轮", info: tyre.fr)
                }
                HStack(spacing: 8) {
                    tyreTile(pos: "左后轮", info: tyre.rl)
                    tyreTile(pos: "右后轮", info: tyre.rr)
                }
            }
        }
    }

    @MainActor
    @ViewBuilder
    private func tyreTile(pos: String, info: NIOVehicleLib.TyreWheelInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pos)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                Spacer()
                Text("🐾")
                    .font(.system(size: 9))
            }
            HStack {
                Text(info.displayPress)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(info.press != nil ? mintCyan : NIOThemePaint.text.opacity(0.4))
                Spacer()
                if !info.displayTemp.isEmpty {
                    Text(info.displayTemp)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(sakuraPink)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NIOThemePaint.fill, lineWidth: 0.8))
    }
}

// MARK: - 8. 🌡️ 暖风座舱与超强干燥模式

@MainActor
private struct NIOAnimeCockpitCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        VStack(spacing: 12) {
            // 座舱温度与空调
            NIOAnimeCardContainer(
                title: "🌡️ 温暖座舱与超强干燥",
                icon: "sparkles.tv.fill",
                colors: colors,
                jsonProvider: { nioToJSON(status?.hvacStatus) },
                onShowJSON: onShowJSON
            ) {
                let hvac = status?.hvacStatus
                let heat = status?.heatingStatus ?? [:]
                let steer = heat["steer_wheel_heat_sts"]?.intValue ?? heat["steer_wheel_heating_sts"]?.intValue ?? 0
                let flHeat = heat["seat_heat_frnt_le_sts"]?.intValue ?? heat["seat_heat_front_left"]?.intValue ?? 0
                let frHeat = heat["seat_heat_frnt_ri_sts"]?.intValue ?? heat["seat_heat_front_right"]?.intValue ?? 0
                let seatHeat = max(flHeat, frHeat)

                let isDry = (hvac?.cbnHiTDrySts ?? 0) == 1
                let isDefrost = (hvac?.ccuMaxDefrstSts ?? 0) == 1
                let isAcMax = (hvac?.ccuAcmaxLampReq ?? 0) == 1
                let isHeatMax = (hvac?.ccuHeatgMaxLampReq ?? 0) == 1
                let isOvrHt = (hvac?.cbnOvrHtActSts ?? 0) == 1

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("车内温度")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            Text(verbatim: hvac?.temperature != nil ? String(format: "%.1f℃", hvac!.temperature!) : "—")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(mintCyan)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("车外温度")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            Text(verbatim: hvac?.outsideTemperature != nil ? String(format: "%.1f℃", hvac!.outsideTemperature!) : "—")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(lavenderDream)
                        }
                    }

                    HStack(spacing: 6) {
                        NIOAnimeBadge(text: hvac?.airConditionerOn == true ? "空调开启" : "空调关闭", active: hvac?.airConditionerOn == true, activeColor: mintCyan)
                        Spacer()
                        if steer > 0 {
                            NIOAnimeBadge(text: "方向盘加热 🔥", active: true, activeColor: pastelYellow)
                        }
                        if seatHeat > 0 {
                            NIOAnimeBadge(text: "前排加热 ♨️", active: true, activeColor: pastelYellow)
                        }
                    }

                    if isDry || isDefrost || isAcMax || isHeatMax || isOvrHt {
                        HStack(spacing: 6) {
                            if isDry {
                                NIOAnimeBadge(text: "高温超强干燥中 ♨️🌬️", active: true, activeColor: sakuraPink)
                            }
                            if isDefrost {
                                NIOAnimeBadge(text: "极速除霜 ❄️", active: true, activeColor: mintCyan)
                            }
                            if isAcMax {
                                NIOAnimeBadge(text: "极速制冷 🧊", active: true, activeColor: mintCyan)
                            }
                            if isHeatMax {
                                NIOAnimeBadge(text: "极速制热 🔥", active: true, activeColor: pastelYellow)
                            }
                            if isOvrHt {
                                NIOAnimeBadge(text: "座舱过热保护 🛡️", active: true, activeColor: sakuraPink)
                            }
                        }
                    }
                }
            }

            // 智能模式与安全
            NIOAnimeCardContainer(
                title: "🐾 车辆模式与安全结界",
                icon: "shield.lefthalf.filled",
                colors: colors,
                jsonProvider: { nioToJSON(status?.offcarModeStatus) },
                onShowJSON: onShowJSON
            ) {
                let offcar = status?.offcarModeStatus ?? [:]
                let defender = NIOVehicleLib.defenderModeActive(offcar)
                let pet = NIOVehicleLib.modeActive(offcar["pet_mode_status"] ?? offcar["pet_mode"])
                let camp = NIOVehicleLib.modeActive(offcar["camping_mode_status"] ?? offcar["camping_mode"] ?? offcar["camp_mode_status"])
                let powerHold = NIOVehicleLib.modeActive(offcar["power_hold_mode_status"] ?? offcar["power_hold_mode"] ?? offcar["offcar_power_hold"])
                let conn = status?.connectionStatus?.connected == true

                VStack(spacing: 8) {
                    HStack {
                        NIOAnimeBadge(text: defender.isActive ? "守卫开启 🛡️" : "守卫关闭", active: defender.isActive, activeColor: sakuraPink)
                        if defender.warnCount > 0 {
                            Text("🚨 \(defender.warnCount)次告警")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(sakuraPink)
                        }
                        Spacer()
                        if pet {
                            NIOAnimeBadge(text: "宠物模式 🐾", active: true, activeColor: pastelYellow)
                        } else if camp {
                            NIOAnimeBadge(text: "露营模式 ⛺️", active: true, activeColor: lavenderDream)
                        } else if powerHold {
                            NIOAnimeBadge(text: "离车不下电 🔋", active: true, activeColor: mintCyan)
                        } else {
                            NIOAnimeBadge(text: "标准驻车", active: false, activeColor: .secondary)
                        }
                    }

                    HStack {
                        Text("云端车控链路")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        Spacer()
                        NIOAnimeBadge(text: conn ? "在线 ☁️" : "离线 💤", active: conn, activeColor: .green)
                    }
                }
            }
        }
    }
}

// MARK: - 8.5 🪑 座椅舒适、加热通风与方向盘加热

@MainActor
private struct NIOAnimeSeatComfortCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let heat = status?.heatingStatus ?? [:]
        let steer = heat["steer_wheel_heat_sts"]?.intValue ?? heat["steer_wheel_heating_sts"]?.intValue ?? 0
        let flHeat = heat["seat_heat_frnt_le_sts"]?.intValue ?? heat["seat_heat_front_left"]?.intValue ?? 0
        let frHeat = heat["seat_heat_frnt_ri_sts"]?.intValue ?? heat["seat_heat_front_right"]?.intValue ?? 0
        let rlHeat = heat["seat_heat_re_le_sts"]?.intValue ?? heat["seat_heat_rear_left"]?.intValue ?? 0
        let rrHeat = heat["seat_heat_re_ri_sts"]?.intValue ?? heat["seat_heat_rear_right"]?.intValue ?? 0
        let flVent = heat["seat_vent_frnt_le_sts"]?.intValue ?? heat["seat_vent_front_left"]?.intValue ?? 0
        let frVent = heat["seat_vent_frnt_ri_sts"]?.intValue ?? heat["seat_vent_front_right"]?.intValue ?? 0
        let battPre = heat["hv_batt_pre_sts"]?.intValue == 1
        let battWarm = heat["btry_warm_up_sts"]?.intValue == 1

        let hasAnyComfort = steer > 0 || flHeat > 0 || frHeat > 0 || rlHeat > 0 || rrHeat > 0 || flVent > 0 || frVent > 0 || battPre || battWarm || !heat.isEmpty

        if hasAnyComfort {
            NIOAnimeCardContainer(
                title: "🪑 座椅舒适与方向盘加热",
                icon: "chair.lounge.fill",
                colors: colors,
                jsonProvider: { nioToJSON(status?.heatingStatus) },
                onShowJSON: onShowJSON
            ) {
                VStack(spacing: 8) {
                    // 2x2 座椅加热与通风状态矩阵
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        seatTile(
                            title: "主驾座椅",
                            heatLevel: flHeat,
                            ventLevel: flVent,
                            icon: "carseat.left.fill"
                        )
                        seatTile(
                            title: "副驾座椅",
                            heatLevel: frHeat,
                            ventLevel: frVent,
                            icon: "carseat.right.fill"
                        )
                        seatTile(
                            title: "二排左座",
                            heatLevel: rlHeat,
                            ventLevel: 0,
                            icon: "carseat.left.fill"
                        )
                        seatTile(
                            title: "二排右座",
                            heatLevel: rrHeat,
                            ventLevel: 0,
                            icon: "carseat.right.fill"
                        )
                    }

                    // 辅助加热与电池温控
                    HStack(spacing: 6) {
                        comfortPill(label: "方向盘加热", isOn: steer > 0, level: steer > 0 ? "\(steer)档" : nil, icon: "steeringwheel", color: pastelYellow)
                        comfortPill(label: "电池预热", isOn: battPre, level: battPre ? "开启" : nil, icon: "flame.fill", color: sakuraPink)
                        comfortPill(label: "电池保温", isOn: battWarm, level: battWarm ? "开启" : nil, icon: "thermometer.sun.fill", color: mintCyan)
                    }
                }
            }
        }
    }

    private func seatTile(title: String, heatLevel: Int, ventLevel: Int, icon: String) -> some View {
        let isHeat = heatLevel > 0
        let isVent = ventLevel > 0
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle((isHeat || isVent) ? (isHeat ? pastelYellow : mintCyan) : NIOThemePaint.text.opacity(0.35))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                HStack(spacing: 4) {
                    if isHeat {
                        Text("🔥 \(heatLevel)档加热")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(pastelYellow)
                    }
                    if isVent {
                        Text("💨 \(ventLevel)档通风")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(mintCyan)
                    }
                    if !isHeat && !isVent {
                        Text("未开启")
                            .font(.system(size: 8))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                    }
                }
            }
            Spacer()
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(isHeat ? pastelYellow.opacity(0.1) : (isVent ? mintCyan.opacity(0.1) : NIOThemePaint.well.opacity(0.4))))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((isHeat || isVent) ? (isHeat ? pastelYellow.opacity(0.3) : mintCyan.opacity(0.3)) : NIOThemePaint.fill.opacity(0.2), lineWidth: 0.5))
    }

    private func comfortPill(label: String, isOn: Bool, level: String?, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 8, weight: isOn ? .bold : .medium))
            if let lvl = level {
                Text(lvl)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.3))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(isOn ? color.opacity(0.18) : NIOThemePaint.well.opacity(0.4))
        .foregroundStyle(isOn ? color : NIOThemePaint.text.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn ? color.opacity(0.4) : Color.clear, lineWidth: 0.5))
    }
}

// MARK: - 8.6 🔑 智能钥匙感知与低压电瓶健康

@MainActor
private struct NIOAnimeKeySensorsCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let key = status?.keyStatus ?? [:]
        let lvBatt = status?.lvBattStatus ?? [:]
        let peUnlock = key["pe_unlock_status"]?.intValue == 1 || key["smart_key_near"]?.intValue == 1
        let handleSensor = key["handle_sensor_status"]?.intValue == 1 || key["door_handle_sensor"]?.intValue == 1
        let lvSoc = lvBatt["lv_batt_soc"]?.intValue
        let lvVolt = lvBatt["lv_batt_volt"]?.numberValue ?? lvBatt["lv_batt_voltage"]?.numberValue

        NIOAnimeCardContainer(
            title: "🔑 钥匙感知与低压供电系统",
            icon: "key.fill",
            colors: colors,
            jsonProvider: {
                if let direct = nioToJSON(status?.lvBattStatus), !direct.isEmpty && direct != "{}" {
                    return "/* lv_batt_status */\n" + direct + "\n\n/* key_status */\n" + (nioToJSON(status?.keyStatus) ?? "{}")
                }
                return nioToJSON(status?.keyStatus) ?? "{}"
            },
            onShowJSON: onShowJSON
        ) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("蓝牙靠近解锁")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        HStack(spacing: 4) {
                            Image(systemName: peUnlock ? "antenna.radiowaves.left.and.right" : "lock.fill")
                                .font(.system(size: 10))
                            Text(peUnlock ? "已感应" : "待命中")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(peUnlock ? mintCyan : NIOThemePaint.text.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(NIOThemePaint.well.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("隐藏门把手感应")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        HStack(spacing: 4) {
                            Image(systemName: handleSensor ? "hand.tap.fill" : "hand.raised.fill")
                                .font(.system(size: 10))
                            Text(handleSensor ? "已伸出/感应" : "收纳锁止")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(handleSensor ? pastelYellow : NIOThemePaint.text.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(NIOThemePaint.well.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("12V 辅助蓄电池")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        HStack(spacing: 3) {
                            if let soc = lvSoc {
                                Text("\(soc)%")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(soc > 40 ? mintCyan : sakuraPink)
                                if let volt = lvVolt {
                                    Text(verbatim: "\(String(format: "%.1f", volt))V")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                                }
                            } else {
                                Text("待抓包同步")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(NIOThemePaint.well.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if lvSoc == nil && key.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 8))
                        Text("当前为 Widget 动态模式，手机打开蔚来 App 下拉刷新即可捕获全量 12V 电瓶与钥匙遥测")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - 9. 🧊 车载智能冰箱与座舱空气健康

@MainActor
private struct NIOAnimeCabinExtrasCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let frdg = status?.frdgStatus ?? [:]
        let frdgPower = frdg["frdg_pwr_sts"]?.intValue == 1
        let frdgCurT = frdg["frdg_cur_t"]?.numberValue
        let frdgTarT = frdg["frdg_tar_t"]?.numberValue
        let special = status?.specialStatus ?? [:]
        let pm25Inside = special["pm25_inside"]?.numberValue ?? special["air_quality_inside"]?.numberValue
        let pm25Outside = special["pm25_outside"]?.numberValue ?? special["air_quality_outside"]?.numberValue

        if frdgPower || frdgCurT != nil || pm25Inside != nil || pm25Outside != nil {
            NIOAnimeCardContainer(
                title: "🧊 车载智能冰箱与空气健康",
                icon: "snowflake.circle.fill",
                colors: colors,
                jsonProvider: { nioToJSON(status?.frdgStatus) },
                onShowJSON: onShowJSON
            ) {
                VStack(spacing: 8) {
                    HStack {
                        // 冰箱状态
                        VStack(alignment: .leading, spacing: 2) {
                            Text("车载智能冰箱")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            HStack(spacing: 4) {
                                Text(frdgPower ? "开启中 ❄️" : "已关闭 💤")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(frdgPower ? mintCyan : NIOThemePaint.text.opacity(0.6))
                                if let cur = frdgCurT {
                                    Text(verbatim: "\(String(format: "%.0f", cur))℃")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundStyle(sakuraPink)
                                }
                                if let tar = frdgTarT {
                                    Text("(设定 \(Int(tar))℃)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                }
                            }
                        }

                        Spacer()

                        // 空气质量
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("座舱 PM2.5")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            HStack(spacing: 4) {
                                if let inPm = pm25Inside {
                                    Text(verbatim: "\(String(format: "%.0f", inPm)) μg/m³")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundStyle(inPm < 35 ? .green : (inPm < 75 ? pastelYellow : sakuraPink))
                                } else {
                                    Text("清新优良 🌿")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 9.5 📦 储物空间与行李箱状态

@MainActor
private struct NIOAnimeStorageBoxCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        let box = status?.boxStatus ?? [:]
        let doors = status?.doorStatus ?? [:]
        let isBoxOpen = box["box_open"]?.boolValue == true || box["box_open"]?.intValue == 1
        let isBoxLock = box["box_lock"]?.boolValue == true || box["box_lock"]?.intValue == 1
        let hoodRaw = doors["engine_hood_ajar_status"]?.intValue ?? doors["engine_hood_sts"]?.intValue ?? doors["hood"]?.intValue
        let hoodOpen = (hoodRaw != nil && hoodRaw != 1)
        let trunkRaw = doors["tailgate_ajar_status"]?.intValue ?? doors["tailgate_sts"]?.intValue ?? doors["trunk"]?.intValue
        let trunkOpen = (trunkRaw != nil && trunkRaw != 1)

        if isBoxOpen || isBoxLock || hoodOpen || trunkOpen || !box.isEmpty {
            NIOAnimeCardContainer(
                title: "📦 储物空间与行李箱状态",
                icon: "archivebox.fill",
                colors: colors,
                jsonProvider: { nioToJSON(status?.boxStatus) },
                onShowJSON: onShowJSON
            ) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        storageTile(
                            title: "前备箱/前舱盖",
                            statusText: hoodOpen ? "已打开 ⚠️" : "已闭锁 🔒",
                            isOpen: hoodOpen,
                            icon: hoodOpen ? "car.side.front.open.fill" : "car.side.fill"
                        )
                        storageTile(
                            title: "后备箱/电动尾门",
                            statusText: trunkOpen ? "已开启 ⚠️" : "已锁好 🔒",
                            isOpen: trunkOpen,
                            icon: trunkOpen ? "car.side.rear.open.fill" : "car.side.fill"
                        )
                        storageTile(
                            title: "中控密码手套箱",
                            statusText: isBoxOpen ? "已开启 🔓" : (isBoxLock ? "密码锁定 🔒" : "关闭已上锁"),
                            isOpen: isBoxOpen,
                            icon: "lock.square.stack.fill"
                        )
                    }
                }
            }
        }
    }

    private func storageTile(title: String, statusText: String, isOpen: Bool, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 8))
            }
            .foregroundStyle(NIOThemePaint.text.opacity(0.6))

            Text(statusText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOpen ? sakuraPink : mintCyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 10. 💡 车外灯光与照明系统 (拟物化与语义重构)

@MainActor
private struct NIOAnimeLightsCard: View {
    let status: NIOVehicleStatus?
    let colors: NIOAnimeColors
    let onShowJSON: (String?, String?) -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    var body: some View {
        if let lights = status?.lightStatus, !lights.isEmpty {
            let dipped = lights["dipped_beam_status"]?.intValue == 1
            let main = lights["main_beam_status"]?.intValue == 1
            let position = lights["position_light_status"]?.intValue == 1
            let hazard = lights["hazard_light_status"]?.intValue == 1
            let anyOn = dipped || main || position || hazard

            NIOAnimeCardContainer(
                title: "💡 车外灯光与照明系统",
                icon: "lightbulb.2.fill",
                colors: colors,
                jsonProvider: { nioToJSON(status?.lightStatus) },
                onShowJSON: onShowJSON
            ) {
                VStack(spacing: 10) {
                    // 1. 全局状态总览横幅
                    HStack(spacing: 8) {
                        if hazard {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("危险警报双闪开启中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                        } else if main {
                            Image(systemName: "headlight.high.beam.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.black)
                            Text("远光大灯照明中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black)
                        } else if dipped {
                            Image(systemName: "headlight.low.beam.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.black)
                            Text("近光大灯照明中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black)
                        } else if position {
                            Image(systemName: "lightbulb.2.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("示廓位置灯点亮中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                        } else {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(mintCyan)
                            Text("全车灯光已熄灭 · 安全驻车")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                        }
                        Spacer()
                        Text(anyOn ? "灯光开启中" : "全部熄灭")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(
                                    anyOn
                                        ? (hazard ? Color.red.opacity(0.8) : (main ? pastelYellow : mintCyan))
                                        : NIOThemePaint.well
                                )
                            )
                            .foregroundStyle(anyOn ? (hazard ? Color.white : Color.black) : NIOThemePaint.text.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                hazard
                                    ? Color.red.opacity(0.85)
                                    : (main
                                        ? pastelYellow.opacity(0.85)
                                        : (dipped
                                            ? mintCyan.opacity(0.85)
                                            : (position
                                                ? lavenderDream.opacity(0.85)
                                                : NIOThemePaint.well.opacity(0.6))))
                            )
                    )

                    // 2. 2x2 拟物化车灯矩阵网格
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        lightTile(
                            name: "近光大灯",
                            icon: "headlight.low.beam.fill",
                            isOn: dipped,
                            activeColor: mintCyan,
                            onLabel: "已开启 (照明中)",
                            offLabel: "已熄灭"
                        )
                        lightTile(
                            name: "远光大灯",
                            icon: "headlight.high.beam.fill",
                            isOn: main,
                            activeColor: pastelYellow,
                            onLabel: "已开启 (高亮远射)",
                            offLabel: "已熄灭"
                        )
                        lightTile(
                            name: "示廓位置灯",
                            icon: "lightbulb.2.fill",
                            isOn: position,
                            activeColor: lavenderDream,
                            onLabel: "已开启 (示宽中)",
                            offLabel: "已熄灭"
                        )
                        lightTile(
                            name: "危险报警双闪",
                            icon: "exclamationmark.triangle.fill",
                            isOn: hazard,
                            activeColor: sakuraPink,
                            onLabel: "警报闪烁中",
                            offLabel: "已关闭 (安全)"
                        )
                    }
                }
            }
        }
    }

    private func lightTile(name: String, icon: String, isOn: Bool, activeColor: Color, onLabel: String, offLabel: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isOn ? activeColor : NIOThemePaint.well)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOn ? Color.black : NIOThemePaint.text.opacity(0.35))
            }
            .shadow(color: isOn ? activeColor.opacity(0.5) : Color.clear, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isOn ? NIOThemePaint.text : NIOThemePaint.text.opacity(0.6))
                Text(isOn ? onLabel : offLabel)
                    .font(.system(size: 8, weight: isOn ? .bold : .regular))
                    .foregroundStyle(isOn ? activeColor : NIOThemePaint.text.opacity(0.4))
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? activeColor.opacity(0.12) : NIOThemePaint.well.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isOn ? activeColor.opacity(0.4) : NIOThemePaint.fill.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 🗺️ 每日行驶轨迹地图卡片

@MainActor
private struct NIOAnimeDailyPathCard: View {
    let dailyPaths: [NIODailyPath]
    let colors: NIOAnimeColors

    @State private var selectedDayIndex: Int = 0

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        if !dailyPaths.isEmpty {
            let currentDayIndex = min(selectedDayIndex, dailyPaths.count - 1)
            let activePath = dailyPaths[currentDayIndex]

            NIOAnimeCardContainer(
                title: "🗺️ 每日行驶轨迹地图",
                icon: "map.fill",
                colors: colors
            ) {
                VStack(spacing: 10) {
                    // 日期选择切换
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(dailyPaths.prefix(7).enumerated()), id: \.element.id) { idx, dp in
                                Button(action: {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedDayIndex = idx
                                    }
                                }) {
                                    Text(dp.label)
                                        .font(.system(size: 10, weight: selectedDayIndex == idx ? .bold : .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(
                                                selectedDayIndex == idx
                                                    ? LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
                                                    : LinearGradient(colors: [NIOThemePaint.well, NIOThemePaint.well], startPoint: .leading, endPoint: .trailing)
                                            )
                                        )
                                        .foregroundStyle(selectedDayIndex == idx ? Color.white : NIOThemePaint.text.opacity(0.6))
                                }
                            }
                        }
                    }

                    // 地图组件
                    pathMapView(activePath.points)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NIOThemePaint.fill, lineWidth: 1)
                        )

                    // 当日行驶统计指标
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当日行驶里程")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                            Text(String(format: "%.1f km", activePath.distanceKm))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(mintCyan)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("轨迹采样时间")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                            Text("\(NIOVehicleLib.fmtClock(activePath.startTime)) ~ \(NIOVehicleLib.fmtClock(activePath.endTime))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private func pathMapView(_ points: [NIOVehicleSnapshot]) -> some View {
        let coords = points.compactMap { snap -> CLLocationCoordinate2D? in
            guard snap.isValidGPS else { return nil }
            return CLLocationCoordinate2D(latitude: snap.lat, longitude: snap.lng)
        }
        guard !coords.isEmpty else {
            return AnyView(
                ZStack {
                    NIOThemePaint.well
                    Text("暂无有效 GPS 行驶轨迹坐标")
                        .font(.system(size: 11))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                }
            )
        }
        return AnyView(
            NIOPathMapView(
                coordinates: coords,
                strokeColor: UIColor(sakuraPink)
            )
        )
    }
}

// MARK: - 🗺️ iOS 原生地图轨迹渲染包装器 (支持 iOS 16+)

private struct NIOPathMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let strokeColor: UIColor

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.layer.cornerRadius = 12
        mapView.clipsToBounds = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        guard !coordinates.isEmpty else { return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)

        if let first = coordinates.first {
            let startAnn = MKPointAnnotation()
            startAnn.coordinate = first
            startAnn.title = "起点"
            mapView.addAnnotation(startAnn)
        }
        if let last = coordinates.last, coordinates.count > 1 {
            let endAnn = MKPointAnnotation()
            endAnn.coordinate = last
            endAnn.title = "终点"
            mapView.addAnnotation(endAnn)
        }

        let rect = polyline.boundingMapRect
        let edgePadding = UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(strokeColor: strokeColor)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let strokeColor: UIColor

        init(strokeColor: UIColor) {
            self.strokeColor = strokeColor
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = strokeColor
                renderer.lineWidth = 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "NIOPathPin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = false
            } else {
                view?.annotation = annotation
            }
            if annotation.title == "起点" {
                view?.markerTintColor = UIColor.systemTeal
                view?.glyphImage = UIImage(systemName: "flag.fill")
            } else {
                view?.markerTintColor = UIColor.systemPink
                view?.glyphImage = UIImage(systemName: "flag.checkered")
            }
            return view
        }
    }
}

// MARK: - 📈 历史趋势与多维图表卡片

private struct TrendPoint: Identifiable {
    let id = UUID()
    let idx: Int
    let value: Double
}

@MainActor
private struct NIOAnimeTrendChartsCard: View {
    let history: [NIOVehicleSnapshot]
    let dailyDeltas: [NIODailyDelta]
    let colors: NIOAnimeColors

    @State private var trendPreset: Int = 60

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        let recent = Array(history.suffix(trendPreset))
        if !recent.isEmpty {
            NIOAnimeCardContainer(
                title: "📈 历史趋势与多维分析",
                icon: "chart.xyaxis.line",
                colors: colors
            ) {
                VStack(spacing: 12) {
                    // 时间范围选择
                    HStack {
                        Text("采样点: \(recent.count) 条")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach([30, 60, 180, 500], id: \.self) { p in
                                Button(action: {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        trendPreset = p
                                    }
                                }) {
                                    Text("\(p)")
                                        .font(.system(size: 9, weight: trendPreset == p ? .bold : .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule().fill(
                                                trendPreset == p
                                                    ? LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
                                                    : LinearGradient(colors: [NIOThemePaint.well, NIOThemePaint.well], startPoint: .leading, endPoint: .trailing)
                                            )
                                        )
                                        .foregroundStyle(trendPreset == p ? Color.white : NIOThemePaint.text.opacity(0.6))
                                }
                            }
                        }
                    }

                    socChart(recent)
                    dailyDeltaChart(dailyDeltas)
                    mileageChart(recent)
                }
            }
        }
    }

    private func socChart(_ data: [NIOVehicleSnapshot]) -> some View {
        let points = data.enumerated().map { idx, snap in
            TrendPoint(idx: idx, value: snap.soc)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("电量趋势 (%)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                Spacer()
                if let last = points.last {
                    Text(String(format: "当前 %.1f%%", last.value))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(mintCyan)
                }
            }
            Chart(points) { p in
                LineMark(x: .value("序号", p.idx), y: .value("电量", p.value))
                    .foregroundStyle(mintCyan)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("序号", p.idx), y: .value("电量", p.value))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [mintCyan.opacity(0.35), mintCyan.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .chartYScale(domain: 0...100)
            .frame(height: 70)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(NIOThemePaint.well.opacity(0.5)))
    }

    private func dailyDeltaChart(_ deltas: [NIODailyDelta]) -> some View {
        guard !deltas.isEmpty else { return AnyView(EmptyView()) }
        let recentDeltas = Array(deltas.suffix(14))
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("近 14 日增里程 (km)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                Chart(recentDeltas) { d in
                    BarMark(x: .value("日期", d.label), y: .value("增量", d.delta))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [sakuraPink, lavenderDream],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(3)
                }
                .frame(height: 65)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(NIOThemePaint.well.opacity(0.5)))
        )
    }

    private func mileageChart(_ data: [NIOVehicleSnapshot]) -> some View {
        let points = data.enumerated().map { idx, snap in
            TrendPoint(idx: idx, value: snap.mileage)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("总里程累计趋势 (km)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                Spacer()
                if let last = points.last {
                    Text(String(format: "%.1f km", last.value))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(lavenderDream)
                }
            }
            Chart(points) { p in
                LineMark(x: .value("序号", p.idx), y: .value("里程", p.value))
                    .foregroundStyle(lavenderDream)
                    .interpolationMethod(.monotone)
            }
            .frame(height: 65)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(NIOThemePaint.well.opacity(0.5)))
    }
}

// MARK: - 11. ⚡️ 远程车控与快捷指令中心

@MainActor
private struct NIOAnimeRemoteControlCard: View {
    let colors: NIOAnimeColors

    private var sakuraPink: Color { colors.sakuraPink }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        NIOAnimeCardContainer(title: "⚡️ 远程智能车控与互联", icon: "bolt.horizontal.circle.fill", colors: colors) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        NIOVehicleLib.openNIOApp()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text("直达蔚来 App 远程车控")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: sakuraPink.opacity(0.3), radius: 4)
                    }
                }

                HStack {
                    Text("💡 提示：蔚来远程无钥匙启动与车门解锁需 TSP 动态硬件 ECDSA 签名及 6 位服务 PIN 码，属于最高安全级指令，建议通过官方链路快捷操作。")
                        .font(.system(size: 9))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                        .lineSpacing(2)
                }
            }
        }
    }
}

// MARK: - 12. 📑 换电站足迹与财务大屏

@MainActor
private struct NIOAnimeOrdersCard: View {
    let summary: NIOServiceSummary?
    let colors: NIOAnimeColors

    @State private var selectedFilter: String = "all"
    @State private var showAllOrders: Bool = false
    @State private var expandedOrderNo: String? = nil

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }
    private var pastelYellow: Color { colors.pastelYellow }

    private let filterCategories: [(id: String, name: String, icon: String)] = [
        ("all", "全部", "tray.full.fill"),
        ("pe_shaman_change", "换电", "arrow.triangle.2.circlepath"),
        ("pe_shaman", "充电", "bolt.fill"),
        ("battery_flexible_upgrade", "灵活升级", "battery.100percent.bolt"),
        ("nsom_so_maintenance", "维保", "wrench.and.screwdriver.fill"),
        ("nsom_so_chauffeur", "驾享", "person.crop.circle.fill.badge.checkmark"),
        ("service_pe_discharge", "放电", "bolt.badge.automatic.fill"),
        ("chauffeur_vehicle_delivery", "送车", "car.side.fill"),
        ("so_case_accident", "事故", "exclamationmark.shield.fill"),
    ]

    var body: some View {
        if let summary = summary, !summary.orders.isEmpty {
            let filteredOrders: [NIOServiceOrder] = {
                if selectedFilter == "all" { return summary.orders }
                return summary.orders.filter { $0.orderType == selectedFilter }
            }()
            let displayOrders = showAllOrders ? filteredOrders : Array(filteredOrders.prefix(5))

            NIOAnimeCardContainer(title: "📑 蔚来服务订单与财务大屏 (\(summary.total)单)", icon: "newspaper.fill", colors: colors) {
                VStack(spacing: 10) {
                    // 1. 核心历史累计统计
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("累计换电")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(summary.swapCompleted)")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundStyle(mintCyan)
                                Text("次")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(mintCyan)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("换电总支出")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            Text(NIOOrderLib.fmtMoney(summary.swapSpent))
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundStyle(sakuraPink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("单次均价")
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            Text(NIOOrderLib.fmtMoney(summary.swapAvgSpent))
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundStyle(pastelYellow)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 2. 电池灵活升级（若有）
                    if summary.upgradeCount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("🔋 电池灵活升级")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(lavenderDream)
                                Text("日租 \(summary.upgradeDayCount) 天 · 月租 \(summary.upgradeMonthCount) 天")
                                    .font(.system(size: 8))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                            }
                            Spacer()
                            Text("\(summary.upgradeCompleted) 笔完成 · " + NIOOrderLib.fmtMoney(summary.upgradeSpent))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(mintCyan)
                        }
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // 3. 月度换电次数与总支出统计卡片 (支持多月水平滑动)
                    if !summary.monthlyStats.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("📅 月度换电与消费支出趋势")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(lavenderDream)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(summary.monthlyStats) { m in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(m.label)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                                            HStack(spacing: 8) {
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text("换电")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                                    Text("\(m.swapCount)次")
                                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                                        .foregroundStyle(mintCyan)
                                                }
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text("换电支出")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                                    Text(NIOOrderLib.fmtMoney(m.swapSpent))
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                        .foregroundStyle(sakuraPink)
                                                }
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text("全服务总额")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                                    Text(NIOOrderLib.fmtMoney(m.totalSpent))
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                        .foregroundStyle(pastelYellow)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(NIOThemePaint.fill)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(mintCyan.opacity(0.2), lineWidth: 0.8))
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 4. 8 大服务类型水平筛选胶囊栏
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(filterCategories, id: \.id) { cat in
                                let count: Int = {
                                    if cat.id == "all" { return summary.orders.count }
                                    return summary.orders.filter { $0.orderType == cat.id }.count
                                }()
                                if count > 0 || cat.id == "all" {
                                    Button(action: {
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedFilter = cat.id
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 9))
                                            Text(cat.name)
                                                .font(.system(size: 10, weight: selectedFilter == cat.id ? .bold : .medium))
                                            Text("\(count)")
                                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(selectedFilter == cat.id ? mintCyan.opacity(0.35) : NIOThemePaint.stroke)
                                                .clipShape(Capsule())
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(selectedFilter == cat.id ? LinearGradient(colors: [sakuraPink.opacity(0.8), lavenderDream.opacity(0.8)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [NIOThemePaint.fill, NIOThemePaint.fill], startPoint: .leading, endPoint: .trailing))
                                        .foregroundStyle(selectedFilter == cat.id ? Color.white : NIOThemePaint.text)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(selectedFilter == cat.id ? mintCyan.opacity(0.6) : NIOThemePaint.stroke, lineWidth: 0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // 5. Top 常用换电站排行 (最多 5 个，带进度条)
                    if (selectedFilter == "all" || selectedFilter == "pe_shaman_change") && !summary.topSwapStations.isEmpty {
                        let maxCount = summary.topSwapStations.map(\.count).max() ?? 1
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("🏆 常用换电站 Top \(min(5, summary.topSwapStations.count))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(mintCyan)
                                Spacer()
                                Text("换电足迹")
                                    .font(.system(size: 8))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                            }

                            ForEach(Array(summary.topSwapStations.prefix(5).enumerated()), id: \.element.name) { idx, st in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("\(idx + 1). \(st.name)")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(NIOThemePaint.text.opacity(0.9))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(st.count)次 · \(NIOOrderLib.fmtMoney(st.spent))")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundStyle(lavenderDream)
                                    }
                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(NIOThemePaint.well)
                                            Capsule()
                                                .fill(LinearGradient(colors: [mintCyan, sakuraPink], startPoint: .leading, endPoint: .trailing))
                                                .frame(width: max(4, g.size.width * CGFloat(st.count) / CGFloat(maxCount)))
                                        }
                                    }
                                    .frame(height: 3)
                                }
                            }
                        }
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider().background(NIOThemePaint.stroke)

                    // 6. 订单明细列表 (带折叠/展开与详情手风琴)
                    if displayOrders.isEmpty {
                        Text("暂无该类型的服务订单 🍃")
                            .font(.system(size: 10))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(displayOrders) { order in
                                let isExpanded = (expandedOrderNo == order.orderNo)
                                Button(action: {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedOrderNo = (isExpanded ? nil : order.orderNo)
                                    }
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(NIOOrderLib.orderTypeLabel(order))
                                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                                        .foregroundStyle(NIOThemePaint.text)
                                                    Text(NIOOrderLib.fmtSwapDate(order.createTime))
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                                                }
                                                Text(order.resourceAddress ?? order.address ?? order.orderNo ?? "—")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(order.orderStatusName ?? "—")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(sakuraPink.opacity(0.18))
                                                    .foregroundStyle(sakuraPink)
                                                    .clipShape(Capsule())
                                                if let cash = order.priceCash, let amt = Double(cash), amt > 0 {
                                                    Text(verbatim: "¥\(String(format: "%.2f", amt))")
                                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                        .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                                                }
                                            }
                                        }

                                        // 展开手风琴详细明细
                                        if isExpanded {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Divider().background(NIOThemePaint.stroke.opacity(0.5))
                                                if let no = order.orderNo, !no.isEmpty {
                                                    HStack {
                                                        Text("订单编号:")
                                                            .font(.system(size: 8))
                                                            .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                                        Text(no)
                                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                                            .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                                                    }
                                                }
                                                if let addr = order.resourceAddress ?? order.address, !addr.isEmpty {
                                                    HStack {
                                                        Text("服务地址:")
                                                            .font(.system(size: 8))
                                                            .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                                        Text(addr)
                                                            .font(.system(size: 8))
                                                            .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                                                    }
                                                }
                                            }
                                            .padding(.top, 2)
                                        }
                                    }
                                    .padding(6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(isExpanded ? NIOThemePaint.well.opacity(0.6) : Color.clear))
                                }
                                .buttonStyle(.plain)

                                if order.id != displayOrders.last?.id {
                                    Divider().background(NIOThemePaint.fill)
                                }
                            }

                            // 展开/收起更多订单按钮
                            if filteredOrders.count > 5 {
                                Button(action: {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAllOrders.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: showAllOrders ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                        Text(showAllOrders ? "收起订单列表" : "查看全部 \(filteredOrders.count) 笔订单")
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(NIOThemePaint.well)
                                    .foregroundStyle(mintCyan)
                                    .clipShape(Capsule())
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 13. 📅 每日签到卡片

@MainActor
private struct NIOAnimeCheckinCard: View {
    let checkinData: NIOCheckinData?
    let colors: NIOAnimeColors
    var onCheckin: (() -> Void)? = nil

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var pastelYellow: Color { colors.pastelYellow }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        if let ci = checkinData {
            NIOAnimeCardContainer(title: "📅 蔚来 App 社区签到与积分", icon: "calendar.badge.checkmark", colors: colors) {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: ci.checkedIn ? [Color.green.opacity(0.3), mintCyan.opacity(0.2)] : [sakuraPink.opacity(0.3), pastelYellow.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)

                            Image(systemName: ci.checkedIn ? "checkmark.seal.fill" : "gift.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(ci.checkedIn ? Color.green : pastelYellow)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(ci.checkedIn ? "今日已成功签到 🎉" : "今日尚未签到 ⏰")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(ci.checkedIn ? Color.green : pastelYellow)
                                Spacer()
                                NIOAnimeBadge(text: ci.checkedIn ? "已领积分 ✨" : "待领取 🎁", active: ci.checkedIn, activeColor: ci.checkedIn ? .green : sakuraPink)
                            }

                            HStack(spacing: 4) {
                                Text("🔥 已连续签到")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.65))
                                Text("\(ci.continuousDays)")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(mintCyan)
                                Text("天")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.65))
                            }
                        }
                    }

                    if !ci.checkedIn {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            onCheckin?()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("立即打卡签到领取积分")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - 14. 📈 能耗达成率与百公里电耗评分

@MainActor
private struct NIOAnimeEfficiencyCard: View {
    let socStatus: NIOSocStatus?
    let colors: NIOAnimeColors

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var pastelYellow: Color { colors.pastelYellow }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        let nominal = socStatus?.remainingRange
        let actual = socStatus?.remainingActualRange
        if let score = NIOEfficiencyLib.computeScore(nominalRange: nominal, actualRange: actual) {
            NIOAnimeCardContainer(title: "📈 驾驶能耗达成率与电耗评分", icon: "chart.line.uptrend.xyaxis.circle.fill", colors: colors) {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // 勋章徽章
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [mintCyan.opacity(0.35), pastelYellow.opacity(0.25)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)

                            Image(systemName: score.icon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(score.grade.contains("S") ? pastelYellow : mintCyan)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(score.title)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(NIOThemePaint.text)
                                Spacer()
                                Text(score.grade)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(pastelYellow.opacity(0.25))
                                    .foregroundStyle(pastelYellow)
                                    .clipShape(Capsule())
                            }

                            Text(score.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.65))
                                .lineLimit(1)
                        }
                    }

                    // 达成率数值与百公里电耗
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前实估达成率")
                                .font(.system(size: 8))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                            Text(verbatim: "\(String(format: "%.1f", score.achievementRate))%")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(mintCyan)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("推算百公里能耗")
                                .font(.system(size: 8))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(verbatim: String(format: "%.1f", score.estimatedKwhPer100Km))
                                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(sakuraPink)
                                Text("kWh")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(sakuraPink.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(NIOThemePaint.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // 达成率进度条
                    VStack(alignment: .leading, spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(NIOThemePaint.stroke)
                                Capsule()
                                    .fill(LinearGradient(colors: [mintCyan, pastelYellow], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(8, geo.size.width * CGFloat(min(1.0, score.achievementRate / 100.0))))
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text("标称 \(Int(nominal ?? 0)) km")
                                .font(.system(size: 8))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                            Spacer()
                            Text("实估 \(Int(actual ?? 0)) km")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(mintCyan)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 15. 🔧 维保周期与耗材寿命追踪

@MainActor
private struct NIOAnimeMaintenanceCard: View {
    let mileage: Double?
    let orders: [NIOServiceOrder]
    let colors: NIOAnimeColors

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var pastelYellow: Color { colors.pastelYellow }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        let currentKm = mileage ?? 0.0
        let report = NIOMaintenanceTracker.generateReport(currentMileage: currentKm, orders: orders)

        NIOAnimeCardContainer(title: "🔧 爱车维保周期与耗材寿命", icon: "wrench.and.screwdriver.fill", colors: colors) {
            VStack(spacing: 10) {
                // 顶部：整车健康评分 + 上次维保记录
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全车健康评分")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(report.overallHealthScore)")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(mintCyan)
                            Text("分 优良")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(mintCyan)
                        }
                    }
                    .padding(8)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("上次维保 · \(report.lastServiceDate)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(lavenderDream)
                        Text(report.lastServiceStation)
                            .font(.system(size: 8))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            .lineLimit(1)
                        if report.totalCount > 0 {
                            Text("累计 \(report.totalCount) 次维保 · " + NIOOrderLib.fmtMoney(report.totalSpent))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // 耗材进度条列表
                VStack(spacing: 8) {
                    ForEach(report.items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(item.isUrgent ? sakuraPink : mintCyan)
                                Text(item.name)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NIOThemePaint.text)
                                Spacer()
                                Text(item.statusDesc)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(item.isUrgent ? sakuraPink : (item.healthPercentage > 60 ? mintCyan : pastelYellow))
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(NIOThemePaint.fill)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: item.isUrgent ? [sakuraPink, .red] : (item.healthPercentage > 60 ? [mintCyan, .cyan] : [pastelYellow, sakuraPink]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(4, geo.size.width * CGFloat(min(1.0, item.healthPercentage / 100.0))))
                                }
                            }
                            .frame(height: 4)

                            HStack {
                                Text("剩余约 \(Int(item.remainingKm)) km")
                                    .font(.system(size: 8))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                                Spacer()
                                Text("约 \(item.remainingDays) 天")
                                    .font(.system(size: 8))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - 16. 📜 抓包请求与运行日志

@MainActor
private struct NIOAnimeFetchLogCard: View {
    let logs: [NIOFetchLogEntry]
    let colors: NIOAnimeColors
    let onViewAllLogs: () -> Void

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        NIOAnimeCardContainer(
            title: "📜 抓包请求与运行诊断（\(logs.count)）",
            icon: "doc.text.magnifyingglass",
            colors: colors,
            jsonProvider: { nioToJSON(logs) }
        ) {
            VStack(spacing: 8) {
                if logs.isEmpty {
                    Text("暂无网络请求日志")
                        .font(.system(size: 10))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                } else {
                    VStack(spacing: 6) {
                        ForEach(logs.prefix(3)) { log in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(log.level == "error" ? sakuraPink : (log.statusCode == 200 ? mintCyan : lavenderDream))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(log.category.uppercased())
                                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                            .foregroundStyle(mintCyan)
                                        if let code = log.statusCode {
                                            Text("\(code)")
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(code == 200 ? mintCyan : sakuraPink)
                                        }
                                        Spacer()
                                        Text(NIOVehicleLib.fmtTime(Int(log.timestamp.timeIntervalSince1970 * 1000)))
                                            .font(.system(size: 8))
                                            .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                                    }
                                    Text(log.message)
                                        .font(.system(size: 9))
                                        .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                            .padding(6)
                            .background(NIOThemePaint.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onViewAllLogs()
                    }) {
                        HStack(spacing: 4) {
                            Text("查看全部 \(logs.count) 条诊断抓包日志")
                                .font(.system(size: 10, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(mintCyan.opacity(0.15))
                        .foregroundStyle(mintCyan)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(mintCyan.opacity(0.3), lineWidth: 0.5))
                    }
                }
            }
        }
    }
}

// MARK: - 顶部导航栏配件

@MainActor
private struct NIOAnimeBrandBadge: View {
    let colors: NIOAnimeColors

    private var sakuraPink: Color { colors.sakuraPink }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        HStack(spacing: 6) {
            // 萌动发光双层 Logo 圈
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [sakuraPink.opacity(0.4), lavenderDream.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)

                Circle()
                    .fill(NIOThemePaint.stroke)
                    .frame(width: 22, height: 22)

                Image("NIO_brand")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .clipShape(Circle())
            }
            .overlay(
                Circle()
                    .stroke(sakuraPink.opacity(0.7), lineWidth: 1)
            )

            Text("蔚来 · 兔可可")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [NIOThemePaint.text, sakuraPink.opacity(0.95)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("🌸")
                .font(.system(size: 10))
        }
        .padding(.leading, 3)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(NIOThemePaint.chipFill)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [sakuraPink.opacity(0.55), lavenderDream.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: sakuraPink.opacity(0.25), radius: 4)
        .fixedSize(horizontal: true, vertical: true)
    }
}

@MainActor
private struct NIOAnimeDashboardActions: View {
    let colors: NIOAnimeColors
    let isLiveActivityActive: Bool
    let isLoadingVehicle: Bool
    let onToggleLiveActivity: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @State private var refreshRotation: Double = 0

    private var sakuraPink: Color { colors.sakuraPink }
    private var mintCyan: Color { colors.mintCyan }
    private var lavenderDream: Color { colors.lavenderDream }

    var body: some View {
        HStack(spacing: 8) {
            // 灵动岛快捷控制（可爱萌系胶囊）
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                onToggleLiveActivity()
            }) {
                HStack(spacing: 4) {
                    Text("🏝️")
                        .font(.system(size: 11))
                    Text(isLiveActivityActive ? "灵动岛中" : "开灵动岛")
                        .font(.system(size: 10, weight: .bold, design: .rounded))

                    if isLiveActivityActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .shadow(color: .green.opacity(0.8), radius: 3)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isLiveActivityActive
                        ? LinearGradient(
                            colors: [sakuraPink.opacity(0.35), lavenderDream.opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [NIOThemePaint.chipFill, NIOThemePaint.chipFill],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .foregroundStyle(isLiveActivityActive ? sakuraPink : NIOThemePaint.text.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isLiveActivityActive
                                ? LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [NIOThemePaint.text.opacity(0.2), NIOThemePaint.stroke], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1
                        )
                )
                .shadow(color: isLiveActivityActive ? sakuraPink.opacity(0.3) : .clear, radius: 4)
            }

            // 手动刷新按钮（与 macOS 看板一致，带 360 度旋转动画与触觉反馈）
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(.easeInOut(duration: 0.6)) {
                    refreshRotation += 360
                }
                onRefresh()
            }) {
                ZStack {
                    Circle()
                        .fill(NIOThemePaint.stroke)
                        .frame(width: 28, height: 28)

                    Image(systemName: isLoadingVehicle ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(sakuraPink)
                        .rotationEffect(.degrees(refreshRotation))
                }
            }
            .disabled(isLoadingVehicle)

            // 设置按钮
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                onSettings()
            }) {
                ZStack {
                    Circle()
                        .fill(NIOThemePaint.stroke)
                        .frame(width: 28, height: 28)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.pastelYellow)
                }
            }
        }
    }
}

// MARK: - 原始 JSON 查看弹窗

@MainActor
private struct NIOAnimeRawJSONSheet: View {
    let title: String?
    let json: String?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title ?? "原始数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onClose)
                }
            }
        }
    }
}

// MARK: - 主看板视图（保持轻量，仅负责组装子视图）

@MainActor
struct IOSNIODashboardView: View {
    @ObservedObject var service = NIOService.shared
    @State private var showConfigSheet = false
    @State private var showLogsSheet = false
    @State private var selectedRawJSONTitle: String?
    @State private var selectedRawJSON: String?
    @State private var hasAppeared = false
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var status: NIOVehicleStatus? { service.vehicleData?.data?.status }
    private var colors: NIOAnimeColors { .resolve(themeService) }

    var body: some View {
        NavigationStack {
            ZStack {
                // 梦幻二次元背景渐变
                NIOAnimeBackground(colors: colors)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 1. 萌宠对话框与顶部状态
                        NIOAnimeMascotHeader(
                            status: status,
                            isLoadingVehicle: service.isLoadingVehicle,
                            lastVehicleFetch: service.lastVehicleFetch,
                            colors: colors
                        )
                        .nioEntry(hasAppeared: hasAppeared, delay: 0.05, lift: 20)

                        if service.is403Detected {
                            NIOAnimeAuthExpiredCard(colors: colors, onUpdate: { showConfigSheet = true })
                                .transition(.scale.combined(with: .opacity))
                        }

                        if !service.isConfigured {
                            NIOWelcomeSetupCard(colors: colors, onConfigure: { showConfigSheet = true })
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.12)
                        } else {
                            // 2. 爱车萌动形象卡片 (3D 车图 + 状态胶囊 + 总里程)
                            NIOAnimeHeroVehicleCard(status: status, lastVehicleFetch: service.lastVehicleFetch, colors: colors)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.12)

                            // 3. ⚡️ 超能萌动电量与续航
                            NIOAnimeBatteryCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.18)

                            // 3.5 ⚡️ 充电大屏与高压快充详情
                            NIOAnimeChargingDetailCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.19)

                            // 4. 💻 车机系统与固件版本 (FOTA)
                            NIOAnimeFotaCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.20)

                            // 5. 📍 停车位置与寻车导航
                            NIOAnimeLocationCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.22)

                            // 5.5 🗺️ 每日行驶轨迹地图
                            NIOAnimeDailyPathCard(dailyPaths: service.dailyPaths, colors: colors)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.24)

                            // 6. 🚪 守护结界 · 车门车况全景
                            NIOAnimeDoorsCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.25)

                            // 6.5 🪟 车窗与天幕开度透视
                            NIOAnimeWindowsCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.26)

                            // 6.6 🚗 驾驶模式与行车泊车全景
                            NIOAnimeDrivingParkingCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.27)

                            // 7. 🛞 萌爪胎压与温度监测 (4 轮网格)
                            NIOAnimeTyreGridCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.28)

                            // 8. 🌡️ 暖风座舱与超强干燥
                            NIOAnimeCockpitCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.31)

                            // 8.5 🪑 座椅舒适与方向盘加热
                            NIOAnimeSeatComfortCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.32)

                            // 8.6 🔑 智能钥匙感知与低压电瓶健康
                            NIOAnimeKeySensorsCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.33)

                            // 9. 🧊 车载智能冰箱与空气健康
                            NIOAnimeCabinExtrasCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.34)

                            // 9.5 📦 储物空间与行李箱状态
                            NIOAnimeStorageBoxCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.35)

                            // 10. 💡 车外灯光与照明系统 (拟物重构)
                            NIOAnimeLightsCard(status: status, colors: colors, onShowJSON: showJSON)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.37)

                            // 11. ⚡️ 远程智能车控与互联
                            NIOAnimeRemoteControlCard(colors: colors)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.40)

                            // 12. 📑 换电站足迹与财务大屏
                            NIOAnimeOrdersCard(summary: service.serviceSummary, colors: colors)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.43)

                            // 13. 📈 能耗达成率与百公里电耗评分
                            NIOAnimeEfficiencyCard(socStatus: status?.socStatus, colors: colors)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.45)

                            // 13.5 📊 历史趋势与多维图表分析
                            NIOAnimeTrendChartsCard(history: service.history, dailyDeltas: service.dailyMileageDeltas, colors: colors)
                                .nioEntry(hasAppeared: hasAppeared, delay: 0.46)

                            // 14. 🔧 维保周期与耗材寿命追踪
                            NIOAnimeMaintenanceCard(
                                mileage: status?.exteriorStatus?.mileage,
                                orders: service.serviceSummary?.orders ?? [],
                                colors: colors
                            )
                            .nioEntry(hasAppeared: hasAppeared, delay: 0.47)

                            // 15. 📅 签到连击与里程成就
                            NIOAnimeCheckinCard(
                                checkinData: service.checkinData,
                                colors: colors,
                                onCheckin: {
                                    Task {
                                        await service.fetchCheckin()
                                    }
                                }
                            )
                            .nioEntry(hasAppeared: hasAppeared, delay: 0.49)

                            // 16. 📜 抓包请求与运行日志
                            NIOAnimeFetchLogCard(
                                logs: service.fetchLogs,
                                colors: colors,
                                onViewAllLogs: { showLogsSheet = true }
                            )
                            .nioEntry(hasAppeared: hasAppeared, delay: 0.50)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .refreshable {
                    await service.fetchVehicle()
                    await service.fetchChange()
                    await service.fetchCheckin()
                    service.updateLiveActivity()
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    hasAppeared = true
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NIOAnimeBrandBadge(colors: colors)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NIOAnimeDashboardActions(
                        colors: colors,
                        isLiveActivityActive: service.isLiveActivityActive,
                        isLoadingVehicle: service.isLoadingVehicle,
                        onToggleLiveActivity: {
                            if service.isLiveActivityActive {
                                service.stopLiveActivity()
                            } else {
                                service.updateLiveActivity()
                            }
                        },
                        onRefresh: {
                            service.refreshAll()
                            service.updateLiveActivity()
                        },
                        onSettings: { showConfigSheet = true }
                    )
                }
            }
            .sheet(isPresented: $showConfigSheet) {
                IOSNIOConfigView()
            }
            .sheet(isPresented: $showLogsSheet) {
                IOSNIOFetchLogView()
            }
            .sheet(isPresented: Binding(
                get: { selectedRawJSON != nil },
                set: { if !$0 { selectedRawJSON = nil; selectedRawJSONTitle = nil } }
            )) {
                NIOAnimeRawJSONSheet(
                    title: selectedRawJSONTitle,
                    json: selectedRawJSON,
                    onClose: { selectedRawJSON = nil }
                )
            }
        }
    }

    private func showJSON(_ title: String?, _ json: String?) {
        selectedRawJSONTitle = title
        selectedRawJSON = json
    }
}
