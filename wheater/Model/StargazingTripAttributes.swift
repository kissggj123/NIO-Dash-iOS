//
//  StargazingTripAttributes.swift
//  wheater
//
//  观星行程 实时活动 (Live Activity) 数据属性模型。
//  本文件同时编译进 App 与 Widget Extension 两个 target。
//

import SwiftUI
import ActivityKit

struct StargazingTripAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var name: String
        var locationName: String
        var startDate: Date
        var endDate: Date

        // 天气简报（Open-Meteo + 7Timer 拉取成功后更新）
        var weatherSummary: String?
        var cloudPct: Int?
        var tempC: Double?
        var seeingText: String?
        var transparencyText: String?

        var themeRaw: String?    // 跟随全局主题换装
        var isFinished: Bool

        /// 状态指纹（去重，避免无意义刷新）
        var fingerprint: String {
            [
                name,
                locationName,
                "\(Int(startDate.timeIntervalSince1970 / 60))",
                weatherSummary ?? "-",
                themeRaw ?? "-",
                isFinished ? "1" : "0"
            ].joined(separator: "|")
        }
    }

    var tripID: String
}
