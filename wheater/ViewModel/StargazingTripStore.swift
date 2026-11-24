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
        loadImportRules()
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

    // MARK: - 解析规则（导入补全记忆）

    /// event_id → 字段覆盖规则：UI 补全控件保存后持久化，
    /// 再次导入同 event_id 的 JSON 时自动合并，缺失字段无需重复补全
    private static let importRulesKey = "nio_stargazing_import_rules"
    private var importRuleDicts: [String: [String: Any]] = [:]

    private func loadImportRules() {
        guard let data = UserDefaults.standard.data(forKey: Self.importRulesKey),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        importRuleDicts = obj
    }

    private func persistImportRules() {
        if let data = try? JSONSerialization.data(withJSONObject: importRuleDicts) {
            UserDefaults.standard.set(data, forKey: Self.importRulesKey)
        }
    }

    /// 把已保存的补全规则深合并进原始 JSON 字典（规则优先，保留原 JSON 未覆盖字段）
    private func applyImportRule(to dict: inout [String: Any]) {
        guard let eventID = dict["event_id"] as? String,
              let rule = importRuleDicts[eventID] else { return }
        deepMerge(rule, into: &dict)
    }

    private func deepMerge(_ source: [String: Any], into target: inout [String: Any]) {
        for (key, value) in source {
            if let srcDict = value as? [String: Any],
               let dstDict = target[key] as? [String: Any] {
                var merged = dstDict
                deepMerge(srcDict, into: &merged)
                target[key] = merged
            } else {
                target[key] = value
            }
        }
    }

    /// 保存某行程的补全规则（导入后补全控件调用）
    func saveImportRule(eventID: String, overrides: [String: Any]) {
        importRuleDicts[eventID] = overrides
        persistImportRules()
    }

    /// 手动编辑行程：替换同 ID 行程并按窗口时间重排序落盘
    func updateTrip(_ updated: StargazingTrip) {
        guard let idx = trips.firstIndex(where: { $0.id == updated.id }) else { return }
        trips[idx] = updated
        trips.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        saveArchive()
    }

    /// 字段补全：把补全 JSON 深合并进行程原始编码，重解码回写，并保存为解析规则
    @discardableResult
    func applyCompletion(_ completion: [String: Any], to trip: StargazingTrip) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try encoder.encode(trip)
            guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            deepMerge(completion, into: &dict)
            let merged = try JSONSerialization.data(withJSONObject: dict)
            let updated = try decoder.decode(StargazingTrip.self, from: merged)
            updateTrip(updated)
            saveImportRule(eventID: trip.id, overrides: completion)
            return true
        } catch {
            importNotice = .init(text: "补全失败：\(error.localizedDescription)", isError: true)
            return false
        }
    }

    // MARK: - 导入

    /// 解析一段 JSON 文本（单对象或对象数组），返回新增/覆盖的行程数量
    @discardableResult
    func importJSON(_ raw: String) throws -> Int {
        guard let data = Self.sanitizeJSONText(raw).data(using: .utf8) else {
            throw StargazingImportError.encoding
        }
        // 车辆凭证误贴保护：给出明确路由提示而不是"不像是观星行程 JSON"
        if NIOVehicleLib.classifySmartText(raw) == .vehicleCapture {
            throw StargazingImportError.vehicleCaptureDetected
        }
        // 智能解析：兼容 单对象 / 行程数组 / {events: [...]} 年历包裹 / 智能备份整包 四种形态
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        // 智能备份导出的整包 JSON：从 defaults 提取观星行程存档与解析规则一并恢复
        if let obj = any as? [String: Any], obj["backup_version"] != nil,
           let defaults = obj["defaults"] as? [String: Any] {
            // 解析规则（补全记忆）随备份迁移
            if let ruleData = Self.tripArchiveData(from: defaults["nio_stargazing_import_rules"]),
               let ruleObj = try? JSONSerialization.jsonObject(with: ruleData) as? [String: [String: Any]] {
                for (id, rule) in ruleObj where importRuleDicts[id] == nil {
                    importRuleDicts[id] = rule
                }
                persistImportRules()
            }
            guard let archiveData = Self.tripArchiveData(from: defaults["nio_stargazing_trips"]),
                  let backupTrips = try? JSONDecoder.stargazing.decode([StargazingTrip].self, from: archiveData),
                  !backupTrips.isEmpty else {
                throw StargazingImportError.notTripJSON(parseErrors: 0)
            }
            return commitTrips(backupTrips, sourceLabel: "智能备份")
        }

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

        // 去重：同 event_id → 更新合并（新 JSON 缺失字段保留旧档已补全内容）；否则新建
        return commitTrips(parsed)
    }

    /// 入库去重合并 + 结果横幅（常规导入与备份提取共用）
    @discardableResult
    private func commitTrips(_ parsed: [StargazingTrip], sourceLabel: String? = nil) -> Int {
        var added = 0
        var updated = 0
        for trip in parsed {
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                trips[index] = Self.fillMissing(from: trips[index], onto: trip)
                updated += 1
            } else {
                trips.append(trip)
                added += 1
            }
        }
        // 最近开始的排前面
        trips.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        saveArchive()

        lastImportAdded = added
        lastImportUpdated = updated
        let prefix = sourceLabel.map { "\($0)：" } ?? ""
        importNotice = StargazingImportNotice(
            text: added > 0 && updated > 0
                ? "\(prefix)导入成功：新增 \(added) 个，更新补全 \(updated) 个"
                : added > 0
                    ? "\(prefix)已成功导入 \(added) 个新行程"
                    : "\(prefix)已更新补全 \(updated) 个行程（缺失字段保留旧档内容）",
            isError: false
        )
        return parsed.count
    }

    /// 从智能备份 defaults 中提取观星行程存档（base64 字符串或原始数组两种形态）
    private static func tripArchiveData(from value: Any?) -> Data? {
        switch value {
        case let s as String:
            return Data(base64Encoded: s)
        case let list as [[String: Any]]:
            return try? JSONSerialization.data(withJSONObject: list)
        default:
            return nil
        }
    }

    /// 备份恢复的观星部分：行程去重合并入库 + 解析规则合并，返回恢复的行程数
    @discardableResult
    func restoreBackupStargazing(from defaults: [String: Any]) -> Int {
        var restoredCount = 0
        if let ruleData = Self.tripArchiveData(from: defaults["nio_stargazing_import_rules"]),
           let ruleObj = try? JSONSerialization.jsonObject(with: ruleData) as? [String: [String: Any]] {
            for (id, rule) in ruleObj where importRuleDicts[id] == nil {
                importRuleDicts[id] = rule
                restoredCount += 1
            }
            persistImportRules()
        }
        if let archiveData = Self.tripArchiveData(from: defaults["nio_stargazing_trips"]),
           let backupTrips = try? JSONDecoder.stargazing.decode([StargazingTrip].self, from: archiveData),
           !backupTrips.isEmpty {
            restoredCount += commitTrips(backupTrips, sourceLabel: "备份恢复")
        }
        return restoredCount
    }

    /// JSON 文本清洗：去 BOM / 首尾空白；非纯 JSON（如编辑器加了前后缀）时截取最外层花括号块
    nonisolated static func sanitizeJSONText(_ raw: String) -> String {
        var text = raw
        for bom in ["\u{FEFF}", "\u{FFFE}"] {
            if text.hasPrefix(bom) { text.removeFirst() }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return trimmed }
        // 编辑器包裹/聊天粘贴带前缀文本 → 定位第一个 { 或 [ 与最后一个 } 或 ]
        if let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = trimmed.lastIndex(where: { $0 == "}" || $0 == "]" }), start < end {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    /// 导入结果计数（供分享导入/跳转提示使用）
    @Published var lastImportAdded = 0
    @Published var lastImportUpdated = 0

    /// 更新合并：以新档为底，旧档中非空字段填补新档缺失（递归字典；数组整体取舍）
    static func fillMissing(from old: StargazingTrip, onto newTrip: StargazingTrip) -> StargazingTrip {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let oldData = try? encoder.encode(old), var oldDict = try? JSONSerialization.jsonObject(with: oldData) as? [String: Any],
            let newData = try? encoder.encode(newTrip), var newDict = try? JSONSerialization.jsonObject(with: newData) as? [String: Any]
        else { return newTrip }
        fillMissingDict(from: oldDict, into: &newDict)
        guard let merged = try? JSONSerialization.data(withJSONObject: newDict),
              let mergedTrip = try? decoder.decode(StargazingTrip.self, from: merged) else { return newTrip }
        return mergedTrip
    }

    private static func fillMissingDict(from old: [String: Any], into newDict: inout [String: Any]) {
        for (key, oldValue) in old {
            let currentValue = newDict[key]
            if currentValue == nil || currentValue is NSNull {
                if !(oldValue is NSNull) { newDict[key] = oldValue }
            } else if let oldSub = oldValue as? [String: Any], let newSub = currentValue as? [String: Any] {
                var mergedSub = newSub
                fillMissingDict(from: oldSub, into: &mergedSub)
                newDict[key] = mergedSub
            }
        }
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

    /// 单事件规范化：规则合并 → moon→moon_interference 别名、窗口时间补全、跳过原因入 tips
    private func normalizeEvent(_ any: Any) throws -> [String: Any] {
        guard var dict = any as? [String: Any] else {
            throw StargazingImportError.unsupportedFormat
        }

        // ⓪ 已保存的补全规则优先合并（含结构不同的未知字段场景）
        applyImportRule(to: &dict)

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

        // ② coordinates.target → radiant 镜像（行星/月亮等非流星雨事件的天体位置）
        if dict["radiant"] == nil,
           let coords = dict["coordinates"] as? [String: Any],
           let target = coords["target"] as? [String: Any] {
            var radiant: [String: Any] = ["name": (target["name"] as? String) ?? ""]
            if let eq = target["equatorial"] { radiant["equatorial"] = eq }
            if let hz = target["horizontal"] { radiant["horizontal"] = hz }
            dict["radiant"] = radiant
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

        // ④ observation / objects / near_objects → tips（保留观测指南与邻近天体信息）
        var guideTips = (dict["tips"] as? [String]) ?? []
        if let obs = dict["observation"] as? [String: Any] {
            if let eq = obs["equipment"] as? String { guideTips.append("🛠 装备：\(eq)") }
            if let dir = obs["direction"] as? String { guideTips.append("🧭 方位：\(dir)") }
            if let finder = obs["finder"] as? String { guideTips.append("📍 定位：\(finder)") }
        }
        if let objects = dict["objects"] as? [[String: Any]] {
            for obj in objects {
                guard let name = obj["name"] as? String else { continue }
                var line = "🔭 \(name)"
                if let mag = obj["magnitude"] { line += "（\(mag)等）" }
                if let dir = obj["direction"] as? String { line += "：\(dir)" }
                guideTips.append(line)
            }
        }
        if let near = dict["near_objects"] as? [String: Any] {
            for (_, value) in near {
                if let text = value as? String { guideTips.append("✦ \(text)") }
            }
        }
        // 仅在收集到内容时写入，避免部分 JSON 重导入把旧档 tips 冲掉（fillMissing 依赖"字段缺失"才保留旧值）
        if !guideTips.isEmpty { dict["tips"] = guideTips }
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
    case vehicleCaptureDetected

    var errorDescription: String? {
        switch self {
        case .encoding:
            return "无法读取文本内容（编码错误）"
        case .vehicleCaptureDetected:
            return "识别为车辆抓包凭证（Token/URL），请到设置页「智能识别与一键填充」粘贴"
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

/// 分享导入成功后请求打开观星界面（Dashboard 监听）
extension Notification.Name {
    static let stargazingOpenRequest = Notification.Name("stargazing_open_request")
}

/// 观星存档统一编解码配置（iso8601 日期）
extension JSONDecoder {
    static let stargazing: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
