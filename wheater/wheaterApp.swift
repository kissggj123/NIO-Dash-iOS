//
//  wheaterApp.swift
//  wheater
//

import SwiftUI
import UserNotifications
import AppIntents

@main
struct wheaterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                print("[Notification] Push notification permissions granted")
            }
        }
        // 后台刷新注册（v5.2.0）：必须在启动完成前注册，否则 BGTaskScheduler 直接拒绝
        NIOService.registerBackgroundRefresh()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    switch url.host {
                    case "raise-island":
                        // 控制胶囊 / 外部通过 yumikotoysrr://raise-island 拉起时直接触发上岛
                        NIOService.shared.raiseLiveActivityFromControl()
                    case "open-dashboard":
                        // 灵动岛 / 锁屏卡片点击：立即刷新车况 + 主卡片入场动画
                        Task { await NIOService.shared.refreshAll(force: true) }
                        NIOService.shared.islandEntryPulse = Date()
                    default:
                        break
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // 后台定位保活：已配置凭证且授权后，轮询 Timer 在后台继续跑
                        NIOLocationKeepAlive.shared.requestAndStart()
                        // 控制胶囊上岛接力：App 激活时消费 Widget 扩展写入的快速上岛请求
                        NIOService.shared.checkPendingIslandRaise()
                    case .background:
                        // 退到后台预约一次 BGAppRefreshTask，后台仍定期刷新车况与灵动岛
                        NIOService.scheduleBackgroundRefresh()
                    default:
                        break
                    }
                }
        }
    }
}

// MARK: - 快捷指令（Shortcuts / 语音 Siri / 灵动建议）
// 仅编译进主 App target：AppShortcutsProvider 必须在主 App 内注册。

/// 刷新车况：后台拉取最新数据（不打开 App），完成后播报结果
struct NIORefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新车况"
    static var description = IntentDescription("立即拉取最新车辆数据并更新小组件与灵动岛")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            NIOService.shared.refreshAll(force: true, announce: false)
        }
        // 拉取为异步流程，稍候等快照落盘再返回（最多 12 秒）
        let before = WheaterVehicleSnapshot.load()?.updatedAt
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let snap = WheaterVehicleSnapshot.load(), snap.updatedAt != before {
                return .result(dialog: IntentDialog("车况已刷新：电量 \(snap.soc.safeInt ?? 0)%，续航 \(snap.remainingRangeKm) km"))
            }
        }
        return .result(dialog: IntentDialog("刷新指令已发出，稍后查看小组件确认结果"))
    }
}

/// 车况速览：不联网，播报最近一次快照
struct NIOStatusOverviewIntent: AppIntent {
    static var title: LocalizedStringResource = "车况速览"
    static var description = IntentDescription("播报电量、续航与车辆状态（最近同步数据）")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snap = WheaterVehicleSnapshot.load() else {
            return .result(dialog: IntentDialog("还没有车况数据，打开 App 同步一次即可"))
        }
        var parts = ["电量 \(snap.soc.safeInt ?? 0)%", "续航 \(snap.remainingRangeKm) km"]
        if snap.isCharging, let target = snap.chargingTargetSoc {
            parts.append("充电中，限充 \(Int(target))%")
        } else {
            parts.append(snap.isLocked ? "已上锁" : "未上锁")
        }
        if let act = snap.actualRangeKm, act > 0 {
            parts.append("实估 \(act) km")
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: "，")))
    }
}

/// 快捷指令注册：Siri 语音短语 + Spotlight/锁屏建议
struct WheaterAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NIORefreshStatusIntent(),
            phrases: [
                "刷新\(.applicationName)车况",
                "\(.applicationName)刷新车况"
            ],
            shortTitle: "刷新车况",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: NIOStatusOverviewIntent(),
            phrases: [
                "\(.applicationName)车况",
                "查看\(.applicationName)车况"
            ],
            shortTitle: "车况速览",
            systemImageName: "car.front.waves.up"
        )
    }
}
