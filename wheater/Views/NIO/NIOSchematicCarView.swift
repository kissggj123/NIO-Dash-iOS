//
//  NIOSchematicCarView.swift
//  wheater
//
//  主页车辆俯视示意图（移植自 nio-dash Web 版 VehicleHero「可调节仪表盘」）
//  坐标系与 Web 版完全一致：原图车头朝右（390×150 基准），
//  整体旋转 180° 呈现为车头朝左；轻点轮胎 / 车门 / 前备箱 / 尾门 / 充电口 /
//  座舱 / 灯光，弹出该部件的实时状态卡（对应 Web 版 hover tooltip）。
//  家充桩（Web 版由 HAR 导入数据驱动）在 iOS 端无数据源，暂不绘制。
//

import SwiftUI

// MARK: - 部件热点数据

/// 部件状态色调
enum NIOSchematicTone: Equatable {
    case ok      // 正常（绿）
    case warn    // 需注意（琥珀）
    case idle    // 无数据 / 未激活（灰）

    var color: Color {
        switch self {
        case .ok:   return Color(red: 0.23, green: 0.76, blue: 0.42)
        case .warn: return Color(red: 0.96, green: 0.62, blue: 0.12)
        case .idle: return Color(red: 0.60, green: 0.66, blue: 0.72)
        }
    }
}

/// 热点信息行
struct NIOSchematicSpotRow: Equatable {
    let label: String
    let value: String
}

/// 可交互部件热点
struct NIOSchematicSpot: Identifiable, Equatable {
    let id: String
    let title: String
    let tone: NIOSchematicTone
    let rows: [NIOSchematicSpotRow]
}

// MARK: - 示意图视图

struct NIOSchematicCarView: View {
    let status: NIOVehicleStatus?
    let isCharging: Bool

    /// 当前选中的部件（轻点弹出状态卡，再点或点空白处收起）
    @State private var selectedID: String?
    /// 充电呼吸脉冲
    @State private var chargePulse = false

    // MARK: 遥测快照

    private var soc: Int { Int(status?.socStatus?.soc ?? 0) }
    private var locked: Bool { (status?.doorStatus?["vehicle_lock_status"]?.intValue ?? 1) == 1 }
    private var tyres: NIOVehicleLib.TyreStatusInfo { NIOVehicleLib.extractTyreInfo(status?.tyreStatus) }

    /// 舱盖微开（1 = 关闭，其他/缺失按 Web 版语义处理）
    private func ajar(_ key: String) -> Bool {
        guard let v = status?.doorStatus?[key]?.intValue else { return false }
        return v != 1
    }

    private var hoodOpen: Bool { ajar("engine_hood_ajar_status") }
    private var tailOpen: Bool { ajar("tailgate_ajar_status") }
    private var portOpen: Bool { ajar("second_charge_port_ajar_status") }

    private func lightOn(_ key: String) -> Bool { (status?.lightStatus?[key]?.intValue ?? 0) >= 1 }
    private var headLightOn: Bool { lightOn("head_light_on") }
    private var drlOn: Bool { lightOn("day_ti_runng_li_sts") }
    private var parkLightOn: Bool { lightOn("parking_light_le_on") || lightOn("parking_light_ri_on") }

    // MARK: 热点构建（字段名与 Web 版 nio-dash 一致）

