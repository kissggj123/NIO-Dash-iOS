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
        // 先探明是数组还是单对象
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let payloads: [Data]
        if let array = any as? [Any] {
            payloads = try array.map { try JSONSerialization.data(withJSONObject: $0) }
        } else if let dict = any as? [String: Any] {
            payloads = [try JSONSerialization.data(withJSONObject: dict)]
        } else {
            throw StargazingImportError.unsupportedFormat
        }

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
