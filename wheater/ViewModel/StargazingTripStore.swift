//
//  StargazingTripStore.swift
//  wheater
//
//  观星行程仓库：JSON 导入（剪贴板/文件）、去重持久化、最近 upcoming 行程。
//

import Foundation
import SwiftUI
import ActivityKit

@MainActor
final class StargazingTripStore: ObservableObject {
    static let shared = StargazingTripStore()

    private static let archiveKey = "nio_stargazing_trips"

    @Published var trips: [StargazingTrip] = []
    /// 导入结果横幅文案（nil 表示无）
    @Published var importNotice: StargazingImportNotice?

    struct StargazingImportNotice: Equatable {
        var text: String
        var isError: Bool
    }

    private init() {
        loadArchive()
    }

    // MARK: - 持久化

    private func loadArchive() {
        guard let data = UserDefaults.standard.data(forKey: Self.archiveKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([StargazingTrip].self, from: data) {
            trips = decoded
        }
    }

    private func saveArchive() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(trips) {
            UserDefaults.standard.set(data, forKey: Self.archiveKey)
        }
    }

    // MARK: - 导入

    /// 解析一段 JSON 文本（单对象或对象数组），返回新增/覆盖的行程数量
    @discardableResult
    func importJSON(_ raw: String) throws -> Int {
        guard let data = raw.data(using: .utf8) else {
            throw StargazingImportError.encoding
        }
        // 智能解析：兼容 单对象 / 行程数组 / {events: [...]} 年历包裹 三种形态
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let payloads = try smartPayloads(from: any)

        let decoder = JSONDecoder()
        var parsed: [StargazingTrip] = []
        var parseErrors = 0
        for payload in payloads {
            if var trip = try? decoder.decode(StargazingTrip.self, from: payload) {
                applyIMOStaticFallback(&trip)
                parsed.append(trip)
            } else {
                parseErrors += 1
            }
        }
        guard !parsed.isEmpty else {
            throw StargazingImportError.notTripJSON(parseErrors: parseErrors)
        }

        // 去重：同 event_id 覆盖旧档
        var replaced = 0
        for trip in parsed {
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = trip
                replaced += 1
            } else {
                trips.append(trip)
            }
        }
        // 最近开始的排前面
        trips.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        saveArchive()

