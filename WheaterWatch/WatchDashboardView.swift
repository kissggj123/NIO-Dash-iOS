//
//  WatchDashboardView.swift
//  YumikoToysRRWatch
//
//  腕上速览主界面：SOC 大圆环 + 续航 + 充电/锁车/特殊模式徽章 + 胎压四宫格
//  + 车内外温度 + 更新时间。主题色跟随 iPhone 当前主题。
//

import SwiftUI

struct WatchDashboardView: View {
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        NavigationStack {
            Group {
                if let snap = session.snapshot {
                    dashboard(snap)
                } else {
                    emptyState
                }
            }
            .navigationTitle("兔可可")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(theme.background)
        .onAppear { session.activate() }
    }

    private var theme: WatchTheme {
        WatchTheme.theme(for: session.snapshot?.themeRaw)
    }

    // MARK: - 主看板

    private func dashboard(_ snap: WatchSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                socRing(snap)
                statusBadges(snap)
                if snap.isCharging { chargingPanel(snap) }
                tyreGrid(snap)
                tempRow(snap)
                footer(snap)
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: SOC 圆环

    private func socRing(_ snap: WatchSnapshot) -> some View {
        ZStack {
            Circle()
                .stroke(theme.accent.opacity(0.18), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.02, min(1.0, snap.soc / 100.0)))
                .stroke(
                    AnyShapeStyle(snap.soc <= 20 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(theme.auroraGradient)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.glow.opacity(0.45), radius: 4)
            VStack(spacing: 0) {
                Text("\(Int(snap.soc))%")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.text)
                Text("\(snap.displayRangeKm) km")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(width: 110, height: 110)
        .padding(.top, 2)
    }

    // MARK: 状态徽章

    private func statusBadges(_ snap: WatchSnapshot) -> some View {
        FlowBadges(items: badgeItems(snap), theme: theme)
    }

    private func badgeItems(_ snap: WatchSnapshot) -> [(String, Color)] {
        var items: [(String, Color)] = []
        if snap.isCharging {
            items.append(("⚡️ 充电中", .green))
        } else if snap.isDriving == true {
            items.append(("🚗 行驶中", theme.accent))
        }
        items.append((snap.isLocked ? "🔒 已锁" : "🔓 未锁", snap.isLocked ? theme.accent : .orange))
        if !snap.isLocked || snap.anyDoorOpen { items.append(("车门/车窗未关", .orange)) }
        if snap.defenderActive { items.append(("🛡 守卫", theme.accent)) }
        if snap.petModeActive { items.append(("🐾 宠物", theme.accent)) }
        if snap.campModeActive { items.append(("🏕 露营", theme.accent)) }
        if snap.powerHoldActive { items.append(("不下电", theme.accent)) }
        if snap.v2lActive == true { items.append(("🔌 V2L", theme.accent)) }
        return items
    }

    // MARK: 充电面板

    private func chargingPanel(_ snap: WatchSnapshot) -> some View {
        VStack(spacing: 4) {
            Text(snap.chargeStateText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            if let power = snap.chargingPowerKw, power > 0 {
                Text(String(format: "%.1f kW", power))
                    .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.text)
            }
            if let eta = snap.chargeEtaDate, eta > Date() {
                Text("预计 \(eta.formatted(date: .omitted, time: .shortened)) 充满")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let target = snap.chargingTargetSoc, target > 0 {
                Text("限充 \(Int(target))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(theme.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 胎压四宫格

    private func tyreGrid(_ snap: WatchSnapshot) -> some View {
        VStack(spacing: 4) {
            if snap.tyres.allSatisfy({ $0.press == nil }) {
                EmptyView()
            } else {
                Text("胎压 bar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(snap.tyres, id: \.label) { tyre in
                        VStack(spacing: 1) {
                            Text(tyre.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(tyre.press.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle((tyre.press ?? 0) < 2.2 && tyre.press != nil ? Color.orange : theme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(theme.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: 温度与更新时间

    private func tempRow(_ snap: WatchSnapshot) -> some View {
        HStack(spacing: 12) {
            if let inside = snap.insideTemp {
                Label(String(format: "%.0f°", inside), systemImage: "thermometer.variable")
                    .font(.caption2.monospacedDigit())
            }
            if let outside = snap.outsideTemp {
                Label(String(format: "%.0f°", outside), systemImage: "cloud.sun")
                    .font(.caption2.monospacedDigit())
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    private func footer(_ snap: WatchSnapshot) -> some View {
        Text("更新于 \(snap.updatedAt.formatted(date: .omitted, time: .shortened)) · 来自 iPhone")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(theme.accent)
            Text("等待 iPhone 数据")
                .font(.headline)
                .foregroundStyle(theme.text)
            Text("在 iPhone 上打开兔可可 App\n刷新车况后自动同步到手表")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// 简易流式徽章行（watchOS 无 FlowLayout，两行自适应换行）
private struct FlowBadges: View {
    let items: [(String, Color)]
    let theme: WatchTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(rows[row], id: \.0) { item in
                        Text(item.0)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: [[(String, Color)]] {
        // 每行约 3 个徽章，简单固定切行
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
    }

    private var rowCount: Int { rows.count }
}
