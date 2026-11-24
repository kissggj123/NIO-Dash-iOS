//
//  IOSStargazingTripView.swift
//  wheater
//
//  观星行程主界面：
//  · 行程列表（剪贴板 / 文件导入 JSON）+ 最近行程实时活动 / 系统日历
//  · 详情：观测质量环形仪表盘、动态星图辐射点指示器、最佳窗口倒计时、
//    月光/天气环境卡片组、Bortle 徽章观测点（MapKit 导航）、
//    行程时间轴、观测建议、红光护眼模式
//

import SwiftUI
import UIKit
import MapKit

// MARK: - 红光护眼模式

private struct RedNightVisionModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .grayscale(1.0)
                .colorMultiply(Color(red: 0.85, green: 0.05, blue: 0.05))
                .tint(.red)
        } else {
            content
        }
    }
}

// MARK: - 主列表

struct IOSStargazingTripView: View {
    @ObservedObject private var store = StargazingTripStore.shared
    @ObservedObject private var activityManager = StargazingTripActivityManager.shared
    @ObservedObject private var themeService = AnimeThemeService.shared
    @ObservedObject private var calendar = StargazingCalendarService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var selectedTrip: StargazingTrip?
    @AppStorage("nio_stargazing_red_mode") private var stargazingRedMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                NIOThemePaint.background.ignoresSafeArea()

