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
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json, .item],
                          allowsMultipleSelection: false) { result in
                handleFileImport(result)
            }
            .navigationDestination(item: $selectedTrip) { trip in
                StargazingTripDetailView(trip: trip)
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
                    Task { await StargazingCalendarService.shared.saveToCalendar(trip: trip) }
                } label: {
                    Label("添加到日历", systemImage: "calendar.badge.plus")
                        .font(.caption.bold())
                }
                .buttonStyle(NIOPressableButtonStyle())
                .tint(NIOThemePaint.accent)
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
    let trip: StargazingTrip

    @ObservedObject private var weather = StargazingWeatherService.shared
    @ObservedObject private var calendar = StargazingCalendarService.shared
    @AppStorage("nio_stargazing_red_mode") private var stargazingRedMode = false
    @State private var showEnvCards = true

    var body: some View {
        ZStack {
            NIOThemePaint.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard
                    countdownCard
                    envCards
                    starMapCard
                    locationsCard
                    timelineCard
                    tipsCard
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

    // MARK: 环境卡片组（月光 / 天气矩阵）

    private var envCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("观测环境", systemImage: "cloud.moon")
                    .font(.subheadline.bold())
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Button {
                    Task { _ = await weather.fetchWeather(for: trip) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .disabled(weather.reportByTripID[trip.id] != nil && !weather.reportByTripID[trip.id]!.isStale)
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
        let moonrise = report?.moonriseText ?? jsonMoon?.moonsetDec14Local?.replacingOccurrences(of: "^月落 ", with: "")
        let moonset = report?.moonsetText
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
        VStack(spacing: 2) {
            Label(label, systemImage: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NIOThemePaint.textSoft)
                .lineLimit(1)
            if isText {
                Text(value == nil ? (unit == "—" ? "—" : unit) : unit)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .lineLimit(1)
            } else if let value {
                Text("\(value.formatted(.number.precision(.fractionLength(digits == 0 ? 0 : 1))))\(unit)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.textSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 130, alignment: .trailing)
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
    case general

    init(from type: String) {
        let text = type.lowercased()
        if text.contains("meteor") || text.contains("流星") || text.contains("shower") {
            self = .meteorShower
        } else if text.contains("aurora") || text.contains("极光") {
            self = .aurora
        } else if text.contains("bird") || text.contains("鸟") || text.contains("migration") || text.contains("迁徙") {
            self = .birding
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
        case .general: return "star"
        }
    }

    var label: String {
        switch self {
        case .meteorShower: return "流星雨"
        case .aurora: return "极光"
        case .birding: return "观鸟"
        case .deepSky: return "观星"
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
        }
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