    static func makeSpots(status: NIOVehicleStatus?, isCharging: Bool) -> [NIOSchematicSpot] {
        let doors = status?.doorStatus
        let win = status?.windowStatus
        let hvac = status?.hvacStatus
        let socStatus = status?.socStatus
        let tyres = NIOVehicleLib.extractTyreInfo(status?.tyreStatus)
        let locked = (doors?["vehicle_lock_status"]?.intValue ?? 1) == 1

        func ajar(_ key: String) -> Bool {
            guard let v = doors?[key]?.intValue else { return false }
            return v != 1
        }
        func winLabel(_ key: String) -> String {
            let pos = win?[key]?.intValue ?? 0
            if pos <= 0 { return "关闭" }
            if pos >= 100 { return "全开" }
            return "开度 \(pos)%"
        }
        func doorSpot(_ id: String, _ title: String, doorKey: String, winKey: String) -> NIOSchematicSpot {
            let open = ajar(doorKey)
            return NIOSchematicSpot(
                id: id,
                title: title,
                tone: open ? .warn : .ok,
                rows: [
                    NIOSchematicSpotRow(label: "车门", value: open ? "开启" : "关闭"),
                    NIOSchematicSpotRow(label: "车窗", value: winLabel(winKey))
                ]
            )
        }
        func tyreSpot(_ id: String, _ title: String, _ info: NIOVehicleLib.TyreWheelInfo) -> NIOSchematicSpot {
            var warn = false
            if let p = info.press, p < 2.2 || p > 3.4 { warn = true }
            if let t = info.temp, t > 75 { warn = true }
            let tone: NIOSchematicTone = info.press == nil ? .idle : (warn ? .warn : .ok)
            return NIOSchematicSpot(
                id: id,
                title: title,
                tone: tone,
                rows: [
                    NIOSchematicSpotRow(label: "胎压", value: info.press != nil ? info.displayPress : "—"),
                    NIOSchematicSpotRow(label: "胎温", value: info.temp != nil ? "\(info.temp!)°C" : "—")
                ]
            )
        }

        let chargeLabel = NIOVehicleLib.smartChargeStateDescription(
            socStatus: socStatus,
            offcarStatus: status?.offcarModeStatus
        )
        let powerText: String = {
            guard let w = socStatus?.chargingPower, w > 0 else { return "—" }
            return String(format: "%.1f kW", w / (w > 100 ? 1000 : 1))
        }()

        var spots: [NIOSchematicSpot] = [
            tyreSpot("tyre_fl", "左前轮", tyres.fl),
            tyreSpot("tyre_fr", "右前轮", tyres.fr),
            tyreSpot("tyre_rl", "左后轮", tyres.rl),
            tyreSpot("tyre_rr", "右后轮", tyres.rr),
            doorSpot("door_fl", "左前门", doorKey: "door_ajar_front_left_status", winKey: "win_front_left_posn"),
            doorSpot("door_fr", "右前门", doorKey: "door_ajar_front_right_status", winKey: "win_front_right_posn"),
            doorSpot("door_rl", "左后门", doorKey: "door_ajar_rear_left_status", winKey: "win_rear_left_posn"),
            doorSpot("door_rr", "右后门", doorKey: "door_ajar_rear_right_status", winKey: "win_rear_right_posn"),
            NIOSchematicSpot(
                id: "hood", title: "前备箱",
                tone: ajar("engine_hood_ajar_status") ? .warn : .ok,
                rows: [NIOSchematicSpotRow(label: "状态", value: ajar("engine_hood_ajar_status") ? "开启" : "关闭")]
            ),
            NIOSchematicSpot(
                id: "tail", title: "尾门",
                tone: ajar("tailgate_ajar_status") ? .warn : .ok,
                rows: [NIOSchematicSpotRow(label: "状态", value: ajar("tailgate_ajar_status") ? "开启" : "关闭")]
            ),
            NIOSchematicSpot(
                id: "port", title: "充电口",
                tone: isCharging ? .ok : (ajar("second_charge_port_ajar_status") ? .warn : .idle),
                rows: [
                    NIOSchematicSpotRow(label: "充电口", value: ajar("second_charge_port_ajar_status") ? "开启" : "关闭"),
                    NIOSchematicSpotRow(label: "充电状态", value: chargeLabel),
                    NIOSchematicSpotRow(label: "功率", value: powerText),
                    NIOSchematicSpotRow(label: "限充", value: socStatus?.targetSocPercentage.map { "\(Int($0))%" } ?? "—")
                ]
            ),
            NIOSchematicSpot(
                id: "cabin", title: "座舱",
                tone: locked ? .ok : .warn,
                rows: [
                    NIOSchematicSpotRow(label: "车锁", value: locked ? "已上锁" : "未上锁"),
                    NIOSchematicSpotRow(label: "车辆", value: status?.exteriorStatus?.vehicleState == 1 ? "行驶中" : "已驻车"),
                    NIOSchematicSpotRow(label: "车内设定", value: hvac?.temperature.map { "\(Int($0))°C" } ?? "—"),
                    NIOSchematicSpotRow(label: "车外", value: hvac?.outsideTemperature.map { "\(Int($0))°C" } ?? "—"),
                    NIOSchematicSpotRow(label: "空调", value: hvac?.airConditionerOn == true ? "开启" : "关闭")
                ]
            ),
            NIOSchematicSpot(
                id: "lights", title: "灯光",
                tone: (status?.lightStatus?["head_light_on"]?.intValue ?? 0) >= 1
                    || (status?.lightStatus?["day_ti_runng_li_sts"]?.intValue ?? 0) >= 1
                    || (status?.lightStatus?["parking_light_le_on"]?.intValue ?? 0) >= 1
                    || (status?.lightStatus?["parking_light_ri_on"]?.intValue ?? 0) >= 1
                    ? .ok : .idle,
                rows: [
                    NIOSchematicSpotRow(label: "大灯", value: (status?.lightStatus?["head_light_on"]?.intValue ?? 0) >= 1 ? "开启" : "关闭"),
                    NIOSchematicSpotRow(label: "日行灯", value: (status?.lightStatus?["day_ti_runng_li_sts"]?.intValue ?? 0) >= 1 ? "开启" : "关闭"),
                    NIOSchematicSpotRow(label: "示宽灯", value: ((status?.lightStatus?["parking_light_le_on"]?.intValue ?? 0) >= 1 || (status?.lightStatus?["parking_light_ri_on"]?.intValue ?? 0) >= 1) ? "开启" : "关闭")
                ]
            )
        ]

        // 家充桩：仅充电时显示（iOS 端无 HAR 导入的桩体数据，只展示充电态摘要）
        if isCharging {
            spots.append(NIOSchematicSpot(
                id: "charger", title: "家充桩",
                tone: .ok,
                rows: [
                    NIOSchematicSpotRow(label: "状态", value: "充电中"),
                    NIOSchematicSpotRow(label: "功率", value: powerText)
                ]
            ))
        }

        return spots
    }

