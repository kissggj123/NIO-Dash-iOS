# 观星行程功能实现计划

## Context

用户提供了一份专业修正过的双子座流星雨观测 JSON（schema_version 2.0.0-corrected，含 best_viewing_window / calendar_event / itinerary_segment / atmosphere / radiant / recommended_locations 等）。要在 YumikoToysRR App 中新增"观星行程"功能：

1. **行程导入**：支持剪贴板粘贴 JSON 解析 + 文件导入（fileImporter），宽容解码，后续可重复导入
2. **实时天气**：接入 Open-Meteo（16 天，填分层云量/温度/湿度/风/气压）+ 7Timer! ASTRO（3 天，填 seeing/transparency），均免 key；API 打满时直连（不经代理，用 URLSession 默认即可，不做代理处理）
3. **实时活动**：最近行程加入灵动岛/锁屏卡（倒计时 Text(timerInterval:) 免刷新自走 + 天气简报）
4. **系统日历**：按 JSON 中 calendar_event（含 alarms）写入 EventKit
5. **入口**：主界面工具栏 + 设置页各一处

用户已确认：入口两处都加；实时活动侧重"倒计时 + 天气简报"。

## 新增文件（6 个）

### 1. `wheater/Model/StargazingTrip.swift`（App target）
- `StargazingTrip: Codable, Identifiable`，宽容解码（decodeIfPresent + 容错 key）：解析上传 JSON 的关键字段：
  - `name/nameEn/constellation/type/zhr/observationScore/parentBody`
  - `bestViewingWindow.primary/secondary`（start_unix/end_unix/label/display_range）
  - `calendarEvent`（summary/description/location/location_coordinates/dtstart_unix/dtend_unix/alarms[trigger/alarm_local/description]）
  - `itinerarySegment.timeline[]`（time_local/unix/action/phase）
  - `recommendedLocations[]`（name/lat/lng/bortle_class/expected_meteors_per_hour_dark）
  - `radiant.horizontal`（altaz_timeline[]、culmination）、`moonInterference`（illumination/moonset/impact_level）、`sunTwilightShanghai`、`tips[]`、`atmosphere`（占位结构 + API 模板）
  - 未知字段忽略（`JSONDecoder` + 手写 `init(from:)` 按需 decodeIfPresent）
- 持久化：trip 数组 JSON 存 `UserDefaults.standard`，key `nio_stargazing_trips`（沿用 nio_ 前缀约定）
- `var startDate/endDate: Date`、`var isUpcoming`、`var primaryLocation` 等计算属性

### 2. `wheater/ViewModel/StargazingTripStore.swift`（App target）
- `@MainActor final class StargazingTripStore: ObservableObject`：
  - `@Published var trips: [StargazingTrip]`（加载/保存 UserDefaults）
  - `func importJSON(_ text: String) throws -> StargazingTrip`（先按 utf8 修剪，JSONSerialization 校验后解码；支持数组或单对象；重复 event_id 去重覆盖）
  - `var nearestUpcomingTrip: StargazingTrip?`（按 endDate 在未来的最近一个）
  - 导入成功/失败结果回传 UI 横幅

### 3. `wheater/Services/StargazingWeatherService.swift`（App target）
- `@MainActor final class StargazingWeatherService: ObservableObject`
- `func fetchWeather(for trip: StargazingTrip) async throws -> StargazingWeatherReport`
  - **Open-Meteo**：`https://api.open-meteo.com/v1/forecast?latitude=&longitude=&hourly=temperature_2m,relative_humidity_2m,dew_point_2m,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,wind_speed_10m,wind_direction_10m,surface_pressure&timezone=Asia%2FShanghai&forecast_days=16`；按行程窗口取小时切片求均值/区间
  - **7Timer! ASTRO**：`https://www.7timer.info/bin/api.pl?lon=&lat=&product=astro&output=json`；cloudcover 1-9 档、seeing 1-8 档（1=最好）、transparency 1-8 档（1=最好）映射为中文等级文案；取行程窗口内最近时次
- 缓存：同坐标同窗口 30 分钟内存缓存 + UserDefaults 磁盘缓存（key `nio_stargazing_weather_cache`），避免高频刷新打满限额
- `@Published var reportByTripID: [String: StargazingWeatherReport]`、错误信息透出（含"API 限额已满请稍后再试"提示）
- `struct StargazingWeatherReport: Codable`（云量总/低/中/高、温度、湿度、露点、风速风向、气压、seeing/transparency 等级与原始档位、fetch 时间、来源标记）

### 4. `wheater/Model/StargazingTripAttributes.swift`（**双 target：App + WheaterStatus**，仿 WheaterAttributes.swift）
- `StargazingTripAttributes: ActivityAttributes`：静态字段 `tripID: String`
- `ContentState: Codable, Hashable`：
  - `name`, `locationName`, `startDate: Date`, `endDate: Date`
  - `weatherSummary: String?`（如 "☁️ 12% · 3℃ · 视宁度 2\""),
  - `cloudPct: Int?`, `tempC: Double?`, `seeingText: String?`, `transparencyText: String?`
  - `themeRaw: String?`（跟随全局主题）
  - `isFinished: Bool`

### 5. `WheaterStatus/StargazingTripLiveActivity.swift`（WheaterStatus target，pbxproj 注册）
- `StargazingTripLiveActivityWidget: Widget`，`ActivityConfiguration(for: StargazingTripAttributes.self)`
- 锁屏卡：行程名 + 地点 + `Text(context.state.startDate, style: .relative)` 倒计时 + 天气简报行；结束后显示"观测已结束"
- 灵动岛：compact leading 星空 icon + 倒计时，expanded 显示天气简报；深链 `yumikotoysrr://open-dashboard`
- 在 `WheaterStatus.swift` 的 `WheaterStatusBundle` body 追加 `StargazingTripLiveActivityWidget()`

