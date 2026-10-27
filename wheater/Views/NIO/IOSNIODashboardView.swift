//
//  IOSNIODashboardView.swift
//  wheater
//
//  A native NIO vehicle dashboard. Data semantics mirror NIO-Dash and ha-nio:
//  a single glanceable overview followed by detailed, read-only telemetry.
//

import SwiftUI

@MainActor
struct IOSNIODashboardView: View {
    @ObservedObject private var service = NIOService.shared
    @ObservedObject private var themeService = AnimeThemeService.shared
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var selectedSection: DashboardSection = .overview

    private var status: NIOVehicleStatus? { service.vehicleData?.data?.status }
    private var soc: NIOSocStatus? { status?.socStatus }
    private var isCharging: Bool {
        NIOVehicleLib.isRealCharging(socStatus: soc, offcarStatus: status?.offcarModeStatus)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NIOAppBackground()
                    .ignoresSafeArea()

                if service.isConfigured {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            vehicleHero
                            sectionPicker
                            selectedContent
                            if let error = service.lastError, !error.isEmpty {
                                NIOAlertCard(message: error, action: { showSettings = true })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .refreshable { await refresh() }
                } else {
                    NIOEmptyState(onConfigure: { showSettings = true })
                        .padding(24)
                }
            }
            .navigationTitle("NIO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(service.isLoadingVehicle ? .orange : .green)
                            .frame(width: 7, height: 7)
                        Text(service.isLoadingVehicle ? "同步中" : "已连接")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { service.refreshAll(force: true) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isLoadingVehicle)
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { IOSNIOConfigView() }
            .sheet(isPresented: $showLogs) { IOSNIOFetchLogView() }
        }
    }