                if store.trips.isEmpty {
                    emptyState
                } else {
                    tripList
                }
            }
            .navigationTitle("观星行程")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.28), value: themeService.currentStyle)
            .onChange(of: themeService.currentStyle) { _, newStyle in
                // 主题换装：正在展示的实时活动同步跟随全局主题
                Task { await activityManager.updateTheme(newStyle.rawValue) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("关闭")
                    }
                    .fixedSize()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        importFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                // SwiftUI fileImporter 依赖文件 UTI 元数据，重装/迁移恢复的 JSON 常被置灰；
                // 改用 UIDocumentPicker 不做类型过滤，任何文件都可选，解析交给 importJSON 容错
                NIODocumentPicker { result in
                    showImporter = false
                    handleFileImport(result)
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                StargazingTripDetailView(initialTrip: trip)
            }
            .task { await activityManager.discoverExistingActivities() }
            .overlay(alignment: .bottom) {
                if let notice = store.importNotice {
                    StargazingNoticeBanner(text: notice.text, isError: notice.isError)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(nanoseconds: 2_600_000_000)
                                withAnimation { store.importNotice = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(NIOThemePaint.accent)
            Text("还没有观测行程")
                .font(.headline)
                .foregroundStyle(NIOThemePaint.text)
            Text("粘贴观测计划 JSON，或从文件导入")
                .font(.subheadline)
                .foregroundStyle(NIOThemePaint.textSoft)
            Button {
                importFromClipboard()
            } label: {
                Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    .font(.subheadline.bold())
                    .foregroundStyle(NIOThemePaint.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(NIOThemePaint.accentGradient))
            }
            .buttonStyle(NIOPressableButtonStyle())
        }
        .padding(30)
    }

    // MARK: 行程列表

    private var tripList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if let nearest = store.nearestUpcomingTrip {
                    nearestCard(nearest)
                }
                ForEach(store.trips) { trip in
                    tripRow(trip)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    /// 最近行程卡：倒计时 + 实时活动 / 日历快捷操作
    private func nearestCard(_ trip: StargazingTrip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最近的行程", systemImage: "star.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(NIOThemePaint.accent)
                Spacer()
                if trip.isNotStarted, let start = trip.startDate {
                    Text(timerInterval: Date()...start, countsDown: true)
                        .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(NIOThemePaint.accent)
                }
            }

            Text(trip.name)
                .font(.title3.bold())
                .foregroundStyle(NIOThemePaint.text)
            if let window = trip.bestViewingWindow?.primary?.displayRange {
                Text(window)
                    .font(.caption)
                    .foregroundStyle(NIOThemePaint.textSoft)
            }

            HStack(spacing: 10) {
                // 加入实时活动
                Button {
                    Task {
                        await activityManager.startActivity(
                            trip: trip,
                            themeRaw: AnimeThemeService.shared.currentStyle.rawValue)
                        if let report = await StargazingWeatherService.shared.fetchWeather(for: trip) {
                            await activityManager.updateWeather(
                                report: report,
                                themeRaw: AnimeThemeService.shared.currentStyle.rawValue)
                        }
                    }
                } label: {
                    Label(activityManager.activeActivityID == trip.id ? "实时活动中" : "加入实时活动",
                          systemImage: "livephoto")
                        .font(.caption.bold())
                }
                .buttonStyle(NIOPressableButtonStyle())
                .tint(activityManager.activeActivityID == trip.id ? .green : NIOThemePaint.accent)

                // 加入系统日历
                Button {
                    guard !calendar.addedEventIDs.contains(trip.id) else { return }
                    Task { await StargazingCalendarService.shared.saveToCalendar(trip: trip) }
                } label: {
                    Label(calendar.addedEventIDs.contains(trip.id) ? "已添加日历" : "添加到日历",
                          systemImage: calendar.addedEventIDs.contains(trip.id) ? "checkmark.calendar" : "calendar.badge.plus")
                        .font(.caption.bold())
                }
                .buttonStyle(NIOPressableButtonStyle())
                .tint(calendar.addedEventIDs.contains(trip.id) ? .green : NIOThemePaint.accent)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NIOThemePaint.fill)
                .overlay(NIOThemePaint.cardSheen)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(NIOThemePaint.stroke, lineWidth: 1)
        )
    }

    /// 普通行程行
    private func tripRow(_ trip: StargazingTrip) -> some View {
        Button { selectedTrip = trip } label: {
            HStack(spacing: 12) {
                scoreBadge(trip)
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(NIOThemePaint.text)
                        .lineLimit(1)
                    Text(trip.displayStartDate)
                        .font(.caption)
                        .foregroundStyle(NIOThemePaint.textSoft)
                    HStack(spacing: 6) {
                        if let zhr = trip.zhr {
                            chipText("ZHR \(zhr)")
                        }
                        if let location = trip.primaryLocation {
                            chipText(location.name)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(NIOThemePaint.textSoft)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(NIOThemePaint.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(NIOThemePaint.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(NIOPressableButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                store.delete(trip)
            } label: {
                Label("删除行程", systemImage: "trash")
            }
        }
    }

    private func chipText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(NIOThemePaint.chipFill))
            .foregroundStyle(NIOThemePaint.textSoft)
            .lineLimit(1)
    }

    /// 列表行小评分徽章
    private func scoreBadge(_ trip: StargazingTrip) -> some View {
        ZStack {
            Circle()
                .stroke(NIOThemePaint.stroke, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(trip.observationScore ?? 0) / 100)
                .stroke(trip.scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(trip.observationScore ?? 0)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
        }
        .frame(width: 38, height: 38)
    }

    // MARK: 导入

    private func importFromClipboard() {
        let text = UIPasteboard.general.string ?? ""
        guard !text.isEmpty else {
            store.importNotice = .init(text: "剪贴板为空", isError: true)
            return
        }
        do {
            _ = try store.importJSON(text)
        } catch {
            store.importNotice = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            store.importNotice = .init(text: error.localizedDescription, isError: true)
        case .success(let urls):
            guard let url = urls.first else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                _ = try store.importJSON(text)
            } catch {
                store.importNotice = .init(text: "文件读取失败：\(error.localizedDescription)", isError: true)
            }
        }
    }
}

// MARK: - 文件选择器（UIDocumentPicker 封装，不做 UTI 过滤避免迁移后置灰）

struct NIODocumentPicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (Result<[URL], Error>) -> Void
        init(onPick: @escaping (Result<[URL], Error>) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

// MARK: - 结果横幅

struct StargazingNoticeBanner: View {
    let text: String
    var isError: Bool

    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .foregroundStyle(isError ? Color.white : NIOThemePaint.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isError ? AnyShapeStyle(Color.red.opacity(0.9)) : AnyShapeStyle(NIOThemePaint.accentGradient))
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

// MARK: - 行程详情

struct StargazingTripDetailView: View {
    let initialTrip: StargazingTrip

    @ObservedObject private var store = StargazingTripStore.shared
    @ObservedObject private var weather = StargazingWeatherService.shared
    @ObservedObject private var calendar = StargazingCalendarService.shared
    @ObservedObject private var themeService = AnimeThemeService.shared
    @AppStorage("nio_stargazing_red_mode") private var stargazingRedMode = false
    @State private var showEnvCards = true

    /// 实时行程（补全/重导入后跟随 store 更新，保证 UI 响应）
    private var trip: StargazingTrip {
        store.trips.first { $0.id == initialTrip.id } ?? initialTrip
    }

    var body: some View {
        ZStack {
            NIOThemePaint.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard
                    countdownCard
                    if !completionFields.isEmpty { completionCard }
                    envCards
                    starMapCard
                    if !trip.recommendedLocations.isEmpty { locationsCard }
                    if trip.itinerarySegment?.timeline.isEmpty == false { timelineCard }
                    if !(trip.species ?? []).isEmpty || trip.tide != nil { birdingCard }
                    if !trip.tips.isEmpty { tipsCard }
                    attributionCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.28), value: themeService.currentStyle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(NIOThemeMotion.themeSpring) {
                        stargazingRedMode.toggle()
                    }
                } label: {
                    Image(systemName: stargazingRedMode ? "lightbulb.max.fill" : "lightbulb.max")
                }
            }
        }
        .task {
            _ = await weather.fetchWeather(for: trip)
        }
        .modifier(RedNightVisionModifier(isActive: stargazingRedMode))
    }

    // MARK: 头部：评分环形仪表盘 + 基本信息

    private var headerCard: some View {
        HStack(spacing: 18) {
            // 环形评分仪表盘
            ZStack {
                Circle()
                    .stroke(NIOThemePaint.stroke, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(trip.observationScore ?? 0) / 100)
                    .stroke(
                        AngularGradient(colors: trip.scoreGradientColors,
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: trip.scoreColor.opacity(0.45), radius: 5)
                VStack(spacing: 0) {
                    Text("\(trip.observationScore ?? 0)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                    Text("观测评分")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
            }
            .frame(width: 96, height: 96)
            .animation(NIOThemeMotion.easeSmooth, value: trip.observationScore)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: trip.categoryIcon)
                        .font(.caption.bold())
                        .foregroundStyle(NIOThemePaint.accent)
                    Text(trip.categoryLabel)
                        .font(.caption.bold())
                        .foregroundStyle(NIOThemePaint.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(NIOThemePaint.accent))
                    if let zhr = trip.zhr {
                        Text("ZHR \(zhr)")
                            .font(.caption.bold())
                            .foregroundStyle(NIOThemePaint.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(NIOThemePaint.accent))
                    }
                    if let constellation = trip.constellation {
                        Text(constellation)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(NIOThemePaint.chipFill))
                            .foregroundStyle(NIOThemePaint.textSoft)
                    }
                }
                if let parent = trip.parentBody {
                    Text("母体：\(parent)")
                        .font(.caption)
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
                if let velocity = trip.velocityKmS {
                    Text("速度：\(Int(velocity)) km/s")
                        .font(.caption)
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
                if let period = trip.activePeriod, let start = period.startDate, let end = period.endDate {
                    Text("活跃期 \(start) ~ \(end)")
                        .font(.caption2)
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NIOThemePaint.fill)
                .overlay(NIOThemePaint.cardSheen)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }

    // MARK: 倒计时 + 日历

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最佳观测窗口", systemImage: "clock.star")
                    .font(.subheadline.bold())
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                if let start = trip.startDate, trip.isNotStarted {
                    Text(timerInterval: Date()...start, countsDown: true)
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(NIOThemePaint.accent)
                }
            }
            if let primary = trip.bestViewingWindow?.primary {
                windowRow(label: "极大夜（最佳）",
                          range: primary.displayRange ?? "",
                          label2: primary.label,
                          bestHour: primary.bestHourLocal,
                          highlight: true)
                if let secondary = trip.bestViewingWindow?.secondary {
                    windowRow(label: "次选夜",
                              range: secondary.displayRange ?? "",
                              label2: secondary.label,
                              bestHour: nil,
                              highlight: false)
                }
            }
            if let note = trip.scoreNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(NIOThemePaint.textSoft)
                    .lineLimit(3)
            }
            // 一键日历按钮
            Button {
                Task { await calendar.saveToCalendar(trip: trip) }
            } label: {
                Label("添加到系统日历（提前提醒）", systemImage: "calendar.badge.plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(NIOThemePaint.accentGradient))
                    .foregroundStyle(NIOThemePaint.onAccent)
            }
            .buttonStyle(NIOPressableButtonStyle())
            if let result = calendar.lastResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(calendar.isError ? Color.red : .green)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(NIOThemePaint.fill))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }

    private func windowRow(label: String, range: String, label2: String?, bestHour: String?, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(highlight ? NIOThemePaint.accent : NIOThemePaint.textSoft.opacity(0.4))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(highlight ? NIOThemePaint.accent : NIOThemePaint.textSoft)
                    if let label2 {
                        Text(label2)
                            .font(.caption2)
                            .foregroundStyle(NIOThemePaint.textSoft)
                    }
                }
                Text(range)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(NIOThemePaint.text)
                if let bestHour {
                    Text("最佳时段 \(bestHour)")
                        .font(.caption2)
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
            }
            Spacer()
        }
    }

    // MARK: 字段补全卡（JSON 结构异常/缺失时手动补全，并保存为解析规则）

    private var completionFields: [String] {
        var m: [String] = []
        if trip.startDate == nil || trip.endDate == nil { m.append("观测窗口") }
        if trip.type?.lowercased().contains("meteor") == true && trip.zhr == nil { m.append("ZHR") }
        if trip.moonInterference == nil { m.append("月光") }
        if trip.radiant?.horizontal?.maxAltitudeDeg == nil && trip.radiant?.equatorial == nil { m.append("辐射点") }
        if trip.primaryLocation?.bortleClass == nil { m.append("Bortle") }
        return m
    }

    @State private var compWindowStart = Date()
    @State private var compWindowEnd = Date().addingTimeInterval(8 * 3600)
    @State private var compZHR = 100
    @State private var compMoonPhase = "waxing_crescent"
    @State private var compMoonIllum = 0.0
    @State private var compRadiantAz = "NE"
    @State private var compRadiantAlt = 45.0
    @State private var compBortle = 4
    @State private var compLoaded = false

    private static let moonPhaseOptions = [
        ("new_moon", "🌑 新月"), ("waxing_crescent", "🌒 娥眉月"),
        ("first_quarter", "🌓 上弦"), ("waxing_gibbous", "🌔 盈凸"),
        ("full_moon", "🌕 满月"), ("waning_gibbous", "🌖 亏凸"),
        ("last_quarter", "🌗 下弦"), ("waning_crescent", "🌘 残月"),
    ]
    private static let compassOptions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("缺失字段补全", systemImage: "slider.horizontal.3")
                .font(.subheadline.bold())
                .foregroundStyle(NIOThemePaint.text)
            Text("JSON 中缺失：\(completionFields.joined(separator: "、"))。补全后会保存为解析规则，再次导入同 event_id 自动应用。")
                .font(.caption2)
                .foregroundStyle(NIOThemePaint.textSoft)

            if completionFields.contains("观测窗口") {
                HStack(spacing: 10) {
                    DatePicker("开始", selection: $compWindowStart)
                        .font(.caption)
                    DatePicker("结束", selection: $compWindowEnd)
                        .font(.caption)
                }
            }
            if completionFields.contains("ZHR") {
                Stepper("ZHR 天顶流量：\(compZHR)/h", value: $compZHR, in: 5...500, step: 5)
                    .font(.caption)
            }
            if completionFields.contains("月光") {
                Picker("月相", selection: $compMoonPhase) {
                    ForEach(Self.moonPhaseOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
                .font(.caption)
                HStack {
                    Text("月光照度 \(Int(compMoonIllum))%")
                        .font(.caption)
                    Slider(value: $compMoonIllum, in: 0...100, step: 1)
                }
            }
            if completionFields.contains("辐射点") {
                Picker("辐射点方位", selection: $compRadiantAz) {
                    ForEach(Self.compassOptions, id: \.self) { Text($0).tag($0) }
                }
                .font(.caption)
                HStack {
                    Text("极大高度 \(Int(compRadiantAlt))°")
                        .font(.caption)
                    Slider(value: $compRadiantAlt, in: 0...90, step: 1)
                }
            }
            if completionFields.contains("Bortle") {
                Picker("波特尔暗空等级", selection: $compBortle) {
                    ForEach(1...9, id: \.self) { Text("Bortle \($0)").tag($0) }
                }
                .font(.caption)
            }

            Button {
                saveCompletion()
            } label: {
                Label("保存补全并记住规则", systemImage: "checkmark.seal")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NIOPressableButtonStyle())
            .tint(NIOThemePaint.accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NIOThemePaint.fill)
                .overlay(NIOThemePaint.cardSheen)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.warm.opacity(0.5), lineWidth: 1))
        .onAppear(perform: loadCompletionDefaults)
    }

    private func loadCompletionDefaults() {
        guard !compLoaded else { return }
        compLoaded = true
        if let s = trip.startDate { compWindowStart = s }
        if let e = trip.endDate { compWindowEnd = e }
        if let z = trip.zhr { compZHR = z }
        if let mi = trip.moonInterference {
            if let p = mi.phase { compMoonPhase = p.lowercased().replacingOccurrences(of: " ", with: "_") }
            if let i = mi.illuminationPctAtPeak { compMoonIllum = i }
        }
        if let maxAlt = trip.radiant?.horizontal?.maxAltitudeDeg {
            compRadiantAlt = maxAlt
            if let desc = trip.radiant?.horizontal?.azimuthDesc {
                for option in Self.compassOptions where desc.uppercased().contains(option) {
                    compRadiantAz = option
                    break
                }
            }
        }
        if let b = trip.primaryLocation?.bortleClass { compBortle = b }
    }

    private func saveCompletion() {
        var completion: [String: Any] = [:]
        if completionFields.contains("观测窗口") {
            completion["best_viewing_window"] = [
                "start_unix": compWindowStart.timeIntervalSince1970,
                "end_unix": compWindowEnd.timeIntervalSince1970,
            ]
        }
        if completionFields.contains("ZHR") {
            completion["zhr"] = compZHR
        }
        if completionFields.contains("月光") {
            completion["moon_interference"] = [
                "phase": compMoonPhase,
                "illumination_pct_at_peak": compMoonIllum,
            ]
        }
        if completionFields.contains("辐射点") {
            completion["radiant"] = ["horizontal": [
                "max_altitude_deg": compRadiantAlt,
                "azimuth_desc": "方位 \(compRadiantAz)（导入补全）",
                "altaz_timeline": [[
                    "alt_deg": compRadiantAlt,
                    "az_compass": compRadiantAz,
                    "note": "导入补全",
                ]],
            ]]
        }
        if completionFields.contains("Bortle") {
            completion["recommended_locations"] = trip.recommendedLocations.map { loc in
                ["id": loc.id, "name": loc.name,
                 "coordinates": ["lat": loc.lat, "lng": loc.lng],
                 "bortle_class": loc == trip.primaryLocation ? compBortle : (loc.bortleClass ?? compBortle)]
            }
        }

        if store.applyCompletion(completion, to: trip) {
            store.importNotice = .init(text: "已补全并保存解析规则（下次导入自动应用）", isError: false)
        }
    }

    // MARK: 环境卡片组（月光 / 天气矩阵）

    @State private var isRefreshingData = false

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var envCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("观测环境", systemImage: "cloud.moon")
                    .font(.subheadline.bold())
                    .foregroundStyle(NIOThemePaint.text)
                if let report = weather.reportByTripID[trip.id] {
                    Text("实时数据 · 更新于 \(Self.timeText(report.fetchedAt))")
                        .font(.caption2)
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
                Spacer()
                Button {
                    guard !isRefreshingData else { return }
                    isRefreshingData = true
                    Task {
                        _ = await weather.fetchWeather(for: trip, forceRefresh: true)
                        isRefreshingData = false
                    }
                } label: {
                    Image(systemName: isRefreshingData ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(isRefreshingData ? 360 : 0))
                        .animation(
                            isRefreshingData
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: isRefreshingData)
                        .foregroundStyle(NIOThemePaint.accent)
                }
                .disabled(isRefreshingData)
                .accessibilityLabel("手动更新观测数据")
            }

            TabView {
                moonCard.padding(.horizontal, 2)
                weatherMatrixCard.padding(.horizontal, 2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 178)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(NIOThemePaint.fill))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }

    /// 月光干扰卡（API 实时日月优先，JSON 静态兜底）
    private var moonCard: some View {
        let report = weather.reportByTripID[trip.id]
        let jsonMoon = trip.moonInterference
        let illum = report?.moonIllumPct ?? jsonMoon?.illuminationPctAtPeak
        let moonrise = report?.moonriseText ?? jsonMoon?.moonriseLocal
        let moonset = report?.moonsetText ?? jsonMoon?.moonsetDec14Local?.replacingOccurrences(of: "^月落 ", with: "")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(moonPhaseEmoji(report: report, jsonMoon: jsonMoon))
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(report?.moonPhaseText ?? jsonMoon?.phaseDesc ?? jsonMoon?.phase ?? "月相未知")
                        .font(.subheadline.bold())
                        .foregroundStyle(NIOThemePaint.text)
                    if let illum {
                        Text("极大时刻月光照明 \(Int(illum))%")
                            .font(.caption)
                            .foregroundStyle(NIOThemePaint.textSoft)
                    }
                    HStack(spacing: 8) {
                        if let moonrise {
                            Text("月出 \(moonrise)")
                        }
                        if let moonset {
                            Text("月落 \(moonset)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(NIOThemePaint.textSoft)
                }
                Spacer()
                impactBadge(jsonMoon?.impactLevel ?? "unknown")
            }
            if report?.skyOK == true, report?.astroTwilightStartText != nil {
                Text("天文暗夜 \(report?.astroTwilightStartText ?? "") → \(report?.astroTwilightEndText ?? "") ｜ 日出 \(report?.sunriseText ?? "") 日落 \(report?.sunsetText ?? "")")
                    .font(.caption2)
                    .foregroundStyle(NIOThemePaint.textSoft)
            }
            if let note = jsonMoon?.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(NIOThemePaint.textSoft)
                    .lineLimit(4)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(NIOThemePaint.chipFill))
    }

    /// 月相 emoji：API 英文 phase 或 JSON phase 枚举
    private func moonPhaseEmoji(report: StargazingWeatherReport?, jsonMoon: MoonInterference?) -> String {
        let phase = (report?.moonPhaseText ?? jsonMoon?.phaseDesc ?? jsonMoon?.phase ?? "").lowercased()
        if phase.contains("full") { return "🌕" }
        if phase.contains("new") { return "🌑" }
        if phase.contains("waxing gibbous") { return "🌔" }
        if phase.contains("waxing") { return "🌒" }
        if phase.contains("waning gibbous") { return "🌖" }
        if phase.contains("waning") { return "🌘" }
        if phase.contains("quarter") { return phase.contains("first") ? "🌓" : "🌗" }
        return jsonMoon?.phaseEmoji ?? "🌙"
    }

    private func impactBadge(_ level: String) -> some View {
        let (text, color): (String, Color) = {
            switch level {
            case "low": return ("干扰低", .green)
            case "medium": return ("干扰中", .orange)
            case "high": return ("干扰高", .red)
            default: return (level, .gray)
            }
        }()
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    /// 实时天气矩阵卡
    private var weatherMatrixCard: some View {
        let report = weather.reportByTripID[trip.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("实时天气（观测窗口均值）")
                    .font(.caption.bold())
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                if let fetched = report?.fetchedAt {
                    Text("更新 \(fetched.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                weatherMetric(icon: "cloud.fill", label: "总云量", value: report?.cloudCoverPct, unit: "%")
                weatherMetric(icon: "cloud.fog", label: "低云", value: report?.cloudLowPct, unit: "%")
                weatherMetric(icon: "cloud", label: "高云", value: report?.cloudHighPct, unit: "%")
                weatherMetric(icon: "thermometer.medium", label: "气温", value: report?.temperatureC, unit: "℃", digits: 1)
                weatherMetric(icon: "humidity", label: "湿度", value: report?.humidityPct, unit: "%")
                weatherMetric(icon: "wind", label: "风速", value: report?.windSpeedKmh, unit: "km/h")
                weatherMetric(icon: "eye", label: "视宁度", value: report?.seeingArcsec, unit: "\"", digits: 1)
                weatherMetric(icon: "sun.max", label: "透光度", value: nil, unit: report?.transparencyText ?? "—", isText: true)
                weatherMetric(icon: "aqi.medium", label: "AQI", value: report?.aqiUS, unit: report?.aqiLevelText ?? "", digits: 0)
            }
            if let report, report.isOutOfForecastRange {
                Text("该日期超出 Open-Meteo 16 天预报窗口，临近日期（约提前 16 天）自动补全")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            if let error = weather.lastErrorByTripID[trip.id] {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(NIOThemePaint.chipFill))
    }

    private func weatherMetric(icon: String, label: String, value: Double?, unit: String, digits: Int = 0, isText: Bool = false) -> some View {
        VStack(spacing: 3) {
            Label(label, systemImage: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NIOThemePaint.textSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Group {
                if isText {
                    Text(value == nil ? (unit == "—" ? "—" : unit) : unit)
                } else if let value {
                    Text("\(value.formatted(.number.precision(.fractionLength(digits == 0 ? 0 : 1))))\(unit)")
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(value == nil && !isText ? NIOThemePaint.textSoft : NIOThemePaint.text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: 16, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(NIOThemePaint.fill))
    }

    // MARK: 动态星图 + 辐射点指示器

    /// 时间轴：JSON 优先，缺失时用赤经赤纬本地推算
    private var resolvedAltazTimeline: [Radiant.Horizontal.AltAzEntry] {
        let jsonTimeline = trip.radiant?.horizontal?.altazTimeline ?? []
        if !jsonTimeline.isEmpty { return jsonTimeline }
        guard let eq = trip.radiant?.equatorial, let ra = eq.raDeg, let dec = eq.decDeg,
              let start = trip.startDate, let end = trip.endDate,
              let loc = trip.primaryLocation else { return [] }
        return RadiantAstrometry.timeline(raDeg: ra, decDeg: dec,
                                          lat: loc.lat, lng: loc.lng,
                                          start: start.addingTimeInterval(-7200),
                                          end: min(end, start.addingTimeInterval(43200)))
    }

    private var starMapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("辐射点方位", systemImage: "location.north.circle")
                .font(.subheadline.bold())
                .foregroundStyle(NIOThemePaint.text)
            if let desc = trip.radiant?.horizontal?.azimuthDesc {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(NIOThemePaint.textSoft)
            }
            RadiantCompassView(entries: resolvedAltazTimeline,
                               equatorial: trip.radiant?.equatorial,
                               location: trip.primaryLocation)
                .frame(height: 190)
                .frame(maxWidth: .infinity)
            let altaz = resolvedAltazTimeline
            if !altaz.isEmpty {
                ForEach(altaz) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.timeLocal ?? "")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(NIOThemePaint.text)
                            .frame(width: 96, alignment: .leading)
                        Text("高 \(entry.altDeg.map { String(format: "%.0f", $0) } ?? "—")°")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(NIOThemePaint.textSoft)
                            .frame(width: 52, alignment: .leading)
                        Text("位 \(entry.azCompass ?? (entry.azDeg.map { String(format: "%.0f°", $0) } ?? "—"))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(NIOThemePaint.textSoft)
                            .frame(width: 76, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        if let note = entry.note {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(NIOThemePaint.textSoft)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(NIOThemePaint.fill))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }

    // MARK: 推荐观测点

    private var locationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let route = trip.routeName {
                Text(route)
                    .font(.caption.bold())
                    .foregroundStyle(NIOThemePaint.textSoft)
            }
            ForEach(trip.recommendedLocations) { location in
                Button {
                    openNavigation(location: location)
                } label: {
                    HStack(spacing: 10) {
                        BortleBadge(bortleClass: location.bortleClass
                            ?? StargazingLocalAstronomy.bortleFallback(locationName: location.name)
                            ?? 9,
                            isFallback: location.bortleClass == nil)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(location.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(NIOThemePaint.text)
                                if let tag = location.tag {
                                    Text(tag)
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(NIOThemePaint.chipFill))
                                        .foregroundStyle(NIOThemePaint.textSoft)
                                }
                            }
                            HStack(spacing: 8) {
                                if let city = location.city {
                                    Text(city)
                                        .font(.caption)
                                        .foregroundStyle(NIOThemePaint.textSoft)
                                }
                                if let rate = location.expectedRate {
                                    Text(rate)
                                        .font(.caption2)
                                        .foregroundStyle(NIOThemePaint.textSoft)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(NIOThemePaint.accent)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(NIOThemePaint.chipFill))
                }
                .buttonStyle(NIOPressableButtonStyle())
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(NIOThemePaint.fill))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }

    /// MapKit 调起路线导航（驾车）
    private func openNavigation(location: RecommendedLocation) {
        let coordinate = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = location.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: 数据来源与专业支持（署名）

    private var attributionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("数据来源", systemImage: "info.circle")
                .font(.caption.bold())
                .foregroundStyle(NIOThemePaint.text)
            Text("""
            · 天气/云量：Open-Meteo（CC BY 4.0，非商业 1 万次/日）
            · 视宁度/透光度：7Timer! ASTRO
            · 日出日落/天文晨昏：sunrise-sunset.org v2（CC BY 4.0）、sunrisesunset.io
            · 月出月落/月相/照度：sunrisesunset.io、USNO、CycleCalcs
            · AQI：Open-Meteo Air Quality
            · 辐射点高度/方位：本地天文引擎（SunCalc 算法）
            · ZHR/极大时刻/辐射点：IMO 静态年历
            · Bortle 暗空等级：静态地图值（"≈" 标注为推算值）
            """)
            .font(.system(size: 9))
            .foregroundStyle(NIOThemePaint.textSoft)
            .fixedSize(horizontal: false, vertical: true)
            if let report = weather.reportByTripID[trip.id], let source = report.skyError {
                Text("当前日月数据：\(source)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NIOThemePaint.accent)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(NIOThemePaint.chipFill))
    }

    // MARK: 行程时间轴

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("行程安排", systemImage: "clock.badge.checkmark")
                .font(.subheadline.bold())
                .foregroundStyle(NIOThemePaint.text)
            if let timeline = trip.itinerarySegment?.timeline, !timeline.isEmpty {
                ForEach(Array(timeline.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(NIOThemePaint.accent)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(NIOThemePaint.stroke)
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.timeLocal ?? "")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(NIOThemePaint.accent)
                            Text(item.action ?? "")
                                .font(.caption)
                                .foregroundStyle(NIOThemePaint.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(NIOThemePaint.fill))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }

    // MARK: 观测建议

    // MARK: 观鸟卡（物种清单 + 潮汐预估）

    private var birdingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("目标物种与潮汐", systemImage: "bird")
                .font(.subheadline.bold())
                .foregroundStyle(NIOThemePaint.text)

            ForEach(trip.species ?? []) { sp in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sp.name)
                            .font(.caption.bold())
                            .foregroundStyle(NIOThemePaint.text)
                        if let en = sp.nameEn, !en.isEmpty {
                            Text(en)
                                .font(.caption2)
                                .foregroundStyle(NIOThemePaint.textSoft)
                        }
                    }
                    Spacer()
                    if let count = sp.count, !count.isEmpty {
                        Text(count)
                            .font(.caption2.bold())
                            .foregroundStyle(NIOThemePaint.warm)
                    }
                    if let prot = sp.protection, !prot.isEmpty {
                        Text(prot)
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(NIOThemePaint.warm.opacity(0.18)))
                            .foregroundStyle(NIOThemePaint.warm)
                    }
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(NIOThemePaint.textSoft.opacity(0.12)).frame(height: 0.7)
                }
            }

            if let tide = trip.tide {
                HStack(spacing: 12) {
                    if let high = tide.highTideEstimate {
                        Label("涨潮 \(high)", systemImage: "water.wave")
                            .font(.caption2)
                            .foregroundStyle(NIOThemePaint.textSoft)
                    }
                    if let low = tide.lowTideEstimate {
                        Label("落潮 \(low)", systemImage: "water.wave.slash")
                            .font(.caption2)
                            .foregroundStyle(NIOThemePaint.textSoft)
                    }
                }
                if let note = tide.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(NIOThemePaint.textSoft)
                }
                if let station = tide.station {
                    Text("参考站：\(station)")
                        .font(.caption2)
                        .foregroundStyle(NIOThemePaint.textSoft.opacity(0.8))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NIOThemePaint.fill)
                .overlay(NIOThemePaint.cardSheen)
        )
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("观测建议", systemImage: "lightbulb")
                .font(.subheadline.bold())
                .foregroundStyle(NIOThemePaint.text)
            ForEach(Array(trip.tips.enumerated()), id: \.offset) { index, tip in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(NIOThemePaint.onAccent)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(NIOThemePaint.accent))
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(NIOThemePaint.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(NIOThemePaint.fill))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NIOThemePaint.stroke, lineWidth: 1))
    }
}

// MARK: - 观测类别（为流星雨/极光/观鸟/深度观星预留）

enum StargazingCategory: String, CaseIterable {
    case meteorShower
    case aurora
    case birding
    case deepSky
    case supermoon
    case planet
    case general

    init(from type: String) {
        let text = type.lowercased()
        if text.contains("meteor") || text.contains("流星") || text.contains("shower") {
            self = .meteorShower
        } else if text.contains("aurora") || text.contains("极光") {
            self = .aurora
        } else if text.contains("bird") || text.contains("鸟") || text.contains("migration") || text.contains("迁徙") {
            self = .birding
        } else if text.contains("supermoon") || text.contains("超级月亮") || text.contains("满月") {
            self = .supermoon
        } else if text.contains("planet") || text.contains("行星") || text.contains("opposition") || text.contains("冲日") {
            self = .planet
        } else if text.contains("deep") || text.contains("深空") || text.contains("star") || text.contains("观星") {
            self = .deepSky
        } else {
            self = .general
        }
    }

    var icon: String {
        switch self {
        case .meteorShower: return "sparkles"
        case .aurora: return "rainbow"
        case .birding: return "bird.fill"
        case .deepSky: return "telescope"
        case .supermoon: return "moon.max"
        case .planet: return "sun.haze"
        case .general: return "star"
        }
    }

    var label: String {
        switch self {
        case .meteorShower: return "流星雨"
        case .aurora: return "极光"
        case .birding: return "观鸟"
        case .deepSky: return "观星"
        case .supermoon: return "超级月亮"
        case .planet: return "行星天象"
        case .general: return "观测"
        }
    }

    /// 类别对应的重点环境卡顺序（观鸟后可换潮汐卡等）
    var envCardOrder: [String] {
        switch self {
        case .birding: return ["weather", "moon"]
        default: return ["moon", "weather"]
        }
    }
}

// MARK: - 评分配色

extension StargazingTrip {

    /// 观测类别：为后续适配 极光/观鸟（迁徙潮/潮汐/观测点） 等类型预留
    var category: StargazingCategory {
        StargazingCategory(from: type ?? "")
    }

    var categoryIcon: String { category.icon }
    var categoryLabel: String { category.label }

    var scoreColor: Color {
        switch observationScore ?? 0 {
        case 90...: return Color(hex: "F5A623")   // 金橙
        case 75..<90: return .green
        case 60..<75: return .blue
        default: return .gray
        }
    }

    var scoreGradientColors: [Color] {
        switch observationScore ?? 0 {
        case 90...: return [Color(hex: "FFD34D"), Color(hex: "F5A623")]
        case 75..<90: return [Color(hex: "7BE495"), Color(hex: "2FB37C")]
        case 60..<75: return [Color(hex: "8FC7FF"), Color(hex: "4A8FE7")]
        default: return [Color.gray.opacity(0.6), Color.gray]
        }
    }

    var displayStartDate: String {
        guard let start = startDate else { return "时间待定" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: start)
    }
}

// MARK: - Bortle 暗空徽章

struct BortleBadge: View {
    let bortleClass: Int
    var isFallback = false   // 静态地图值兜底（非 JSON 提供）

    /// Bortle 1( pristine 黑) → 9(市中心亮黄) 色标
    private var color: Color {
        switch bortleClass {
        case 1: return Color(hex: "0A0A1E")
        case 2: return Color(hex: "1B2A4A")
        case 3: return Color(hex: "2E4A7A")
        case 4: return Color(hex: "4E7A3E")
        case 5: return Color(hex: "B8912E")
        case 6: return Color(hex: "D67E2E")
        case 7: return Color(hex: "E06030")
        case 8: return Color(hex: "E85A5A")
        default: return Color(hex: "F2C94C")
        }
    }

    private var description: String {
        switch bortleClass {
        case 1...2: return "顶级暗夜"
        case 3: return "乡村暗夜"
        case 4: return "乡村/近郊"
        case 5: return "郊区"
        case 6: return "明亮郊区"
        case 7: return "郊区/城市过渡"
        case 8: return "城市"
        default: return "市中心"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(bortleClass)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(bortleClass <= 3 ? .white : .black)
            Text("Bortle")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(bortleClass <= 3 ? .white.opacity(0.8) : .black.opacity(0.6))
        }
        .frame(width: 40, height: 40)
        .background(Circle().fill(color))
        .overlay(
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if isFallback {
                Text("≈")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(x: 4, y: 4)
            }
        }
        .help(description)
    }
}

// MARK: - 辐射点方位罗盘（Canvas）

struct RadiantCompassView: View {
    let entries: [Radiant.Horizontal.AltAzEntry]
    var equatorial: Radiant.Equatorial?
    var location: RecommendedLocation?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 26

            // 外圈罗盘
            context.stroke(
                Path { p in p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2)) },
                with: .color(.secondary.opacity(0.5)), lineWidth: 1.5)

            // 方位刻度（N/E/S/W + 45°）
            let labels: [(String, Double)] = [("北", 0), ("东北", 45), ("东", 90), ("东南", 135),
                                              ("南", 180), ("西南", 225), ("西", 270), ("西北", 315)]
            for (label, az) in labels {
                let angle = Self.azimuthToAngle(az)
                let tickStart = Self.point(center: center, radius: radius, angle: angle)
                let tickEnd = Self.point(center: center, radius: radius - 8, angle: angle)
                var tick = Path()
                tick.move(to: tickStart)
                tick.addLine(to: tickEnd)
                context.stroke(tick, with: .color(.secondary.opacity(0.7)), lineWidth: 1.5)
                let textPos = Self.point(center: center, radius: radius + 13, angle: angle)
                context.draw(
                    Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.secondary),
                    at: textPos)
            }

            // 地平线弧（半透明）
            var horizon = Path()
            horizon.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
            context.fill(horizon, with: .color(.blue.opacity(0.04)))

            // 当前辐射点位置：赤经赤纬本地计算优先，其次时间轴插值
            let (current, currentLabel) = Self.currentPosition(entries: entries,
                                                               equatorial: equatorial,
                                                               location: location)
            if entries.count >= 2 {
                var track = Path()
                let sorted = entries.compactMap { $0.date }.sorted()
                if let first = sorted.first {
                    let firstPoint = Self.project(entry: Self.entry(at: first, in: entries),
                                                  center: center, radius: radius)
                    track.move(to: firstPoint)
                    for date in sorted.dropFirst() {
                        let entry = Self.entry(at: date, in: entries)
                        track.addLine(to: Self.project(entry: entry, center: center, radius: radius))
                    }
                    context.stroke(track, with: .color(.orange.opacity(0.4)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }

            // 当前位置：光晕 + 圆点（地平线下时改灰色并标注）
            let belowHorizon = (current.altDeg ?? 0) < 0
            let currentPoint = Self.project(entry: current, center: center, radius: radius)
            let glowColor = belowHorizon ? Color.gray : Color.orange
            let glow = Path(ellipseIn: CGRect(x: currentPoint.x - 16, y: currentPoint.y - 16,
                                              width: 32, height: 32))
            context.fill(glow, with: .color(glowColor.opacity(0.18)))
            let dot = Path(ellipseIn: CGRect(x: currentPoint.x - 6, y: currentPoint.y - 6,
                                             width: 12, height: 12))
            context.fill(dot, with: .color(glowColor))
            context.draw(
                Text(currentLabel)
                    .font(.system(size: 10, weight: .heavy)).foregroundColor(glowColor),
                at: CGPoint(x: currentPoint.x, y: currentPoint.y + 22))

            // 圆心信息读数：当前高度/方位 + 状态（白圈不再空白）
            let alt = current.altDeg ?? 0
            let azCompass = current.azCompass
                ?? (current.azDeg.map { Self.compassName($0) } ?? "—")
            let status: String
            if belowHorizon {
                status = "未升起 · 等待窗口"
            } else if alt >= 30 {
                status = "观测条件良好"
            } else {
                status = "高度偏低 · 建议等待"
            }
            context.draw(
                Text("\(String(format: "%.0f", max(0, alt)))°")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85)),
                at: CGPoint(x: center.x, y: center.y - 12))
            context.draw(
                Text("方位 \(azCompass)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary),
                at: CGPoint(x: center.x, y: center.y + 8))
            context.draw(
                Text(status)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.9)),
                at: CGPoint(x: center.x, y: center.y + 24))
        }
    }

    /// 方位角 → 罗盘名（N/NE/...）
    static func compassName(_ az: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let idx = Int(((az + 11.25) / 22.5).truncatingRemainder(dividingBy: 16))
        return names[idx < 0 ? idx + 16 : idx]
    }

    /// 方位角（0=北, 顺时针）→ Canvas 角度
    static func azimuthToAngle(_ az: Double) -> Angle {
        .degrees(az - 90)
    }

    static func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle.radians),
                y: center.y + radius * sin(angle.radians))
    }

    /// 高度角 → 距离圆心：天顶=圆心，地平线=外圈
    static func project(entry: Radiant.Horizontal.AltAzEntry, center: CGPoint, radius: CGFloat) -> CGPoint {
        let alt = max(0, min(90, entry.altDeg ?? 0))
        let r = radius * (1 - alt / 90)
        let az = entry.azDeg ?? 0
        return point(center: center, radius: r, angle: azimuthToAngle(az))
    }

    /// 当前辐射点位置：赤经赤纬本地天文计算优先（任意时刻准确），
    /// 无赤经赤纬时回退到时间轴插值/钳制（标注对应时次）
    static func currentPosition(entries: [Radiant.Horizontal.AltAzEntry],
                                equatorial: Radiant.Equatorial?,
                                location: RecommendedLocation?)
        -> (Radiant.Horizontal.AltAzEntry, String) {
        // 1) 本地计算
        if let eq = equatorial, let ra = eq.raDeg, let dec = eq.decDeg,
           let loc = location {
            let pos = RadiantAstrometry.altAz(raDeg: ra, decDeg: dec, lat: loc.lat, lng: loc.lng, date: Date())
            let entry = Radiant.Horizontal.AltAzEntry(
                timeLocal: nil, unix: Date().timeIntervalSince1970,
                altDeg: pos.altDeg, azDeg: pos.azDeg,
                azCompass: RadiantAstrometry.compass(for: pos.azDeg), note: nil)
            let label = (pos.altDeg < 0)
                ? "辐射点 地平线下 \(String(format: "%.0f", abs(pos.altDeg)))°"
                : "辐射点 \(String(format: "%.0f", pos.altDeg))°"
            return (entry, label)
        }
        // 2) 时间轴插值（窗口外钳到端点并标注时次）
        let current = Self.interpolatedCurrent(entries: entries)
        let timeText = current.timeLocal.map { " \($0)" } ?? ""
        let label = "辐射点 \(String(format: "%.0f", current.altDeg ?? 0))°\(timeText)"
        return (current, label)
    }

    /// 按当前时间在 altaz_timeline 中线性插值
    static func interpolatedCurrent(entries: [Radiant.Horizontal.AltAzEntry]) -> Radiant.Horizontal.AltAzEntry {
        let dated = entries.compactMap { entry -> (Date, Radiant.Horizontal.AltAzEntry)? in
            entry.date.map { ($0, entry) }
        }.sorted { $0.0 < $1.0 }
        guard !dated.isEmpty else {
            return Radiant.Horizontal.AltAzEntry(timeLocal: nil, unix: nil, altDeg: nil, azDeg: nil, azCompass: nil, note: nil)
        }
        let now = Date()
        if now <= dated[0].0 { return dated[0].1 }
        if now >= dated[dated.count - 1].0 { return dated[dated.count - 1].1 }
        for (index, pair) in dated.enumerated() where index > 0 {
            if now <= pair.0 {
                let prev = dated[index - 1]
                let fraction = now.timeIntervalSince(prev.0) / pair.0.timeIntervalSince(prev.0)
                func lerp(_ a: Double?, _ b: Double?) -> Double? {
                    guard let a, let b else { return nil }
                    return a + (b - a) * fraction
                }
                return Radiant.Horizontal.AltAzEntry(
                    timeLocal: pair.1.timeLocal,
                    unix: pair.1.unix,
                    altDeg: lerp(prev.1.altDeg, pair.1.altDeg),
                    azDeg: lerp(prev.1.azDeg, pair.1.azDeg),
                    azCompass: pair.1.azCompass,
                    note: pair.1.note)
            }
        }
        return dated[dated.count - 1].1
    }

    /// 找最近时间点的 entry（用于轨迹绘制）
    static func entry(at date: Date, in entries: [Radiant.Horizontal.AltAzEntry]) -> Radiant.Horizontal.AltAzEntry {
        entries.min { abs(($0.date ?? .distantFuture).timeIntervalSince(date))
            < abs(($1.date ?? .distantFuture).timeIntervalSince(date)) } ?? entries[0]
    }
}