### 6. `wheater/Views/NIO/IOSStargazingTripView.swift`（App target）
- 主列表页：行程卡（名称/极大时刻/观测评分/地点 tag）、导入按钮（📋 从剪贴板导入 + 从文件导入 `fileImporter`，type: .json/.item）、删除（swipe）
- 行程详情（按用户补充的 UI 规格）：
  - **顶部：观测质量环形仪表盘**——Canvas/Gauge 环形渲染 `observationScore`（94 分），按分数段动态切换高光渐变色（≥90 金橙 / 75-89 绿 / 60-74 蓝 / <60 灰），中心显示分数与 ZHR
  - **动态星图与辐射点方位指示器**——Canvas 绘制 360° 方位罗盘 + 地平线弧：根据当前时间在 `radiant.horizontal.altaz_timeline` 插值出辐射点实时高度角/方位角，指针 + 光晕标出当前位置；下方列表展示逐时次 alt/az/compass/note
  - **最佳观测倒计时**——解析 `best_viewing_window.primary.start_time`，显示 天/时/分 倒计时（`Text(date, style: .relative)` 免刷新自走）
  - **一键"添加到系统日历" Action Button** → `StargazingCalendarService`（默认提前 1 小时提醒；若 JSON 自带 alarms 则合并写入）
  - **观测环境卡片组**（Tab/横滑卡片）：
    - 月光干扰卡：月相 emoji + 照明度百分比 + 月落时间 + impact_level 徽章
    - 实时天气矩阵卡：网格展示云量/透光度/视宁度/气温/湿度/AQI（AQI 无免费实时源，先用 JSON 内值占位并标注"静态"），右上角刷新按钮调 API（见 StargazingWeatherService）
  - **推荐观测点列表**：卡片式展示 recommendedLocations，Bortle 1-9 徽章按暗空色标着色（1 深黑→9 亮黄）；点击卡片 → MapKit `MKMapItem.openInMaps` 调起系统导航（或 `MKDirections` 显示路线）
  - 行程 timeline 卡（itinerary_segment）+ 观测建议 tips
  - **红光护眼模式（Night Vision Mode）**：详情页 toolbar 灯泡按钮一键切换，整屏叠加 `Color.red.opacity` 高对比暗红阶滤镜（所有前景色强制红色调、禁用彩色高亮），状态持久化 `nio_stargazing_red_mode`；参考实时活动 LA 规则避免影响其他页面
- 操作按钮（仅最近一个 upcoming 行程）：
  - **加入实时活动** → `StargazingTripActivityManager.shared.startActivity(trip)`；已启动则变"更新天气/结束活动"
- `@MainActor final class StargazingTripActivityManager`（放本文件或 Store 内）：`Activity<StargazingTripAttributes>` request/update/end，天气拉取成功后自动 update 一次

### 7. `wheater/Services/StargazingCalendarService.swift`（App target）
- `EKEventStore`：iOS 17+ `requestWriteOnlyAccessToEvents`；构建 EKEvent（title=calendar_event.summary, location=location, notes=description, startDate=dtstart_unix, endDate=dtend_unix, 地点坐标不加）；alarms 转换 `PT` ISO8601 duration 解析
- 保存成功/失败回传给 UI

## 修改的现有文件

| 文件 | 改动 |
|---|---|
| `wheater/Views/NIO/IOSNIODashboardView.swift` | iPhone 工具栏加星空按钮（`sparkles`）→ `.sheet` 展示 IOSStargazingTripView；iPad splitLayout 侧栏加"观星行程"项或同 toolbar 按钮 |
| `wheater/Views/NIO/IOSNIOConfigView.swift` | 设置页加"观星行程"入口 section（仿恋爱实验室入口写法） |
| `WheaterStatus/WheaterStatus.swift` | WidgetBundle 追加 StargazingTripLiveActivityWidget |
| `wheater/Info.plist` | 加 `NSCalendarsWriteOnlyAccessUsageDescription`（"用于将观星行程与出发提醒写入系统日历"） |
| `YumikoToysRR.xcodeproj/project.pbxproj` | 手动注册 6 个新文件（PBXBuildFile + PBXFileReference + group child + Sources phase；StargazingTripAttributes.swift 需同时注册进 App 与 WheaterStatus 两个 target，参照 WheaterAttributes.swift 的双 build file id 模式） |

## 关键复用

- 主题：详情页取色走现有 `NIOThemePaint` / `AnimeThemeService.shared`；ContentState.themeRaw 延续 WheaterAttributes 的换装机制
- 按压手感 `NIOPressableButtonStyle`、动效 `NIOThemeMotion`
- 网络写法参照 `NIOService.swift` 的 URLSession async/await 模式
- pbxproj 注册模式（memory 已记录）：PBXBuildFile + PBXFileReference + group child + Sources phase

## 验证

1. `xcodebuild -project YumikoToysRR.xcodeproj -scheme YumikoToysRR -destination 'generic/platform=iOS Simulator' build` 编译通过（App + 扩展双 target）
2. 先 `curl` 实测 Open-Meteo 与 7Timer 端点（崇明东滩坐标 31.518/121.956）确认返回结构再写解析；如遇限额提示改直连测试
3. 模拟器运行：剪贴板粘贴用户提供的 Geminiids JSON → 解析出详情 → 天气卡加载 → 加入实时活动（模拟器锁屏查看倒计时）→ 写入日历（模拟器日历 App 验证事件与两个提醒）
4. 重复导入同一 JSON 验证去重；导入畸形 JSON 验证错误横幅