        let fresh = parsed.count - replaced
        importNotice = StargazingImportNotice(
            text: fresh > 0
                ? "已导入 \(parsed.count) 个行程" + (replaced > 0 ? "（更新 \(replaced) 个旧档）" : "")
                : "已更新行程「\(parsed[0].name)」",
            isError: false
        )
        return parsed.count
    }

    func delete(_ trip: StargazingTrip) {
        trips.removeAll { $0.id == trip.id }
        saveArchive()
    }

    // MARK: 智能导入规范化（schema 2.0-complete 年历 / 单行程 / 数组）

    /// 从任意 JSON 顶层形态提取事件字典列表（自动解包 events 包裹）
    private func smartPayloads(from any: Any) throws -> [Data] {
        let eventDicts: [[String: Any]]
        if let array = any as? [Any] {
            eventDicts = try array.compactMap(normalizeEvent)
        } else if let dict = any as? [String: Any] {
            if let events = dict["events"] as? [Any] {
                eventDicts = try events.compactMap(normalizeEvent)
            } else {
                eventDicts = [try normalizeEvent(dict)]
            }
        } else {
            throw StargazingImportError.unsupportedFormat
        }
        guard !eventDicts.isEmpty else {
            throw StargazingImportError.notTripJSON(parseErrors: 0)
        }
        return try eventDicts.map { try JSONSerialization.data(withJSONObject: $0) }
    }

    /// 单事件规范化：moon→moon_interference 别名、窗口时间补全、跳过原因入 tips
    private func normalizeEvent(_ any: Any) throws -> [String: Any] {
        guard var dict = any as? [String: Any] else {
            throw StargazingImportError.unsupportedFormat
        }

        // ① moon（新版）→ moon_interference（旧版键名）
        if let moon = dict["moon"] as? [String: Any] {
            var mi = (dict["moon_interference"] as? [String: Any]) ?? [:]
            if mi["phase"] == nil, let p = moon["phase"] { mi["phase"] = p }
            if mi["phase_desc"] == nil, let pd = moon["phase_desc"] { mi["phase_desc"] = pd }
            if mi["illumination_pct_at_peak"] == nil {
                if let v = (moon["illumination_pct_at_peak"] as? Double)
                    ?? (moon["illumination_pct"] as? Double) {
                    mi["illumination_pct_at_peak"] = v
                }
            }
            if mi["moonrise_local"] == nil, let mr = moon["moonrise_local"] as? String {
                mi["moonrise_local"] = mr
            }
            if mi["moonset_dec14_local"] == nil, let ms = moon["moonset_local"] as? String {
                mi["moonset_dec14_local"] = ms
            }
            dict["moon_interference"] = mi
        }

        // ② best_viewing_window 时间补全
        if let w = dict["best_viewing_window"] as? [String: Any] {
            dict["best_viewing_window"] = normalizeWindow(w, peak: dict["peak"] as? [String: Any])
        } else if let peak = dict["peak"] as? [String: Any],
                  let peakUnix = (peak["peak_unix"] as? NSNumber)?.doubleValue {
            // 无窗口但有峰值 → 以峰值为中心造一个窗口
            dict["best_viewing_window"] = [
                "start_unix": peakUnix - 5 * 3600,
                "end_unix": peakUnix + 5 * 3600,
                "display_range": (peak["peak_local"] as? String) ?? "",
            ]
        }

        // ③ reason_skip → 追加到 tips 保持可见
        if let skip = dict["reason_skip"] as? String, !skip.isEmpty {
            var tips = (dict["tips"] as? [String]) ?? []
            tips.insert("⚠️ 跳过建议：\(skip)", at: 0)
            dict["tips"] = tips
        }
        return dict
    }

    /// 窗口时间归一：数字时间戳、primary 镜像、display_range 文本推断
    private func normalizeWindow(_ window: [String: Any], peak: [String: Any]?) -> [String: Any] {
        var w = window
        // start_time/end_time 若是数字（新 schema），转 start_unix/end_unix
        if w["start_unix"] == nil, let n = w["start_time"] as? NSNumber { w["start_unix"] = n.doubleValue }
        if w["end_unix"] == nil, let n = w["end_time"] as? NSNumber { w["end_unix"] = n.doubleValue }

        // 镜像进 primary（模型优先读 primary）
        if w["primary"] == nil,
           let s = (w["start_unix"] as? NSNumber)?.doubleValue,
           let e = (w["end_unix"] as? NSNumber)?.doubleValue {
            w["primary"] = ["start_unix": s, "end_unix": e,
                            "display_range": (w["display_range"] as? String) ?? ""]
        }

        // 完全无时间：从 display_range / peak_local 文本推断
        if w["start_unix"] == nil {
            let rangeText = (w["display_range"] as? String)
                ?? (peak?["peak_local"] as? String) ?? ""
            if let (start, end) = parseRangeText(rangeText) {
                w["start_unix"] = start.timeIntervalSince1970
                w["end_unix"] = end.timeIntervalSince1970
                w["primary"] = ["start_unix": w["start_unix"]!, "end_unix": w["end_unix"]!,
                                "display_range": rangeText]
            } else if let peakUnix = (peak?["peak_unix"] as? NSNumber)?.doubleValue {
                w["start_unix"] = peakUnix - 5 * 3600
                w["end_unix"] = peakUnix + 5 * 3600
                w["primary"] = ["start_unix": w["start_unix"]!, "end_unix": w["end_unix"]!]
            }
        }
        return w
    }

    /// 解析 "2026-11-24 17:00 ~ 2026-11-25 03:00" / "2026-11-25 全夜" / "2026-11-26 黎明前" / "12-14 21:30 ~ 12-15 05:00"
    private func parseRangeText(_ text: String) -> (Date, Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        // 拆分起止段
        let parts = text.components(separatedBy: "~").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = parts.first, !head.isEmpty else { return nil }
        let tail = parts.count > 1 ? parts[1] : nil

        func component(_ regex: String, in text: String) -> String? {
            text.range(of: regex, options: .regularExpression).map { String(text[$0]) }
        }
        // 年月日（第二段允许只有 MM-dd，继承第一段年份）
        let headDate = component(#"\d{4}-\d{2}-\d{2}"#, in: head)
        let headTime = component(#"\d{2}:\d{2}"#, in: head)
        guard let headDate else { return nil }
        let headParts = headDate.split(separator: "-").compactMap { Int($0) }
        guard headParts.count == 3 else { return nil }
        var startComps = DateComponents(year: headParts[0], month: headParts[1], day: headParts[2])
        if let headTime {
            let t = headTime.split(separator: ":").compactMap { Int($0) }
            startComps.hour = t.first ?? 20
            startComps.minute = t.count > 1 ? t[1] : 0
        } else if head.contains("黎明") {
            startComps.hour = 5
        } else {
            startComps.hour = 20
        }
        guard let start = calendar.date(from: startComps) else { return nil }

        var endComps = DateComponents()
        if let tail {
            let tailDateFull = component(#"\d{4}-\d{2}-\d{2}"#, in: tail)
            let tailDateShort = component(#"\d{2}-\d{2}\b"#, in: tail) ?? component(#"\b\d{2}-\d{2}"#, in: tail)
            let tailTime = component(#"\d{2}:\d{2}"#, in: tail)
            if let full = tailDateFull {
                let p = full.split(separator: "-").compactMap { Int($0) }
                endComps.year = p.first; endComps.month = p.count > 1 ? p[1] : nil; endComps.day = p.count > 2 ? p[2] : nil
            } else if let short = tailDateShort {
                let p = short.split(separator: "-").compactMap { Int($0) }
                if p.count == 2 {
                    endComps.year = headParts[0]
                    endComps.month = p[0] < (startComps.month ?? 0) ? headParts[0] + 1 : headParts[0]
                    endComps.day = p[1]
                }
            }
            if let tailTime {
                let t = tailTime.split(separator: ":").compactMap { Int($0) }
                endComps.hour = t.first ?? 5
                endComps.minute = t.count > 1 ? t[1] : 0
            } else {
                endComps.hour = 5; endComps.minute = 0
            }
        }
        if endComps.year == nil && endComps.month == nil && endComps.day == nil {
            return (start, start.addingTimeInterval(10 * 3600))
        }
        return (start, calendar.date(from: endComps) ?? start.addingTimeInterval(10 * 3600))
    }

    /// IMO 静态年历兜底：JSON 缺 ZHR/辐射点赤经赤纬/母体时按星座/名称补齐
    /// （ZHR/极大时刻/辐射点无实时 API，IMO 即静态年历）
    private func applyIMOStaticFallback(_ trip: inout StargazingTrip) {
        guard let imo = StargazingLocalAstronomy.imoMatch(
            constellation: trip.constellation, name: trip.name) else { return }
        if trip.zhr == nil { trip.zhr = imo.zhr }
        if trip.parentBody == nil { trip.parentBody = imo.parent }
        if trip.radiant?.equatorial == nil {
            let eq = Radiant.Equatorial(raDeg: imo.raDeg, decDeg: imo.decDeg)
            if trip.radiant == nil {
                trip.radiant = Radiant(horizontal: nil, equatorial: eq)
            } else {
                trip.radiant?.equatorial = eq
            }
        }
    }

    /// 距离最近的未结束行程
    var nearestUpcomingTrip: StargazingTrip? {
        trips
            .filter { $0.isUpcoming }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
}

enum StargazingImportError: LocalizedError {
    case encoding
    case unsupportedFormat
    case notTripJSON(parseErrors: Int)

    var errorDescription: String? {
        switch self {
        case .encoding:
            return "无法读取文本内容（编码错误）"
        case .unsupportedFormat:
            return "内容不是 JSON 对象或数组"
        case .notTripJSON:
            return "JSON 已识别，但缺少观测计划字段（如 name / best_viewing_window）"
        }
    }
}

// MARK: - 观星行程实时活动管理

@MainActor
final class StargazingTripActivityManager: ObservableObject {
    static let shared = StargazingTripActivityManager()

    @Published var activeActivityID: String?
    @Published var lastResult: String?
    @Published var isError = false

    private var activity: Activity<StargazingTripAttributes>?

    /// 当前已启动实时活动的行程 ID（App 重启后重新发现）
    func discoverExistingActivities() async {
        for running in Activity<StargazingTripAttributes>.activities {
            if let existing = activity, running.id == existing.id { continue }
            activity = running
            activeActivityID = running.attributes.tripID
        }
    }

    var isRunning: Bool { activity != nil }

    /// 启动最近行程实时活动（倒计时自走，天气稍后 update）
    func startActivity(trip: StargazingTrip, themeRaw: String?) async {
        guard let start = trip.startDate, let end = trip.endDate else {
            lastResult = "行程缺少观测窗口起止时间"
            isError = true
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastResult = "实时活动已被系统禁用，请在设置中开启"
            isError = true
            return
        }
        // 已在展示别的行程：先结束
        await endCurrentActivity()

        let attributes = StargazingTripAttributes(tripID: trip.id)
        let state = StargazingTripAttributes.ContentState(
            name: trip.name,
            locationName: trip.calendarEvent?.location ?? trip.primaryLocation?.name ?? "观测点",
            startDate: start,
            endDate: end,
            weatherSummary: nil, cloudPct: nil, tempC: nil,
            seeingText: nil, transparencyText: nil,
            themeRaw: themeRaw,
            isFinished: end < Date())
        do {
            let launched = try Activity<StargazingTripAttributes>.request(
                attributes: attributes,
                content: .init(state: state, staleDate: end.addingTimeInterval(600)))
            activity = launched
            activeActivityID = trip.id
            lastResult = "已加入实时活动"
            isError = false
        } catch {
            lastResult = "实时活动启动失败：\(error.localizedDescription)"
            isError = true
        }
    }

    /// 天气拉取成功后刷新简报
    func updateWeather(report: StargazingWeatherReport, themeRaw: String?) async {
        guard let activity else { return }
        let state = activity.contentState
        let newState = StargazingTripAttributes.ContentState(
            name: state.name,
            locationName: state.locationName,
            startDate: state.startDate,
            endDate: state.endDate,
            weatherSummary: report.summaryLine,
            cloudPct: report.cloudCoverPct.map { Int($0.rounded()) },
            tempC: report.temperatureC,
            seeingText: report.seeingText,
            transparencyText: report.transparencyText,
            themeRaw: themeRaw,
            isFinished: state.endDate < Date())
        guard newState.fingerprint != state.fingerprint else { return }
        await activity.update(using: newState)
    }

    /// 主题换装：App 内切换主题后，热更新正在展示的实时活动配色
    func updateTheme(_ themeRaw: String?) async {
        guard let activity else { return }
        var state = activity.contentState
        guard state.themeRaw != themeRaw else { return }
        state.themeRaw = themeRaw
        await activity.update(ActivityContent(state: state, staleDate: state.endDate.addingTimeInterval(600)))
    }

    /// 结束当前实时活动
    func endCurrentActivity() async {
        guard let activity else { return }
        var state = activity.contentState
        state.isFinished = true
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .immediate)
        self.activity = nil
        activeActivityID = nil
    }
}
