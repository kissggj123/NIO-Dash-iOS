//
//  StargazingTripLiveActivity.swift
//  WheaterStatus
//
//  观星行程 灵动岛 / 锁屏实时活动：
//  · 锁屏卡：行程名 + 地点 + 距开始/结束倒计时（免刷新自走）+ 天气简报
//  · 灵动岛：compact 星空 icon + 倒计时；expanded 展示天气简报
//  点击深链回 App 主界面。
//

import WidgetKit
import SwiftUI
import ActivityKit

struct StargazingTripLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StargazingTripAttributes.self) { context in
            StargazingLockScreenView(state: context.state)
                .widgetURL(islandOpenAppURL)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.name)
                            .font(.caption.bold())
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.locationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        countdownLabel(state: state)
                        Spacer()
                        if let summary = state.weatherSummary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
            } compactTrailing: {
                countdownLabel(state: state)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
            }
        }
    }

    @ViewBuilder
    private func countdownLabel(state: StargazingTripAttributes.ContentState) -> some View {
        if state.isFinished {
            Text("已结束")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if Date() < state.startDate {
            Text(timerInterval: Date()...state.startDate, countsDown: true)
                .font(.caption2.monospacedDigit())
        } else {
            Text(timerInterval: Date()...max(state.endDate, Date().addingTimeInterval(1)), countsDown: true)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.green)
        }
    }
}

// MARK: - 锁屏卡片

struct StargazingLockScreenView: View {
    let state: StargazingTripAttributes.ContentState

    private var theme: WheaterThemeColors {
        WheaterThemeColors(themeRaw: state.themeRaw)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左：星空徽章
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.18))
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 38, height: 38)

            // 中：行程信息 + 倒计时
            VStack(alignment: .leading, spacing: 3) {
                Text(state.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(state.locationName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textSoft)
                    .lineLimit(1)

                if state.isFinished {
                    Text("观测窗口已结束")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSoft)
                } else if Date() < state.startDate {
                    HStack(spacing: 4) {
                        Text("距开始")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textSoft)
                        Text(timerInterval: Date()...state.startDate, countsDown: true)
                            .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: 130, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("观测中，距结束")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textSoft)
                        Text(timerInterval: Date()...max(state.endDate, Date().addingTimeInterval(1)), countsDown: true)
                            .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.green)
                            .frame(maxWidth: 130, alignment: .leading)
                    }
                }
            }

            Spacer(minLength: 0)

            // 右：天气简报
            if let summary = state.weatherSummary {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summary)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    if let cloud = state.cloudPct, let temp = state.tempC {
                        Text("\(cloud)% · \(String(format: "%.0f", temp))℃")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textSoft.opacity(0.8))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
