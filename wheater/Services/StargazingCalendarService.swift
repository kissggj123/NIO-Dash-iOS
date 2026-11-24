//
//  StargazingCalendarService.swift
//  wheater
//
//  观星行程 → 系统日历（EventKit）：
//  · 按 calendar_event 构建 EKEvent（标题/地点/备注/起止）
//  · alarms trigger（ISO8601 duration 如 -PT3H）→ EKAlarm
//  · 无 alarms 时默认提前 1 小时提醒
//

import Foundation
import EventKit

@MainActor
final class StargazingCalendarService: ObservableObject {
    static let shared = StargazingCalendarService()

    private let eventStore = EKEventStore()

    @Published var lastResult: String?
    @Published var isError = false

    func saveToCalendar(trip: StargazingTrip) async {
        guard let event = trip.calendarEvent,
              let startDate = event.startDate,
              let endDate = event.endDate else {
            lastResult = "行程 JSON 缺少 calendar_event 起止时间"
            isError = true
            return
        }

        // iOS 17+ 只写权限
        let granted: Bool
        do {
            granted = try await eventStore.requestWriteOnlyAccessToEvents()
        } catch {
            lastResult = "日历权限请求失败：\(error.localizedDescription)"
            isError = true
            return
        }
        guard granted else {
            lastResult = "未获得日历写入权限，请在系统设置中开启"
            isError = true
            return
        }

        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = event.summary ?? "\(trip.name) 观星"
        ekEvent.location = event.location
        ekEvent.notes = event.description ?? trip.tips.joined(separator: "\n· ")
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.calendar = eventStore.defaultCalendarForNewEvents

        // 提醒：JSON alarms 优先，否则默认提前 1 小时
        let offsets = alarmOffsets(event.alarms)
        let relative = offsets ?? [-3600]
        for offset in relative {
            ekEvent.addAlarm(EKAlarm(relativeOffset: offset))
        }

        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            lastResult = "已加入系统日历：\(ekEvent.title ?? "")"
            isError = false
        } catch {
            lastResult = "日历保存失败：\(error.localizedDescription)"
            isError = true
        }
    }

    /// "-PT3H" / "-PT30M" → relativeOffset 秒（负数=提前）
    private func alarmOffsets(_ alarms: [StargazingCalendarEvent.Alarm]) -> [TimeInterval]? {
        let offsets = alarms.compactMap { alarm -> TimeInterval? in
            guard let trigger = alarm.trigger else { return nil }
            return Self.parseISODuration(trigger)
        }
        return offsets.isEmpty ? nil : offsets
    }

    /// 解析 ISO8601 duration（仅 PTnH/PTnM/PTnS 组合，带负号表示提前）
    static func parseISODuration(_ text: String) -> TimeInterval? {
        var sign = 1.0
        var body = text.trimmingCharacters(in: .whitespaces).uppercased()
        if body.hasPrefix("-") {
            sign = -1.0
            body.removeFirst()
        }
        guard body.hasPrefix("PT") else { return nil }
        body.removeFirst(2)

        var seconds = 0.0
        var number = ""
        for ch in body {
            if ch.isNumber {
                number.append(ch)
            } else {
                guard let value = Double(number) else { return nil }
                switch ch {
                case "H": seconds += value * 3600
                case "M": seconds += value * 60
                case "S": seconds += value
                default: return nil
                }
                number = ""
            }
        }
        guard number.isEmpty else { return nil }
        return sign * seconds
    }
}