    private var spots: [NIOSchematicSpot] { Self.makeSpots(status: status, isCharging: isCharging) }
    private func spot(_ id: String) -> NIOSchematicSpot? { spots.first { $0.id == id } }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            // 自适应缩放：按内容实际边界（充电时含家充桩）计算，车体撑满可用区域并居中
            let contentW: CGFloat = isCharging ? 585 : 460
            let contentH: CGFloat = 205
            let contentCenterX: CGFloat = isCharging ? 327 : 390
            let contentCenterY: CGFloat = 152
            let scale = min(geo.size.width / contentW, geo.size.height / contentH)
            carDrawing
                .offset(x: 350 - contentCenterX, y: 117.5 - contentCenterY)
                .frame(width: 700, height: 235)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .rotationEffect(.degrees(180))
                .onTapGesture { selectedID = nil } // 点空白处收起状态卡
        }
        .overlay(alignment: .bottomTrailing) {
            if let spot = spots.first(where: { $0.id == selectedID }) {
                detailCard(spot)
                    .padding(8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
        }
        .animation(NIOThemeMotion.easeSmooth, value: selectedID)
        .onAppear {
            guard isCharging else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                chargePulse = true
            }
        }
        .onChange(of: isCharging) { _, charging in
            // 充电状态变化时启停呼吸动画（家充桩 / 充电线 / 充电口同步）
            if charging {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    chargePulse = true
                }
            } else {
                withAnimation(NIOThemeMotion.easeSmooth) { chargePulse = false }
            }
        }
    }

    // MARK: 车体绘制（Web 版 SVG 原坐标移植，整体 180° 由容器负责）

    private var carDrawing: some View {
        ZStack {
            // 车底软阴影
            Ellipse()
                .fill(Color.black.opacity(0.06))
                .frame(width: 480, height: 200)
                .position(x: 390, y: 156)

            // 轮胎 × 4（胎压异常琥珀描边）
            tyreView("tyre_fl", x: 481, y: 56)
            tyreView("tyre_fr", x: 481, y: 224)
            tyreView("tyre_rl", x: 206, y: 56)
            tyreView("tyre_rr", x: 206, y: 224)

            // 车身轮廓
            PathShape(path: bodyPath)
                .fill(bodyFill)
            PathShape(path: bodyPath)
                .stroke(bodyStroke, lineWidth: 2)

            // 后视镜 × 2
            RoundedRectangle(cornerRadius: 4)
                .fill(mirrorFill)
                .frame(width: 16, height: 10)
                .position(x: 444, y: 67)
            RoundedRectangle(cornerRadius: 4)
                .fill(mirrorFill)
                .frame(width: 16, height: 10)
                .position(x: 444, y: 233)

            // 前备箱 / 尾门面板
            panelView(id: "tail", path: tailPath, isOpen: tailOpen)
            panelView(id: "hood", path: hoodPath, isOpen: hoodOpen)

            // 车门 × 4
            doorView("door_fl", x: 360, y: 74, width: 88)
            doorView("door_fr", x: 360, y: 210, width: 88)
            doorView("door_rl", x: 272, y: 74, width: 84)
            doorView("door_rr", x: 272, y: 210, width: 84)

            // 前后挡风玻璃
            PathShape(path: glassRearPath)
                .fill(glassGradient)
            PathShape(path: glassFrontPath)
                .fill(glassGradient)

            // 座舱：车顶面板 + SOC 电量条 + 锁止文字
            cabinView

            // 灯光
            lightsView

            // 家充桩 + 充电线（仅充电时显示，充电线从桩体连到充电口）
            if isCharging {
                PathShape(path: cablePath)
                    .stroke(
                        NIOSchematicTone.ok.color.opacity(chargePulse ? 0.85 : 0.45),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                chargerPileView
            }

            // 充电口
            chargePortView
        }
    }

    // MARK: 各部件

    private func tyreView(_ id: String, x: CGFloat, y: CGFloat) -> some View {
        let tone = spot(id)?.tone ?? .idle
        return RoundedRectangle(cornerRadius: 7)
            .fill(Color(red: 0.14, green: 0.19, blue: 0.24))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(tone == .warn ? NIOSchematicTone.warn.color : .clear, lineWidth: 2.5)
            )
            .frame(width: 58, height: 20)
            .contentShape(Rectangle())
            .position(x: x + 29, y: y + 10)
            .onTapGesture { select(id) }
    }

    @ViewBuilder
    private func panelView(id: String, path: Path, isOpen: Bool) -> some View {
        PathShape(path: path)
            .fill(isOpen ? NIOSchematicTone.warn.color.opacity(0.22) : panelFill)
        PathShape(path: path)
            .stroke(panelStroke, lineWidth: 1.6)
        // 透明命中区（path 本身即可命中，补一层 contentShape 稳定命中）
        PathShape(path: path)
            .fill(Color.clear)
            .contentShape(PathShape(path: path))
            .onTapGesture { select(id) }
    }

    private func doorView(_ id: String, x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        let open = spot(id)?.tone == .warn
        return RoundedRectangle(cornerRadius: 6)
            .fill(open ? NIOSchematicTone.warn.color.opacity(0.35) : Color(red: 0.90, green: 0.92, blue: 0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(red: 0.78, green: 0.81, blue: 0.85), lineWidth: 1.4)
            )
            .frame(width: width, height: 16)
            .contentShape(Rectangle())
            .position(x: x + width / 2, y: y + 8)
            .onTapGesture { select(id) }
    }

    private var cabinView: some View {
        ZStack {
            // 车顶面板（座舱）
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color(red: 0.86, green: 0.88, blue: 0.90), lineWidth: 1.6)
                )
                .frame(width: 158, height: 108)
            // SOC 电量条（轨道 + 填充，局部坐标：轨道左缘距容器中心 -55）
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.90, green: 0.91, blue: 0.93))
                .frame(width: 110, height: 8)
                .offset(x: 0, y: 24)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.22, green: 0.72, blue: 0.42))
                .frame(width: max(10, 110 * CGFloat(min(1, max(0, Double(soc) / 100)))), height: 8)
                .offset(x: min(55, max(10, 110 * CGFloat(min(1, max(0, Double(soc) / 100))))) / 2 - 55, y: 24)
            // 锁止文字（容器整体旋转 180°，此处反转回正）
            Text(locked ? "已上锁" : "未上锁")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.28))
                .rotationEffect(.degrees(180))
                .offset(y: -4)
        }
        .frame(width: 170, height: 120)
        .contentShape(Rectangle())
        .position(x: 351, y: 150)
        .onTapGesture { select("cabin") }
    }

    private var lightsView: some View {
        ZStack {
            PathShape(path: lightLeftPath)
                .stroke(lightColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            PathShape(path: lightRightPath)
                .stroke(lightColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if headLightOn || drlOn {
                PathShape(path: lightLeftPath)
                    .stroke(NIOSchematicTone.warn.color.opacity(0.35), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .blur(radius: 5)
                PathShape(path: lightRightPath)
                    .stroke(NIOSchematicTone.warn.color.opacity(0.35), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .blur(radius: 5)
            }
        }
        .frame(width: 40, height: 120)
        .contentShape(Rectangle())
        .position(x: 608, y: 150)
        .onTapGesture { select("lights") }
    }

    private var chargePortView: some View {
        ZStack {
            if isCharging {
                // 充电呼吸光晕
                Circle()
                    .fill(NIOSchematicTone.ok.color.opacity(chargePulse ? 0.35 : 0.08))
                    .frame(width: 34, height: 34)
                    .scaleEffect(chargePulse ? 1.25 : 0.8)
            }
            Circle()
                .fill(portFill)
                .frame(width: 14, height: 14)
            Circle()
                .stroke(portStroke, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
        .position(x: 248, y: 84)
        .onTapGesture { select("port") }
    }

    /// 家充桩（Web 版 SVG 原坐标：桩体/屏幕/LED/底座；局部坐标基于 66×162 容器）
    private var chargerPileView: some View {
        ZStack {
            // 桩体
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.78, green: 0.81, blue: 0.85), lineWidth: 1.6)
                )
                .frame(width: 50, height: 152)
            // 屏幕
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.16, green: 0.20, blue: 0.25))
                .frame(width: 30, height: 22)
                .offset(y: 49)
            // LED 指示灯（呼吸）
            Circle()
                .fill(NIOSchematicTone.ok.color.opacity(chargePulse ? 1.0 : 0.4))
                .frame(width: 8, height: 8)
                .offset(y: 22)
            // 底座
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                .frame(width: 66, height: 10)
                .offset(y: -77)
        }
        .frame(width: 66, height: 162)
        .contentShape(Rectangle())
        .position(x: 75, y: 150)
        .onTapGesture { select("charger") }
    }

    /// 充电线：M 100 176 C 150 250, 200 30, 244 80（桩体 → 充电口）
    private var cablePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 100, y: 176))
        p.addCurve(to: CGPoint(x: 244, y: 80), control1: CGPoint(x: 150, y: 250), control2: CGPoint(x: 200, y: 30))
        return p
    }

    private func select(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(NIOThemeMotion.easeSmooth) {
            selectedID = selectedID == id ? nil : id
        }
    }

    // MARK: 状态卡

    private func detailCard(_ spot: NIOSchematicSpot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(spot.tone.color)
                    .frame(width: 7, height: 7)
                Text(spot.title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.28))
                Spacer()
                Button {
                    select(spot.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.28).opacity(0.45))
                        .padding(4)
                }
            }
            ForEach(spot.rows, id: \.label) { row in
                HStack {
                    Text(row.label)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.28).opacity(0.55))
                    Spacer()
                    Text(row.value)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.28))
                }
            }
        }
        .padding(10)
        .frame(width: 185)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(spot.tone.color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
    }

    // MARK: 配色（白车示意图，与 Web 版一致）

    private var bodyFill: Color { Color(red: 0.973, green: 0.973, blue: 0.965) }
    private var bodyStroke: Color { Color(red: 0.80, green: 0.81, blue: 0.82) }
    private var panelFill: Color { Color.white.opacity(0.9) }
    private var panelStroke: Color { Color(red: 0.85, green: 0.86, blue: 0.87) }
    private var mirrorFill: Color { Color(red: 0.85, green: 0.87, blue: 0.89) }
    private var portFill: Color { portOpen ? NIOSchematicTone.warn.color.opacity(0.5) : Color(red: 0.62, green: 0.68, blue: 0.73).opacity(0.4) }
    private var portStroke: Color {
        if isCharging { return NIOSchematicTone.ok.color }
        if portOpen { return NIOSchematicTone.warn.color }
        return Color(red: 0.62, green: 0.68, blue: 0.73)
    }
    private var lightColor: Color {
        (headLightOn || drlOn || parkLightOn)
            ? Color(red: 0.96, green: 0.76, blue: 0.26)
            : Color(red: 0.76, green: 0.80, blue: 0.83)
    }
    private var glassGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.62, green: 0.71, blue: 0.81),
                Color(red: 0.83, green: 0.88, blue: 0.92)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: SVG 路径移植（Web 版原坐标）

    private var bodyPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 215, y: 72))
        p.addLine(to: CGPoint(x: 540, y: 72))
        p.addCurve(to: CGPoint(x: 612, y: 150), control1: CGPoint(x: 585, y: 72), control2: CGPoint(x: 610, y: 100))
        p.addCurve(to: CGPoint(x: 540, y: 228), control1: CGPoint(x: 610, y: 200), control2: CGPoint(x: 585, y: 228))
        p.addLine(to: CGPoint(x: 215, y: 228))
        p.addCurve(to: CGPoint(x: 168, y: 150), control1: CGPoint(x: 185, y: 228), control2: CGPoint(x: 168, y: 205))
        p.addCurve(to: CGPoint(x: 215, y: 72), control1: CGPoint(x: 168, y: 95), control2: CGPoint(x: 185, y: 72))
        p.closeSubpath()
        return p
    }

    private var tailPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 236, y: 84))
        p.addLine(to: CGPoint(x: 215, y: 84))
        p.addCurve(to: CGPoint(x: 180, y: 150), control1: CGPoint(x: 192, y: 84), control2: CGPoint(x: 180, y: 108))
        p.addCurve(to: CGPoint(x: 215, y: 216), control1: CGPoint(x: 180, y: 192), control2: CGPoint(x: 192, y: 216))
        p.addLine(to: CGPoint(x: 236, y: 216))
        p.addQuadCurve(to: CGPoint(x: 236, y: 84), control: CGPoint(x: 226, y: 150))
        p.closeSubpath()
        return p
    }

    private var hoodPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 474, y: 84))
        p.addLine(to: CGPoint(x: 540, y: 84))
        p.addCurve(to: CGPoint(x: 600, y: 150), control1: CGPoint(x: 578, y: 84), control2: CGPoint(x: 598, y: 108))
        p.addCurve(to: CGPoint(x: 540, y: 216), control1: CGPoint(x: 598, y: 192), control2: CGPoint(x: 578, y: 216))
        p.addLine(to: CGPoint(x: 474, y: 216))
        p.addQuadCurve(to: CGPoint(x: 474, y: 84), control: CGPoint(x: 484, y: 150))
        p.closeSubpath()
        return p
    }

    private var glassRearPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 270, y: 98))
        p.addQuadCurve(to: CGPoint(x: 240, y: 150), control: CGPoint(x: 242, y: 102))
        p.addQuadCurve(to: CGPoint(x: 270, y: 202), control: CGPoint(x: 242, y: 198))
        p.closeSubpath()
        return p
    }

    private var glassFrontPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 432, y: 96))
        p.addQuadCurve(to: CGPoint(x: 472, y: 150), control: CGPoint(x: 470, y: 100))
        p.addQuadCurve(to: CGPoint(x: 432, y: 204), control: CGPoint(x: 470, y: 200))
        p.closeSubpath()
        return p
    }

    // 灯光曲线（局部坐标，容器 40×120 定位在 (608,150)）
    private var lightLeftPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 2, y: 6))
        p.addQuadCurve(to: CGPoint(x: 18, y: 34), control: CGPoint(x: 16, y: 18))
        return p
    }

    private var lightRightPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 2, y: 114))
        p.addQuadCurve(to: CGPoint(x: 18, y: 88), control: CGPoint(x: 16, y: 102))
        return p
    }
}

// MARK: - Path 形状包装

/// 让 Path 可以作为 Shape 使用（fill / stroke / contentShape）
private struct PathShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}