    private var vehicleHero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: themeService.currentToken.gradientStart), Color(hex: themeService.currentToken.gradientEnd)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 260, height: 260)
                .offset(x: 130, y: -95)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(vehicleName)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 5) {
                            Image(systemName: isCharging ? "bolt.fill" : vehicleStateIcon)
                            Text(vehicleStateLabel)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isCharging ? .green : .white.opacity(0.68))
                    }
                    Spacer()
                    if service.isLoadingVehicle {
                        ProgressView().tint(.white)
                    } else {
                        Text(lastUpdatedLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(soc.map { String(format: "%.0f", $0.soc ?? 0) } ?? "--")
                        .font(.system(size: 68, weight: .thin, design: .rounded))
                    Text("%")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(rangeText(soc?.remainingRange))
                            .font(.title3.weight(.semibold))
                        Text("CLTC 续航")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(isCharging ? Color.green : themeService.accentColor())
                            .frame(width: max(6, proxy.size.width * CGFloat(min(1, max(0, (soc?.soc ?? 0) / 100)))))
                    }
                }
                .frame(height: 6)

                HStack(spacing: 0) {
                    HeroMetric(title: "实估续航", value: rangeText(soc?.remainingActualRange))
                    HeroMetric(title: "总里程", value: mileageText)
                    HeroMetric(title: isCharging ? "充电功率" : "车辆状态", value: isCharging ? powerText : vehicleStateLabel, trailing: true)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
    }

    private var sectionPicker: some View {
        Picker("看板", selection: $selectedSection) {
            ForEach(DashboardSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .overview: overview
        case .vehicle: vehicleDetail
        case .insights: insights
        }
    }

    private var overview: some View {
        VStack(spacing: 14) {
            NIOSectionCard(title: "当前状态", subtitle: "来自车辆实时遥测") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatusTile(icon: "lock.fill", title: "车锁", value: isLocked ? "已上锁" : "未上锁", tint: isLocked ? .green : .orange)
                    StatusTile(icon: "door.left.hand.open", title: "车门", value: allDoorsClosed ? "已关好" : "请检查", tint: allDoorsClosed ? .green : .orange)
                    StatusTile(icon: "window.vertical.open", title: "车窗", value: windowsClosed ? "已关闭" : "有开启", tint: windowsClosed ? .green : .orange)
                    StatusTile(icon: "thermometer.medium", title: "座舱温度", value: temperatureText, tint: .cyan)
                }
            }

            NIOSectionCard(title: "能量", subtitle: isCharging ? "正在充电" : "电池与续航") {
                VStack(spacing: 0) {
                    KeyValueRow(label: "充电状态", value: NIOVehicleLib.smartChargeStateDescription(socStatus: soc, offcarStatus: status?.offcarModeStatus))
                    Divider()
                    KeyValueRow(label: "目标电量", value: soc?.targetSocPercentage.map { String(format: "%.0f%%", $0) } ?? "--")
                    Divider()
                    KeyValueRow(label: "电池锁定下限", value: soc?.lockSoc.map { String(format: "%.0f%%", $0) } ?? "--")
                }
            }

            NIOEfficiencyCard(soc: soc, batteryCapacityKwh: service.estimateBatteryCapacityKwh(socStatus: soc))

            NIOModesCard(offcar: status?.offcarModeStatus, v2lStatus: soc?.v2lStatus)

            NIOAccessoriesCard(
                lvBatt: status?.lvBattStatus,
                frdg: status?.frdgStatus,
                heating: status?.heatingStatus,
                light: status?.lightStatus
            )

            tyreCard
            if telemetryWarning != nil {
                NIOSectionCard(title: "遥测诊断", subtitle: "RVS 状态请求字段检查") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(telemetryWarning!, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("请在 NIO App 的爱车页下拉刷新后，重新抓取完整的 /rvs/vehicle/.../status 请求；不要修改 URL 的 field、参数顺序或 sign。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("打开配置") { showSettings = true }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            locationCard
        }
    }

    private var tyreCard: some View {
        // Do not use NIOVehicleLib.extractTyreInfo(from:) here: its deliberate
        // 2.5 bar preview fallback is useful for a widget layout, but would make
        // a missing RVS `tyre` block look like live vehicle data in the app.
        let tyres = NIOVehicleLib.extractTyreInfo(status?.tyreStatus)
        return NIOSectionCard(title: "轮胎", subtitle: "胎压与胎温") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                TyreTile(position: "左前", item: tyres.fl)
                TyreTile(position: "右前", item: tyres.fr)
                TyreTile(position: "左后", item: tyres.rl)
                TyreTile(position: "右后", item: tyres.rr)
            }
        }
    }

    @ViewBuilder
    private var locationCard: some View {
        if let position = status?.positionStatus,
           let latitude = position.latitude,
           let longitude = position.longitude,
           NIOVehicleLib.isValidGPS(lat: latitude, lng: longitude) {
            NIOSectionCard(title: "车辆位置", subtitle: "定位数据可能存在延迟") {
                Link(destination: URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)")!) {
                    HStack {
                        Image(systemName: "location.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("在地图中查看位置").foregroundStyle(.primary)
                            Text(String(format: "%.5f, %.5f", latitude, longitude))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var vehicleDetail: some View {
        VStack(spacing: 14) {
            NIOSectionCard(title: "车辆防护", subtitle: "门、窗与连接状态") {
                let entries = NIOVehicleLib.parseAvailableDoors(doorStatus: status?.doorStatus, windowStatus: status?.windowStatus)
                VStack(spacing: 0) {
                    ForEach(entries) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .frame(width: 22)
                                .foregroundStyle(item.isClosed ? .green : .orange)
                            Text(item.title)
                            Spacer()
                            Text(item.isClosed ? "正常" : "注意")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(item.isClosed ? .green : .orange)
                        }
                        .padding(.vertical, 10)
                        if item.id != entries.last?.id { Divider() }
                    }
                }
            }

            NIOSectionCard(title: "座舱与系统", subtitle: "空调、车机与低压电瓶") {
                VStack(spacing: 0) {
                    KeyValueRow(label: "空调", value: status?.hvacStatus?.airConditionerOn == true ? "已开启" : "已关闭")
                    Divider()
                    KeyValueRow(label: "车外温度", value: degreeText(status?.hvacStatus?.outsideTemperature))
                    Divider()
                    KeyValueRow(label: "车机版本", value: fotaDisplay)
                    Divider()
                    KeyValueRow(label: "云端连接", value: status?.connectionStatus?.connected == true ? "在线" : "状态未知")
                }
            }

            NIOSectionCard(title: "行驶", subtitle: "来自 RVS exterior status") {
                VStack(spacing: 0) {
                    KeyValueRow(label: "当前车速", value: status?.exteriorStatus?.speed.map { String(format: "%.0f km/h", $0) } ?? "--")
                    Divider()
                    KeyValueRow(label: "行驶状态", value: vehicleStateLabel)
                    Divider()
                    KeyValueRow(label: "数据采样", value: sampleTimeLabel)
                }
            }
        }
    }

    private var insights: some View {
        VStack(spacing: 14) {
            NIOHistoryTrendCard(snapshots: service.history, deltas: service.dailyMileageDeltas)

            NIOTodayTrackCard(path: service.dailyPaths.last)

            NIOSectionCard(title: "行驶记录", subtitle: "基于本地历史采样") {
                HStack {
                    InsightMetric(value: "\(service.history.count)", label: "历史采样")
                    Divider().frame(height: 38)
                    InsightMetric(value: "\(service.dailyPaths.count)", label: "行驶日期")
                    Divider().frame(height: 38)
                    InsightMetric(value: "\(service.dailyMileageDeltas.count)", label: "里程记录")
                }
            }
            NIOSectionCard(title: "服务与换电", subtitle: "订单同步数据") {
                HStack {
                    InsightMetric(value: "\(service.serviceSummary?.swapCompleted ?? 0)", label: "已完成换电")
                    Divider().frame(height: 38)
                    InsightMetric(value: "\(service.serviceSummary?.total ?? 0)", label: "服务订单")
                    Divider().frame(height: 38)
                    InsightMetric(value: checkinValue, label: "连续签到")
                }
            }

            NIOMaintenanceCard(mileageKm: status?.exteriorStatus?.mileage, orders: service.recentOrders)

            NIOSectionCard(title: "同步诊断", subtitle: "最近请求与响应记录") {
                Button { showLogs = true } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("查看同步日志")
                        Spacer()
                        Text("\(service.fetchLogs.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func refresh() async {
        await service.fetchVehicle(force: true)
        await service.fetchChange(force: true)
        await service.fetchCheckin(force: true)
        service.updateLiveActivity()
    }

    private var vehicleName: String { status?.vehicleId.map { "NIO \($0.suffix(6))" } ?? "我的 NIO" }
    private var isLocked: Bool { (status?.doorStatus?["vehicle_lock_status"]?.intValue ?? 1) == 1 }
    private var allDoorsClosed: Bool { NIOVehicleLib.parseAvailableDoors(doorStatus: status?.doorStatus, windowStatus: nil).filter { $0.id != "vehicle_lock" }.allSatisfy(\.isClosed) }
    private var windowsClosed: Bool { NIOVehicleLib.parseAvailableDoors(doorStatus: nil, windowStatus: status?.windowStatus).first { $0.id == "windows" }?.isClosed ?? true }
    private var mileageText: String { status?.exteriorStatus?.mileage.map { String(format: "%.0f km", $0) } ?? "--" }
    private var powerText: String { soc?.chargingPower.map { String(format: "%.1f kW", $0 / ($0 > 100 ? 1000 : 1)) } ?? "--" }
    private var temperatureText: String { degreeText(status?.hvacStatus?.temperature) }
    private var checkinValue: String { service.checkinData.map { "\($0.continuousDays) 天" } ?? "--" }
    private var fotaDisplay: String {
        let fota = status?.fotaStatus
        let raw = [fota?.currentVersion, fota?.lastVersion, fota?.currentPartNo]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let raw else { return "未返回" }
        return NIOVehicleLib.parseFotaInfo(version: raw).fullDisplay
    }
    private var telemetryWarning: String? {
        let tyreMissing = !NIOVehicleLib.extractTyreInfo(status?.tyreStatus).hasData
        let fotaMissing = status?.fotaStatus?.currentVersion?.isEmpty != false
            && status?.fotaStatus?.lastVersion?.isEmpty != false
        switch (tyreMissing, fotaMissing) {
        case (true, true): return "当前请求未返回胎压和车机版本"
        case (true, false): return "当前请求未返回胎压数据"
        case (false, true): return "当前请求未返回车机版本"
        case (false, false): return nil
        }
    }
    private var sampleTimeLabel: String { dateLabel(status?.socStatus?.sampleTime ?? status?.exteriorStatus?.sampleTime) }
    private var lastUpdatedLabel: String { service.lastVehicleFetch.map { $0.formatted(date: .omitted, time: .shortened) } ?? "未同步" }
    private var vehicleStateIcon: String { status?.exteriorStatus?.vehicleState == 1 ? "steeringwheel" : "parkingsign" }
    private var vehicleStateLabel: String { status?.exteriorStatus?.vehicleState == 1 ? "行驶中" : "已驻车" }
    private func rangeText(_ value: Double?) -> String { value.map { String(format: "%.0f km", $0) } ?? "--" }
    private func degreeText(_ value: Double?) -> String { value.map { String(format: "%.0f℃", $0) } ?? "--" }
    private func dateLabel(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, vehicle, insights
    var id: String { rawValue }
    var title: String { switch self { case .overview: "概览"; case .vehicle: "车辆"; case .insights: "记录" } }
}

private struct NIOAppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AnimeThemeService.shared.backgroundPrimary(), AnimeThemeService.shared.backgroundSecondary()],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct NIOEmptyState: View {
    let onConfigure: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "car.2.fill").font(.system(size: 44)).foregroundStyle(Color(red: 0.11, green: 0.54, blue: 0.48))
            Text("连接你的 NIO").font(.title2.weight(.semibold))
            Text("粘贴从 NIO App 获取的车辆状态 URL 和 Access Token，即可在这里查看实时车况。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("开始配置", action: onConfigure).buttonStyle(.borderedProminent).tint(Color(red: 0.10, green: 0.48, blue: 0.42))
        }
    }
}

private struct NIOAlertCard: View {
    let message: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: "exclamationmark.triangle.fill"); Text(message).lineLimit(2); Spacer(); Image(systemName: "chevron.right") }
                .font(.subheadline).foregroundStyle(.orange).padding(14).background(.orange.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct NIOSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            content
        }
        .padding(16).background(NIOThemePaint.fill).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct HeroMetric: View {
    let title: String; let value: String; var trailing = false
    var body: some View { VStack(alignment: trailing ? .trailing : .leading, spacing: 2) { Text(value).font(.subheadline.weight(.semibold)); Text(title).font(.caption2).foregroundStyle(.white.opacity(0.52)) }.frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading) }
}

private struct StatusTile: View {
    let icon: String; let title: String; let value: String; let tint: Color
    var body: some View { HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(tint).frame(width: 20); VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.medium)) }; Spacer() }.padding(12).background(tint.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14)) }
}

private struct KeyValueRow: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).font(.subheadline.weight(.medium)) }.padding(.vertical, 10) }
}

private struct TyreTile: View {
    let position: String; let item: NIOVehicleLib.TyreWheelInfo
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(position).font(.caption).foregroundStyle(.secondary); Text(item.press.map { String(format: "%.1f bar", $0) } ?? "--").font(.subheadline.weight(.semibold)); Text(item.temp.map { "\($0)℃" } ?? "温度 --").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14)) }
}

private struct InsightMetric: View {
    let value: String; let label: String
    var body: some View { VStack(spacing: 3) { Text(value).font(.title3.weight(.semibold)); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}
