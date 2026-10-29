//
//  NIOService.swift
//  wheater
//
//  蔚来 NIO 数据服务（iOS 原生适配版）
//

import Foundation
import Combine
import SwiftUI
import UIKit
import ActivityKit
import BackgroundTasks
import WidgetKit
import CoreLocation

@MainActor
final class NIOService: ObservableObject {
    static let shared = NIOService()

    // MARK: - Published 配置项 (UserDefaults 双向同步持久化)

    @Published var nioVehicleApiMode: String = UserDefaults.standard.string(forKey: "nio_vehicle_api_mode") ?? "url" {
        didSet { UserDefaults.standard.set(nioVehicleApiMode, forKey: "nio_vehicle_api_mode") }
    }
    @Published var nioVehicleApiURL: String = UserDefaults.standard.string(forKey: "nio_vehicle_api_url") ?? "" {
        didSet { UserDefaults.standard.set(nioVehicleApiURL, forKey: "nio_vehicle_api_url") }
    }
    @Published var nioVehicleId: String = UserDefaults.standard.string(forKey: "nio_vehicle_id") ?? "" {
        didSet { UserDefaults.standard.set(nioVehicleId, forKey: "nio_vehicle_id") }
    }
    @Published var nioDeviceId: String = UserDefaults.standard.string(forKey: "nio_device_id") ?? "" {
        didSet { UserDefaults.standard.set(nioDeviceId, forKey: "nio_device_id") }
    }
    @Published var nioVehicleSignSecret: String = UserDefaults.standard.string(forKey: "nio_vehicle_sign_secret") ?? "" {
        didSet { UserDefaults.standard.set(nioVehicleSignSecret, forKey: "nio_vehicle_sign_secret") }
    }
    @Published var nioVehicleSignAlgo: String = UserDefaults.standard.string(forKey: "nio_vehicle_sign_algo") ?? "md5_append" {
        didSet { UserDefaults.standard.set(nioVehicleSignAlgo, forKey: "nio_vehicle_sign_algo") }
    }
    @Published var nioVehicleApiSign: String = UserDefaults.standard.string(forKey: "nio_vehicle_sign") ?? "" {
        didSet { UserDefaults.standard.set(nioVehicleApiSign, forKey: "nio_vehicle_sign") }
    }
    @Published var nioVehicleApiTimestamp: String = UserDefaults.standard.string(forKey: "nio_vehicle_timestamp") ?? "" {
        didSet { UserDefaults.standard.set(nioVehicleApiTimestamp, forKey: "nio_vehicle_timestamp") }
    }
    @Published var nioVehicleAccessToken: String = UserDefaults.standard.string(forKey: "nio_vehicle_token") ?? "" {
        didSet { UserDefaults.standard.set(nioVehicleAccessToken, forKey: "nio_vehicle_token") }
    }
    @Published var nioChangeApiURL: String = UserDefaults.standard.string(forKey: "nio_change_api_url") ?? "" {
        didSet { UserDefaults.standard.set(nioChangeApiURL, forKey: "nio_change_api_url") }
    }
    @Published var nioChangeAccessToken: String = UserDefaults.standard.string(forKey: "nio_change_token") ?? "" {
        didSet { UserDefaults.standard.set(nioChangeAccessToken, forKey: "nio_change_token") }
    }
    @Published var nioCheckinApiURL: String = UserDefaults.standard.string(forKey: "nio_checkin_api_url") ?? "" {
        didSet { UserDefaults.standard.set(nioCheckinApiURL, forKey: "nio_checkin_api_url") }
    }
    @Published var nioCheckinAccessToken: String = UserDefaults.standard.string(forKey: "nio_checkin_token") ?? "" {
        didSet { UserDefaults.standard.set(nioCheckinAccessToken, forKey: "nio_checkin_token") }
    }
    @Published var nioIsAutoPollEnabled: Bool = UserDefaults.standard.object(forKey: "nio_auto_poll") == nil ? true : UserDefaults.standard.bool(forKey: "nio_auto_poll") {
        didSet { UserDefaults.standard.set(nioIsAutoPollEnabled, forKey: "nio_auto_poll") }
    }
    @Published var nioVehiclePollIntervalSeconds: Int = max(60, UserDefaults.standard.integer(forKey: "nio_poll_interval") > 0 ? UserDefaults.standard.integer(forKey: "nio_poll_interval") : 300) {
        didSet { UserDefaults.standard.set(nioVehiclePollIntervalSeconds, forKey: "nio_poll_interval") }
    }

    // MARK: - Published 业务状态

    @Published var vehicleData: NIOVehicleResponse?
    @Published var serviceSummary: NIOServiceSummary?
    @Published var recentOrders: [NIOServiceOrder] = []
    @Published var checkinData: NIOCheckinData?
    @Published var history: [NIOVehicleSnapshot] = []
    @Published var dailyPaths: [NIODailyPath] = []
    @Published var dailyMileageDeltas: [NIODailyDelta] = []
    @Published var fetchLogs: [NIOFetchLogEntry] = []

    @Published var isLoadingVehicle = false
    @Published var isLoadingChange = false
    @Published var isLoadingCheckin = false
    @Published var lastError: String?
    /// 最近一次成功拉取车况的时刻（主 App 首页与桌面 Widget 更新时间的唯一数据源）。
    /// 持久化到 UserDefaults，防止 App 重启后短暂为 nil 时被 `?? Date()` 兜底成"现在"。
    @Published var lastVehicleFetch: Date? {
        didSet {
            let key = Self.lastVehicleFetchKey
            if let lastVehicleFetch {
                UserDefaults.standard.set(lastVehicleFetch.timeIntervalSince1970, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    private static let lastVehicleFetchKey = "nio_last_vehicle_fetch_time"
    @Published var is403Detected = false

    var isConfigured: Bool {
        if !nioVehicleAccessToken.isEmpty {
            if !nioVehicleApiURL.isEmpty || !nioVehicleId.isEmpty {
                return true
            }
        }
        return false
    }

    // MARK: - 调度状态

    private var vehicleTimer: Timer?
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // 节流时间戳：change / checkin 变化频率低，轮询时限制最小间隔，
    // 避免高频请求触发风控导致 token 被判定异常而快速失效
    private var lastChangeFetch: Date?
    private var lastCheckinFetch: Date?

    // MARK: - 统一设备指纹（防止服务器判定多端登录导致 token 过快失效）
    //
    // 服务器将 token 与登录设备指纹绑定；同一 token 出现多种 build/iOS 组合
    // 的 User-Agent 交替会被判定为多端登录并踢下线。因此所有请求共享同一指纹：
    //  · app_ver 取自抓包 URL（与签名请求同源），build 号与 app_ver 世代匹配，
    //    避免「NextevCar/6.7.15 + build:2586」这类不存在的组合被识别为伪造客户端
    //  · iOS 版本使用本机真实系统版本，与真机蔚来 App 指纹保持一致
    //  · User-Guid 回放抓包的 device_id，与登录设备绑定同一标识

    private func unifiedUserAgent(for url: URL?) -> String {
        // 优先级：当前请求 URL > 直推捕获的 App 版本 > 抓包 URL > 兜底
        let captured = url.flatMap { NIOVehicleLib.extractQueryParam(from: $0.absoluteString, key: "app_ver") }
            ?? UserDefaults.standard.string(forKey: "nio_captured_app_ver").flatMap { $0.isEmpty ? nil : $0 }
            ?? NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "app_ver")
        let version = captured ?? "6.7.15"
        let build = version.compare("6.6.0", options: .numeric) == .orderedAscending ? 2586 : 2644
        return "NextevCar/\(version) (com.do1.WeiLaiApp; build:\(build); iOS \(UIDevice.current.systemVersion)) Alamofire/5.9.1"
    }

    private func applyDeviceFingerprint(to req: inout URLRequest, url: URL?) {
        req.setValue(unifiedUserAgent(for: url), forHTTPHeaderField: "User-Agent")
        if !nioDeviceId.isEmpty {
            req.setValue(nioDeviceId, forHTTPHeaderField: "User-Guid")
        }
    }

    private var dataDirectory: URL {
        // 文档目录理论上恒存在；不用强制解包，兜底沙盒临时目录
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("NIO_Data", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var vehicleFile: URL { dataDirectory.appendingPathComponent("vehicle.json") }
    private var cachedTyreFile: URL { dataDirectory.appendingPathComponent("cached_tyre.json") }
    private var cachedLvBattFile: URL { dataDirectory.appendingPathComponent("cached_lv_batt.json") }
    private var cachedFotaFile: URL { dataDirectory.appendingPathComponent("cached_fota.json") }
    private var cachedDoorFile: URL { dataDirectory.appendingPathComponent("cached_door.json") }
    private var cachedKeyFile: URL { dataDirectory.appendingPathComponent("cached_key.json") }
    private var cachedHeatingFile: URL { dataDirectory.appendingPathComponent("cached_heating.json") }
    private var cachedWindowFile: URL { dataDirectory.appendingPathComponent("cached_window.json") }
    private var cachedFrdgFile: URL { dataDirectory.appendingPathComponent("cached_frdg.json") }
    private var cachedBoxFile: URL { dataDirectory.appendingPathComponent("cached_box.json") }
    private var cachedLightFile: URL { dataDirectory.appendingPathComponent("cached_light.json") }
    private var cachedOffcarFile: URL { dataDirectory.appendingPathComponent("cached_offcar.json") }
    private var historyFile: URL { dataDirectory.appendingPathComponent("history.json") }
    private var checkinFile: URL { dataDirectory.appendingPathComponent("checkin.json") }
    private var logsFile: URL { dataDirectory.appendingPathComponent("logs.json") }
    private var ordersFile: URL { dataDirectory.appendingPathComponent("orders.json") }

    var cachedTyreStatus: [String: NIOJSONValue]? = nil
    var cachedLvBattStatus: [String: NIOJSONValue]? = nil
    var cachedFotaStatus: NIOFotaStatus? = nil
    var cachedDoorStatus: [String: NIOJSONValue]? = nil
    var cachedKeyStatus: [String: NIOJSONValue]? = nil
    var cachedHeatingStatus: [String: NIOJSONValue]? = nil
    var cachedWindowStatus: [String: NIOJSONValue]? = nil
    var cachedFrdgStatus: [String: NIOJSONValue]? = nil
    var cachedBoxStatus: [String: NIOJSONValue]? = nil
    var cachedLightStatus: [String: NIOJSONValue]? = nil
    var cachedOffcarStatus: [String: NIOJSONValue]? = nil
    private var lastFetchTimestamp: Date? = nil
    /// 从小组件 / 控制胶囊进入 App 时，fetchVehicle 正在跑会被 guard 吞掉；
    /// 记录 pending 标志，当前轮结束后自动补一轮，避免刷新卡住。
    private var pendingVehicleRefresh = false
    /// Widget is inexpensive and keeps the live activity fresh. Full RVS blocks
    /// (tyre, FOTA, doors…) are only refreshed when stale, explicitly requested,
    /// or still absent; this avoids repeatedly hitting the private telemetry API.
    private var lastTelemetryFetch: Date? = nil
    private let telemetryRefreshInterval: TimeInterval = 15 * 60

    private init() {
        // 先恢复持久化的更新时间，再异步加载缓存/网络数据，
        // 确保冷启动初期 buildState 兜底不会把更新时间写成"现在"（init 内直接赋值不触发 didSet）
        if let ts = UserDefaults.standard.object(forKey: Self.lastVehicleFetchKey) as? TimeInterval, ts > 0 {
            lastVehicleFetch = Date(timeIntervalSince1970: ts)
        }
        loadPersistedData()
        startScheduling()
        setupLifecycleObservers()
        setupIslandRaiseObserver()
    }

    /// 控制胶囊上岛实时通道：App 已在前台运行时 scenePhase 不会变化（onChange 不触发），
    /// Widget 扩展点击胶囊后 post Darwin 通知，此处监听立即消费上岛请求。
    private func setupIslandRaiseObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in NIOService.shared.checkPendingIslandRaise() }
            },
            "com.yumikotoysrr.wheater.raiseIsland" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 后台定位保活激活时，轮询定时器继续在后台跑（车况准实时）；
            // 未开保活则暂停轮询，杜绝后台无效网络唤醒与并发冲突
            guard !NIOLocationKeepAlive.shared.isKeepingAlive else { return }
            MainActor.assumeIsolated {
                self?.vehicleTimer?.invalidate()
                self?.vehicleTimer = nil
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 回到前台后平滑恢复调度，若数据已超 2 分钟则轻量刷新一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self else { return }
                // 控制胶囊上岛接力：回前台先消费 Widget 扩展写入的快速上岛请求
                self.checkPendingIslandRaise()
                if let last = self.lastVehicleFetch, Date().timeIntervalSince(last) > 120 {
                    Task { [weak self] in await self?.fetchVehicle(force: false) }
                }
                self.scheduleNextVehiclePoll()
            }
        }
    }

    // MARK: - 调度管理 (智能退避 + 随机 Jitter 扰动)

    func startScheduling() {
        stopScheduling()
        guard isConfigured && nioIsAutoPollEnabled else { return }
        refreshAll()
        scheduleNextVehiclePoll()
    }

    func scheduleNextVehiclePoll() {
        vehicleTimer?.invalidate()
        guard isConfigured && nioIsAutoPollEnabled else { return }

        // 基础周期：若 403 触发则自动退避 15 分钟 (900秒) 避免频繁撞车封禁 Token
        let baseInterval: Double
        if is403Detected {
            baseInterval = 900.0
        } else {
            baseInterval = Double(max(60, nioVehiclePollIntervalSeconds))
        }

        // 注入 ± 15~35 秒随机 Jitter，错开与 macOS / 手机 App 的并发时间窗口
        let jitter = Double.random(in: -15...35)
        let finalInterval = max(60.0, baseInterval + jitter)

        vehicleTimer = Timer.scheduledTimer(withTimeInterval: finalInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchVehicle()
                self?.scheduleNextVehiclePoll()
            }
        }
    }

    func stopScheduling() {
        vehicleTimer?.invalidate()
        vehicleTimer = nil
    }

    // MARK: - 刷新全部

    /// 全量刷新。轮询走默认 force=false（change/checkin 受节流），用户手动刷新传 force=true。
    func refreshAll(force: Bool = false) {
        Task {
            async let v: () = fetchVehicle(force: force)
            async let c: () = fetchChange(force: force)
            async let k: () = fetchCheckin(force: force)
            _ = await (v, c, k)
            // 更新时间由 fetchVehicle 成功路径（真实拿到数据后）写入。
            // 此处不可无条件重置为当前时刻：请求被防抖吞掉或失败时，
            // 会把"更新时间"伪刷新成"现在"，导致桌面 Widget 恒显示"刚刚"。
        }
    }

    // MARK: - 车辆双 API 协同调度拉取架构 (参考 nio-dash / ha-nio)
    // 链路 1 (Widget 动态签名接口): 专精拉取实时 SOC 电量、充电状态/功率、行车状态、车辆闭锁、实时定位与温度 (动态签名永不过期)
    // 链路 2 (RVS 全量遥测接口): 专精拉取 4 轮胎压/胎温、车机固件 FOTA、12V 小电瓶电压/电量、7门车窗天窗开度全景、车外灯光、座椅方向盘加热、车载冰箱、离车守卫/露营/宠物模式

    func fetchVehicle(force: Bool = false) async {
        guard isConfigured else { return }
        guard !isLoadingVehicle else {
            // 从小组件进入时可能正赶上后台轮询在跑，静默丢弃会导致"卡住"。
            // force 请求标记 pending，当前轮结束后自动补一轮。
            if force { pendingVehicleRefresh = true }
            return
        }

        // 防抖节流阀：防止短时间连续点击造成的并发突发请求
        if !force, let last = lastFetchTimestamp, Date().timeIntervalSince(last) < 8.0 {
            return
        }

        isLoadingVehicle = true
        defer {
            isLoadingVehicle = false
            scheduleNextVehiclePoll()
            // 补跑被 guard 吞掉的 force 请求（从小组件 / 控制胶囊进入时的刷新）
            if pendingVehicleRefresh {
                pendingVehicleRefresh = false
                Task { await fetchVehicle(force: true) }
            }
        }

        let token = normalizeBearer(nioVehicleAccessToken)
        guard !token.isEmpty else {
            lastError = "未配置有效的 Access Token"
            return
        }

        // 1. 获取 Widget 动态小组件实时状态 (高频动态)
        var widgetStatus: NIOVehicleStatus? = nil
        if let widgetUrl = buildWidgetTargetURL() {
            widgetStatus = await fetchWidgetData(url: widgetUrl, token: token)
        }

        // 2. Full RVS telemetry is deliberately decoupled from the high-frequency
        // Widget path. A user may paste several signed captures (one per line),
        // e.g. a lightweight live-status request plus a full tyre/FOTA request.
        // Each request is replayed unchanged because its `field` list is signed.
        let hasMissingTelemetry = !NIOVehicleLib.extractTyreInfo(self.vehicleData?.data?.status?.tyreStatus).hasData
            || (self.vehicleData?.data?.status?.fotaStatus?.currentVersion?.isEmpty != false)
        let shouldRefreshTelemetry = force || hasMissingTelemetry
            || lastTelemetryFetch.map { Date().timeIntervalSince($0) >= telemetryRefreshInterval } ?? true
        var rvsStatus: NIOVehicleStatus? = nil
        if shouldRefreshTelemetry {
            let rvsStatuses = await withTaskGroup(of: NIOVehicleStatus?.self) { group in
                for rvsURL in buildRvsTargetURLs() {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        return await self.fetchRvsData(url: rvsURL, token: token)
                    }
                }
                var values: [NIOVehicleStatus] = []
                for await value in group {
                    if let value { values.append(value) }
                }
                return values
            }
            rvsStatus = mergeRVSStatuses(rvsStatuses)
            if rvsStatus != nil { lastTelemetryFetch = Date() }
        }

        // 3. 智能融合两路 API 数据与持久化落盘缓存 (Smart Merge)
        if widgetStatus != nil || rvsStatus != nil {
            let merged = mergeVehicleStatus(widget: widgetStatus, rvs: rvsStatus)
            self.vehicleData = merged
            self.lastVehicleFetch = Date()
            self.lastFetchTimestamp = Date()
            self.lastError = nil
            self.is403Detected = false

            // 同步刷新 iOS 灵动岛与锁屏实时活动
            self.updateLiveActivity()

            // 异步持久化到本地
            saveJSONAsync(merged, to: vehicleFile)
            appendSnapshot(merged)
        } else if self.vehicleData == nil {
            self.lastError = "车辆数据拉取失败，请在蔚来 App 爱车页下拉刷新后重新嗅探"
        }
    }

    private func buildWidgetTargetURL() -> URL? {
        if !nioVehicleId.isEmpty {
            let devId = nioDeviceId.isEmpty ? "iOS_Device_\(nioVehicleId.prefix(6))" : nioDeviceId
            if let built = NIOVehicleLib.buildWidgetURL(
                vehicleId: nioVehicleId,
                deviceId: devId,
                secret: nioVehicleSignSecret.isEmpty ? nil : nioVehicleSignSecret,
                algo: nioVehicleSignAlgo.isEmpty ? "md5_append" : nioVehicleSignAlgo
            ) {
                return built.url
            }
        }
        // 若未填 vehicleId，但有 nioVehicleApiURL，尝试从中提取 vehicleId 与 deviceId
        if !nioVehicleApiURL.isEmpty {
            if let vid = NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "vehicle_id"), !vid.isEmpty {
                let devId = NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "device_id") ?? "iOS_Device_\(vid.prefix(6))"
                let sgn = NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "sign")
                let ts = NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "timestamp") ?? "\(Int(Date().timeIntervalSince1970))"
                if let built = NIOVehicleLib.buildWidgetURL(vehicleId: vid, deviceId: devId, secret: nioVehicleSignSecret.isEmpty ? nil : nioVehicleSignSecret, algo: nioVehicleSignAlgo) {
                    return built.url
                }
                if let sgn = sgn, !sgn.isEmpty {
                    let wStr = "https://app.nio.com/app/api/icar/v2/widget/info?widget_size=large&app_id=10002&widget_functions=rvs_set_doorlock%2Crvs_set_air_conditioner%2Crvs_set_tailgate%2Crvs_exe_findme&lang=zh-CN&region=cn&device_id=\(devId)&timestamp=\(ts)&vehicle_id=\(vid)&app_ver=6.7.15&sign=\(sgn)"
                    return URL(string: wStr)
                }
            }
        }
        return nil
    }

    private func buildRvsTargetURLs() -> [URL] {
        var urls: [URL] = []
        let vid = nioVehicleId.isEmpty ? (NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "vehicle_id") ?? "") : nioVehicleId
        let devId = nioDeviceId.isEmpty ? (NIOVehicleLib.extractQueryParam(from: nioVehicleApiURL, key: "device_id") ?? "iOS_Device_\(vid.prefix(6))") : nioDeviceId
        let ts = String(Int(Date().timeIntervalSince1970))

        // 1. User-captured URLs are replayed verbatim. Multiple newline-separated
        // captures are supported so narrow, signed requests can complement each
        // other (for example `field=tyre` and `field=fota`).
        let capturedURLs = nioVehicleApiURL
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter { $0.contains("icar.nio.com") && $0.contains("/status") }
        for captured in capturedURLs {
            let trimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
            var fullUrl = trimmed
            if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
                fullUrl = "https://\(trimmed)"
            }
            if let resigned = NIOVehicleLib.autoResignRvsURL(fullUrl, secret: nioVehicleSignSecret, algo: nioVehicleSignAlgo),
               let u = URL(string: resigned) {
                urls.append(u)
            }
            if let u = URL(string: fullUrl), !urls.contains(u) {
                urls.append(u)
            }
        }

        // 2. 基于 vehicleId 动态构建 RVS 遥测候选 URL
        if !vid.isEmpty {
            let baseCandidates = [
                "https://icar.nio.com/api/2/rvs/vehicle/\(vid)/status",
                "https://icar.nio.com/api/1/vehicle/\(vid)/status",
                "https://gateway-front-external.nio.com/moat/1100367/api/v1/otd/car/ext/general/vehicle/\(vid)/status",
                "https://app.nio.com/app/api/icar/v2/vehicle/\(vid)/status"
            ]

            for base in baseCandidates {
                var params: [String: String] = [
                    "region": "cn",
                    "lang": "zh-CN",
                    "app_ver": "6.5.3",
                    "device_id": devId,
                    "timestamp": ts
                ]
                if !nioVehicleSignSecret.isEmpty {
                    params["sign"] = NIOVehicleLib.computeWidgetSign(params: params, secret: nioVehicleSignSecret, algo: nioVehicleSignAlgo)
                } else if !nioVehicleApiSign.isEmpty {
                    params["sign"] = nioVehicleApiSign
                }
                var comp = URLComponents(string: base)
                comp?.queryItems = params.keys.sorted().map { URLQueryItem(name: $0, value: params[$0]) }
                if let u = comp?.url, !urls.contains(u) {
                    urls.append(u)
                }
            }
        }

        return urls
    }

    /// Combines independently captured, signed RVS responses by status block.
    /// Encoding back through the model keeps new/unknown blocks forward-compatible.
    private func mergeRVSStatuses(_ statuses: [NIOVehicleStatus]) -> NIOVehicleStatus? {
        guard !statuses.isEmpty else { return nil }
        var merged: [String: Any] = [:]
        for status in statuses {
            guard let data = try? JSONEncoder().encode(status),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (key, value) in object where !(value is NSNull) { merged[key] = value }
        }
        guard !merged.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: merged) else { return statuses.first }
        return try? JSONDecoder().decode(NIOVehicleStatus.self, from: data)
    }

    // MARK: - 凭证失效上报 (401/403)

    /// Token 过期/失效提醒：点亮"凭证失效"状态 + 明确文案 + 警示触感。
    /// 此前 401/403 只写入拉取日志即静默返回，状态点/退避/横幅全部不触发；
    /// 修复成功后由 fetchVehicle 成功分支自动复位（is403Detected = false + lastError = nil）。
    private func noteAuthFailure(_ statusCode: Int) {
        guard statusCode == 401 || statusCode == 403 else { return }
        guard !is403Detected else { return }
        is403Detected = true
        lastError = "蔚来 Token 已失效（HTTP \(statusCode)），自动刷新已降频为 15 分钟重试 · 请重新嗅探并更新 Token"
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func fetchWidgetData(url: URL, token: String) async -> NIOVehicleStatus? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        applyDeviceFingerprint(to: &req, url: url)
        req.setValue(token, forHTTPHeaderField: "Authorization")

        let logEntry = NIOFetchLogEntry(
            category: "vehicle_widget", level: "info",
            message: "Widget 动态接口 · 开始拉取实时状态…",
            detail: nil, timestamp: Date(),
            requestURL: url.absoluteString, requestMethod: "GET",
            requestBody: nil, responsePreview: nil, statusCode: nil
        )
        appendLog(logEntry)

        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            let text = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 200, let rawJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let norm = RVSRormalizer.normalize(rawJson)
                let normData = try JSONSerialization.data(withJSONObject: norm)
                let decoded = try JSONDecoder().decode(NIOVehicleResponse.self, from: normData)
                updateLog(logEntry, statusCode: 200, preview: String(text.prefix(200)))
                return decoded.data?.status
            } else {
                updateLog(logEntry, statusCode: http.statusCode, preview: String(text.prefix(200)))
                noteAuthFailure(http.statusCode)
            }
        } catch {
            updateLog(logEntry, statusCode: nil, preview: error.localizedDescription)
        }
        return nil
    }

    private func fetchRvsData(url: URL, token: String) async -> NIOVehicleStatus? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json,text/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        applyDeviceFingerprint(to: &req, url: url)
        if url.host?.lowercased().contains("icar.nio.com") == true {
            req.setValue("tsp.nio.com", forHTTPHeaderField: "Host")
        }
        req.setValue(token, forHTTPHeaderField: "Authorization")

        let logEntry = NIOFetchLogEntry(
            category: "vehicle_rvs", level: "info",
            message: "RVS 全量接口 · 开始拉取遥测车况…",
            detail: nil, timestamp: Date(),
            requestURL: url.absoluteString, requestMethod: "GET",
            requestBody: nil, responsePreview: nil, statusCode: nil
        )
        appendLog(logEntry)

        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            let text = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 200, let rawJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let norm = RVSRormalizer.normalize(rawJson)
                let normData = try JSONSerialization.data(withJSONObject: norm)
                let decoded = try JSONDecoder().decode(NIOVehicleResponse.self, from: normData)
                updateLog(logEntry, statusCode: 200, preview: String(text.prefix(200)))
                return decoded.data?.status
            } else {
                updateLog(logEntry, statusCode: http.statusCode, preview: String(text.prefix(200)))
                noteAuthFailure(http.statusCode)
            }
        } catch {
            updateLog(logEntry, statusCode: nil, preview: error.localizedDescription)
        }
        return nil
    }

    private func mergeVehicleStatus(widget: NIOVehicleStatus?, rvs: NIOVehicleStatus?) -> NIOVehicleResponse {
        var base = self.vehicleData ?? NIOVehicleResponse(
            resultCode: "success",
            data: NIOVehicleData(
                status: NIOVehicleStatus(vehicleId: self.nioVehicleId)
            )
        )
        if base.data == nil { base.data = NIOVehicleData(status: NIOVehicleStatus(vehicleId: self.nioVehicleId)) }
        if base.data?.status == nil { base.data?.status = NIOVehicleStatus(vehicleId: self.nioVehicleId) }

        // --- 1. 实时动态状态 (优先取 Widget 动态最新，其次取 RVS) ---
        if let wSoc = widget?.socStatus ?? rvs?.socStatus {
            base.data?.status?.socStatus = wSoc
        }
        if let wConn = widget?.connectionStatus ?? rvs?.connectionStatus {
            base.data?.status?.connectionStatus = wConn
        }
        if let wPos = widget?.positionStatus ?? rvs?.positionStatus {
            base.data?.status?.positionStatus = wPos
        }
        if let wExt = widget?.exteriorStatus ?? rvs?.exteriorStatus {
            base.data?.status?.exteriorStatus = wExt
        }
        if let wHvac = widget?.hvacStatus ?? rvs?.hvacStatus {
            var finalHvac = wHvac
            if finalHvac.outsideTemperature == nil {
                finalHvac.outsideTemperature = rvs?.hvacStatus?.outsideTemperature ?? self.vehicleData?.data?.status?.hvacStatus?.outsideTemperature
            }
            base.data?.status?.hvacStatus = finalHvac
        }

        // --- 2. 全量遥测状态 (优先取 RVS 全量，其次取持久化缓存，再次取已有数据) ---
        // 2.1 4 轮胎压/胎温
        if let rTyre = rvs?.tyreStatus, NIOVehicleLib.extractTyreInfo(rTyre).hasData {
            base.data?.status?.tyreStatus = rTyre
            self.cachedTyreStatus = rTyre
            saveJSONAsync(rTyre, to: cachedTyreFile)
        } else if let cTyre = self.cachedTyreStatus, NIOVehicleLib.extractTyreInfo(cTyre).hasData {
            base.data?.status?.tyreStatus = cTyre
        }

        // 2.2 车机固件版本 FOTA
        if let rFota = rvs?.fotaStatus, !(rFota.currentVersion ?? "").isEmpty {
            base.data?.status?.fotaStatus = rFota
            self.cachedFotaStatus = rFota
            saveJSONAsync(rFota, to: cachedFotaFile)
        } else if let cFota = self.cachedFotaStatus {
            base.data?.status?.fotaStatus = cFota
        }

        // 2.3 12V 辅助蓄电池
        if let rLv = rvs?.lvBattStatus, !rLv.isEmpty {
            base.data?.status?.lvBattStatus = rLv
            self.cachedLvBattStatus = rLv
            saveJSONAsync(rLv, to: cachedLvBattFile)
        } else if let cLv = self.cachedLvBattStatus, !cLv.isEmpty {
            base.data?.status?.lvBattStatus = cLv
        }

        // 2.4 车门与车锁 (融合 Widget 实时车锁与 RVS 详细车门)
        var mergedDoors = rvs?.doorStatus ?? self.cachedDoorStatus ?? self.vehicleData?.data?.status?.doorStatus ?? [:]
        if let wDoors = widget?.doorStatus {
            for (k, v) in wDoors { mergedDoors[k] = v }
        }
        if !mergedDoors.isEmpty {
            base.data?.status?.doorStatus = mergedDoors
            self.cachedDoorStatus = mergedDoors
            saveJSONAsync(mergedDoors, to: cachedDoorFile)
        }

        // 2.5 车窗与天窗
        if let rWin = rvs?.windowStatus, !rWin.isEmpty {
            base.data?.status?.windowStatus = rWin
            self.cachedWindowStatus = rWin
            saveJSONAsync(rWin, to: cachedWindowFile)
        } else if let cWin = self.cachedWindowStatus, !cWin.isEmpty {
            base.data?.status?.windowStatus = cWin
        }

        // 2.6 车外灯光
        if let rLight = rvs?.lightStatus, !rLight.isEmpty {
            base.data?.status?.lightStatus = rLight
            self.cachedLightStatus = rLight
            saveJSONAsync(rLight, to: cachedLightFile)
        } else if let cLight = self.cachedLightStatus, !cLight.isEmpty {
            base.data?.status?.lightStatus = cLight
        }

        // 2.7 座椅加热与方向盘加热
        if let rHeat = rvs?.heatingStatus, !rHeat.isEmpty {
            base.data?.status?.heatingStatus = rHeat
            self.cachedHeatingStatus = rHeat
            saveJSONAsync(rHeat, to: cachedHeatingFile)
        } else if let cHeat = self.cachedHeatingStatus, !cHeat.isEmpty {
            base.data?.status?.heatingStatus = cHeat
        }

        // 2.8 冰箱与尾箱
        if let rFrdg = rvs?.frdgStatus, !rFrdg.isEmpty {
            base.data?.status?.frdgStatus = rFrdg
            self.cachedFrdgStatus = rFrdg
            saveJSONAsync(rFrdg, to: cachedFrdgFile)
        } else if let cFrdg = self.cachedFrdgStatus, !cFrdg.isEmpty {
            base.data?.status?.frdgStatus = cFrdg
        }
        if let rBox = rvs?.boxStatus, !rBox.isEmpty {
            base.data?.status?.boxStatus = rBox
            self.cachedBoxStatus = rBox
            saveJSONAsync(rBox, to: cachedBoxFile)
        } else if let cBox = self.cachedBoxStatus, !cBox.isEmpty {
            base.data?.status?.boxStatus = cBox
        }

        // 2.9 离车模式 (守卫/露营/宠物/不下电)
        if let rOffcar = rvs?.offcarModeStatus, !rOffcar.isEmpty {
            base.data?.status?.offcarModeStatus = rOffcar
            self.cachedOffcarStatus = rOffcar
            saveJSONAsync(rOffcar, to: cachedOffcarFile)
        } else if let cOffcar = self.cachedOffcarStatus, !cOffcar.isEmpty {
            base.data?.status?.offcarModeStatus = cOffcar
        }

        // 2.10 保养与其它
        if let rMaint = rvs?.maintainStatus {
            base.data?.status?.maintainStatus = rMaint
        }

        if let vid = widget?.vehicleId ?? rvs?.vehicleId ?? base.data?.status?.vehicleId, !vid.isEmpty {
            base.data?.status?.vehicleId = vid
        }

        return base
    }

    // MARK: - 换电服务拉取

    /// 服务订单/换电拉取。轮询调用 force=false（10 分钟节流），手动刷新 force=true 直通。
    /// 高频拉取会触发风控，导致 token 被判定异常设备而过快失效。
    func fetchChange(force: Bool = false) async {
        guard isConfigured else { return }
        guard !isLoadingChange else { return }
        if !force, let last = lastChangeFetch, Date().timeIntervalSince(last) < 600 { return }
        lastChangeFetch = Date()
        isLoadingChange = true
        defer { isLoadingChange = false }

        let token = normalizeBearer(nioChangeAccessToken.isEmpty ? nioVehicleAccessToken : nioChangeAccessToken)
        guard !token.isEmpty else { return }

        // 多链路候选 URL（解决 404 及旧版网关失效问题）
        let primaryGateway = "https://gateway-front-external.nio.com/moat/1100367/api/v1/otd/car/ext/general/serviceOrder/getTabOrder?offset=0&limit=200&orderTypes=pe_shaman,pe_shaman_change,service_pe_discharge,battery_flexible_upgrade,nsom_so_maintenance,nsom_so_chauffeur,chauffeur_vehicle_delivery,so_case_accident&hash_type=sha256&lang=zh&region=US&tz_offset=28800&app_ver=6.5.3"
        let shortGateway = "https://gateway-front-external.nio.com/moat/1100367/api/v1/otd/car/ext/general/serviceOrder/getTabOrder?offset=0&limit=50&orderTypes=pe_shaman_change,pe_shaman"
        let appNioQueryList = "https://app.nio.com/app/api/service_charge/v2/order/query_list?status=all&app_id=10002"
        let appNioSwapList = "https://app.nio.com/app/api/charge/power_swap/order/list"

        var candidates: [String] = []
        if !nioChangeApiURL.isEmpty {
            let sanitized = nioChangeApiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.append(sanitized)
        }
        for u in [primaryGateway, shortGateway, appNioQueryList, appNioSwapList] {
            if !candidates.contains(u) { candidates.append(u) }
        }

        for targetChangeURL in candidates {
            guard let url = URL(string: targetChangeURL) else { continue }
            let isAppNio = targetChangeURL.contains("app.nio.com")

            // 尝试 POST 请求
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
                applyDeviceFingerprint(to: &req, url: url)
                req.setValue(token, forHTTPHeaderField: "Authorization")
                req.httpBody = try? JSONSerialization.data(withJSONObject: isAppNio ? ["page_num": 1, "page_size": 20] : ["offset": 0, "limit": 200])

                let (data, response) = try await urlSession.data(for: req)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        if let decoded = try? JSONDecoder().decode(NIOChangeResponse.self, from: data) {
                            // 空响应保护：接口抖动返回空集时保留旧数据，避免看板突然空白
                            if let newOrders = decoded.resultData?.data, !newOrders.isEmpty {
                                self.serviceSummary = NIOOrderLib.analyzeServiceOrders(decoded)
                                storeRecentOrders(newOrders)
                            }
                            return
                        }
                    } else {
                        noteAuthFailure(http.statusCode)
                    }
                }
            } catch {
                print("[NIOService] fetchChange POST 失败: \(error.localizedDescription)")
            }

            // 若 POST 404/405 则尝试 GET 请求
            if isAppNio {
                do {
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    applyDeviceFingerprint(to: &req, url: url)
                    req.setValue(token, forHTTPHeaderField: "Authorization")

                    let (data, response) = try await urlSession.data(for: req)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 200 {
                            if let decoded = try? JSONDecoder().decode(NIOChangeResponse.self, from: data) {
                                if let newOrders = decoded.resultData?.data, !newOrders.isEmpty {
                                    self.serviceSummary = NIOOrderLib.analyzeServiceOrders(decoded)
                                    storeRecentOrders(newOrders)
                                }
                                return
                            }
                        } else {
                            noteAuthFailure(http.statusCode)
                        }
                    }
                } catch {
                    print("[NIOService] fetchChange GET 兜底失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 签到拉取

    /// 签到状态拉取。轮询调用 force=false（30 分钟节流），手动刷新 force=true 直通。
    func fetchCheckin(force: Bool = false) async {
        guard isConfigured else { return }
        guard !isLoadingCheckin else { return }
        if !force, let last = lastCheckinFetch, Date().timeIntervalSince(last) < 1800 { return }
        lastCheckinFetch = Date()
        isLoadingCheckin = true
        defer { isLoadingCheckin = false }

        let token = normalizeBearer(nioCheckinAccessToken.isEmpty ? nioVehicleAccessToken : nioCheckinAccessToken)
        guard !token.isEmpty else { return }

        // 多链路候选 URL（彻底消除双斜杠 //n/c 导致的 404 Bug）
        let primaryGateway = "https://gateway-front-external.nio.com/moat/10086/n/c/award/square?event=checkin&collection_id=1843940587332317185"
        let fallbackGateway = "https://gateway-front-external.nio.com/moat/10086/n/c/award/square?event=checkin"
        let appNioCheckin = "https://app.nio.com/app/api/users/checkin"
        let appNioStatus = "https://app.nio.com/app/api/users/checkin/status"

        var candidates: [String] = []
        if !nioCheckinApiURL.isEmpty {
            // 自动修复双斜杠 //n/c 历史错误
            let sanitized = nioCheckinApiURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "//n/c", with: "/n/c")
            candidates.append(sanitized)
        }
        for u in [primaryGateway, fallbackGateway, appNioCheckin, appNioStatus] {
            if !candidates.contains(u) { candidates.append(u) }
        }

        for targetCheckinURL in candidates {
            guard let url = URL(string: targetCheckinURL) else { continue }
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
                applyDeviceFingerprint(to: &req, url: url)
                req.setValue(token, forHTTPHeaderField: "Authorization")

                let (data, response) = try await urlSession.data(for: req)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        if let rawJson = try? JSONSerialization.jsonObject(with: data) {
                            if let ci = NIOOrderLib.extractCheckinData(from: rawJson) {
                                self.checkinData = ci
                                saveJSONAsync(ci, to: checkinFile)
                                return
                            }
                        }
                    } else {
                        noteAuthFailure(http.statusCode)
                    }
                }
            } catch {
                print("[NIOService] fetchCheckin 失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 智能识别与一键填充

    func smartParseInput(_ input: String) -> Bool {
        // 清洗手工粘贴内容：markdown 反引号 / 包裹引号 / 空白（URL 常被 ``` 包裹）
        var trimmed = input
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast())
        }

        let parsed = NIOVehicleLib.smartParseInput(trimmed)
        var updated = false

        if let mode = parsed.mode, !mode.isEmpty {
            self.nioVehicleApiMode = mode
            updated = true
        }
        if let vid = parsed.vehicleId, !vid.isEmpty {
            self.nioVehicleId = vid
            updated = true
        }
        if let did = parsed.deviceId, !did.isEmpty {
            self.nioDeviceId = did
            updated = true
        }
        if let sec = parsed.signSecret, !sec.isEmpty {
            self.nioVehicleSignSecret = sec
            self.nioVehicleApiMode = "widget"
            updated = true
        }
        if let algo = parsed.signAlgo, !algo.isEmpty {
            self.nioVehicleSignAlgo = algo
        }
        if let u = parsed.vehicleURL, !u.isEmpty {
            self.nioVehicleApiURL = u
            updated = true
        }
        if let t = parsed.vehicleToken, !t.isEmpty {
            self.nioVehicleAccessToken = t
            updated = true
        }
        if let cu = parsed.changeURL, !cu.isEmpty {
            self.nioChangeApiURL = cu
        }
        if let ct = parsed.changeToken, !ct.isEmpty {
            self.nioChangeAccessToken = ct
        }
        if let ku = parsed.checkinURL, !ku.isEmpty {
            self.nioCheckinApiURL = ku
        }
        if let kt = parsed.checkinToken, !kt.isEmpty {
            self.nioCheckinAccessToken = kt
        }
        // 设备指纹落库（防多端登录：统一 UA 构造与诊断用）
        if let av = parsed.appVer, !av.isEmpty {
            UserDefaults.standard.set(av, forKey: "nio_captured_app_ver")
        }
        if let ua = parsed.userAgent, !ua.isEmpty {
            UserDefaults.standard.set(ua, forKey: "nio_captured_user_agent")
        }
        if let ug = parsed.userGuid, !ug.isEmpty {
            UserDefaults.standard.set(ug, forKey: "nio_captured_user_guid")
            // device_id 缺失时用 User-Guid 兜底
            if self.nioDeviceId.isEmpty { self.nioDeviceId = ug }
        }

        if updated {
            startScheduling()
        }
        return updated
    }

    // MARK: - 辅助

    private func normalizeBearer(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if t.lowercased().hasPrefix("bearer ") {
            return t
        }
        return "Bearer \(t)"
    }

    private func appendSnapshot(_ resp: NIOVehicleResponse) {
        guard let snap = try? NIOVehicleLib.snapshotFromResponse(resp) else { return }
        guard snap.isValidGPS || snap.ts > 0 else { return }
        if history.contains(where: { $0.snapshotKey == snap.snapshotKey }) { return }
        history.append(snap)
        if history.count > 2000 { history = Array(history.suffix(2000)) }

        let snapshotList = self.history
        updateDerivedMetrics(from: snapshotList)
        saveJSONAsync(snapshotList, to: historyFile)
    }

    private func updateDerivedMetrics(from snapshots: [NIOVehicleSnapshot]) {
        let copy = snapshots
        Task.detached(priority: .userInitiated) {
            let paths = NIOVehicleLib.buildDailyPaths(history: copy)
            let deltas = NIOVehicleLib.computeDailyMileageDeltas(history: copy)
            await MainActor.run {
                NIOService.shared.dailyPaths = paths
                NIOService.shared.dailyMileageDeltas = deltas
            }
        }
    }

    /// 存储最近服务订单（换电/维保等），供维保追踪卡使用；调用方已做空集过滤
    private func storeRecentOrders(_ orders: [NIOServiceOrder]) {
        guard !orders.isEmpty else { return }
        self.recentOrders = orders
        saveJSONAsync(orders, to: ordersFile)
    }

    private func appendLog(_ entry: NIOFetchLogEntry) {
        var logs = fetchLogs
        logs.insert(entry, at: 0)
        if logs.count > 50 { logs = Array(logs.prefix(50)) }
        self.fetchLogs = logs
        saveJSONAsync(logs, to: logsFile)
    }

    private func updateLog(_ entry: NIOFetchLogEntry, statusCode: Int?, preview: String?) {
        var updated = entry
        updated.statusCode = statusCode
        updated.responsePreview = preview
        if let idx = fetchLogs.firstIndex(where: { $0.id == entry.id }) {
            fetchLogs[idx] = updated
            saveJSONAsync(fetchLogs, to: logsFile)
        }
    }

    private func loadPersistedData() {
        // 冷启动 IO + 大 JSON 解码全部移出主线程，避免启动掉帧；完成后回主线程发布
        let vFile = vehicleFile
        let tFile = cachedTyreFile
        let lvFile = cachedLvBattFile
        let fotaFile = cachedFotaFile
        let doorFile = cachedDoorFile
        let kFile = cachedKeyFile
        let htFile = cachedHeatingFile
        let wFile = cachedWindowFile
        let fFile = cachedFrdgFile
        let bFile = cachedBoxFile
        let ltFile = cachedLightFile
        let offFile = cachedOffcarFile
        let hFile = historyFile
        let cFile = checkinFile
        let lFile = logsFile
        let oFile = ordersFile
        Task.detached(priority: .userInitiated) { [weak self] in
            var fetchedAt: Date? = nil
            var vehicle: NIOVehicleResponse? = nil
            var cachedTyre: [String: NIOJSONValue]? = nil
            var cachedLv: [String: NIOJSONValue]? = nil
            var cachedFota: NIOFotaStatus? = nil
            var cachedDoor: [String: NIOJSONValue]? = nil
            var cachedKey: [String: NIOJSONValue]? = nil
            var cachedHt: [String: NIOJSONValue]? = nil
            var cachedWin: [String: NIOJSONValue]? = nil
            var cachedFrdg: [String: NIOJSONValue]? = nil
            var cachedBox: [String: NIOJSONValue]? = nil
            var cachedLt: [String: NIOJSONValue]? = nil
            var cachedOff: [String: NIOJSONValue]? = nil
            var history: [NIOVehicleSnapshot] = []
            var checkin: NIOCheckinData? = nil
            var logs: [NIOFetchLogEntry] = []

            func readDict(_ url: URL) -> [String: NIOJSONValue]? {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode([String: NIOJSONValue].self, from: data)
            }

            cachedTyre = readDict(tFile)
            cachedLv = readDict(lvFile)
            cachedDoor = readDict(doorFile)
            cachedKey = readDict(kFile)
            cachedHt = readDict(htFile)
            cachedWin = readDict(wFile)
            cachedFrdg = readDict(fFile)
            cachedBox = readDict(bFile)
            cachedLt = readDict(ltFile)
            cachedOff = readDict(offFile)

            if let data = try? Data(contentsOf: fotaFile) {
                cachedFota = try? JSONDecoder().decode(NIOFotaStatus.self, from: data)
            }

            if let data = try? Data(contentsOf: vFile),
               let decoded = try? JSONDecoder().decode(NIOVehicleResponse.self, from: data) {
                var v = decoded
                if v.data?.status?.tyreStatus == nil || !NIOVehicleLib.extractTyreInfo(v.data?.status?.tyreStatus).hasData {
                    if let cTyre = cachedTyre { v.data?.status?.tyreStatus = cTyre }
                }
                if v.data?.status?.lvBattStatus == nil || v.data?.status?.lvBattStatus?.isEmpty == true {
                    if let cLv = cachedLv { v.data?.status?.lvBattStatus = cLv }
                }
                if v.data?.status?.fotaStatus == nil {
                    if let cFota = cachedFota { v.data?.status?.fotaStatus = cFota }
                }
                if v.data?.status?.doorStatus == nil || v.data?.status?.doorStatus?.isEmpty == true {
                    if let cDoor = cachedDoor { v.data?.status?.doorStatus = cDoor }
                }
                if v.data?.status?.keyStatus == nil || v.data?.status?.keyStatus?.isEmpty == true {
                    if let cKey = cachedKey { v.data?.status?.keyStatus = cKey }
                }
                if v.data?.status?.heatingStatus == nil || v.data?.status?.heatingStatus?.isEmpty == true {
                    if let cHt = cachedHt { v.data?.status?.heatingStatus = cHt }
                }
                if v.data?.status?.windowStatus == nil || v.data?.status?.windowStatus?.isEmpty == true {
                    if let cWin = cachedWin { v.data?.status?.windowStatus = cWin }
                }
                if v.data?.status?.frdgStatus == nil || v.data?.status?.frdgStatus?.isEmpty == true {
                    if let cFrdg = cachedFrdg { v.data?.status?.frdgStatus = cFrdg }
                }
                if v.data?.status?.boxStatus == nil || v.data?.status?.boxStatus?.isEmpty == true {
                    if let cBox = cachedBox { v.data?.status?.boxStatus = cBox }
                }
                if v.data?.status?.lightStatus == nil || v.data?.status?.lightStatus?.isEmpty == true {
                    if let cLt = cachedLt { v.data?.status?.lightStatus = cLt }
                }
                if v.data?.status?.offcarModeStatus == nil || v.data?.status?.offcarModeStatus?.isEmpty == true {
                    if let cOff = cachedOff { v.data?.status?.offcarModeStatus = cOff }
                }
                vehicle = v
                if let ts = decoded.data?.status?.socStatus?.sampleTime, ts > 0 {
                    let sec = ts > 1_000_000_000_000 ? (ts / 1000) : ts
                    fetchedAt = Date(timeIntervalSince1970: TimeInterval(sec))
                } else if let attr = try? FileManager.default.attributesOfItem(atPath: vFile.path),
                          let modDate = attr[.modificationDate] as? Date {
                    fetchedAt = modDate
                }
            }
            if let data = try? Data(contentsOf: hFile) {
                history = (try? JSONDecoder().decode([NIOVehicleSnapshot].self, from: data)) ?? []
            }
            if let data = try? Data(contentsOf: cFile) {
                checkin = try? JSONDecoder().decode(NIOCheckinData.self, from: data)
            }
            if let data = try? Data(contentsOf: lFile) {
                logs = (try? JSONDecoder().decode([NIOFetchLogEntry].self, from: data)) ?? []
            }
            var orders: [NIOServiceOrder] = []
            if let data = try? Data(contentsOf: oFile) {
                orders = (try? JSONDecoder().decode([NIOServiceOrder].self, from: data)) ?? []
            }

            let finalVehicle = vehicle
            let finalCachedTyre = cachedTyre
            let finalCachedLv = cachedLv
            let finalCachedFota = cachedFota
            let finalCachedDoor = cachedDoor
            let finalCachedKey = cachedKey
            let finalCachedHt = cachedHt
            let finalCachedWin = cachedWin
            let finalCachedFrdg = cachedFrdg
            let finalCachedBox = cachedBox
            let finalCachedLt = cachedLt
            let finalCachedOff = cachedOff
            let finalFetchedAt = fetchedAt
            let finalHistory = history
            let finalCheckin = checkin
            let finalLogs = logs
            let finalOrders = orders

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                // 冷启动竞态保护：网络刷新若已先一步写入（对应状态非空），
                // 磁盘快照不再覆盖，避免慢盘读到的旧数据覆盖刚拉取的新数据
                if self.cachedTyreStatus == nil { self.cachedTyreStatus = finalCachedTyre }
                if self.cachedLvBattStatus == nil { self.cachedLvBattStatus = finalCachedLv }
                if self.cachedFotaStatus == nil { self.cachedFotaStatus = finalCachedFota }
                if self.cachedDoorStatus == nil { self.cachedDoorStatus = finalCachedDoor }
                if self.cachedKeyStatus == nil { self.cachedKeyStatus = finalCachedKey }
                if self.cachedHeatingStatus == nil { self.cachedHeatingStatus = finalCachedHt }
                if self.cachedWindowStatus == nil { self.cachedWindowStatus = finalCachedWin }
                if self.cachedFrdgStatus == nil { self.cachedFrdgStatus = finalCachedFrdg }
                if self.cachedBoxStatus == nil { self.cachedBoxStatus = finalCachedBox }
                if self.cachedLightStatus == nil { self.cachedLightStatus = finalCachedLt }
                if self.cachedOffcarStatus == nil { self.cachedOffcarStatus = finalCachedOff }
                if let v = finalVehicle, self.vehicleData == nil {
                    self.vehicleData = v
                    self.lastVehicleFetch = finalFetchedAt
                    // 冷启动兜底：即使网络拉取失败（如 Token 失效），桌面 Widget 也能立即
                    // 显示最近缓存车况，不再停留在"打开 App 同步车况"空状态
                    self.updateLiveActivity()
                }
                if !finalHistory.isEmpty, self.history.isEmpty {
                    self.history = finalHistory
                    self.updateDerivedMetrics(from: finalHistory)
                }
                if let c = finalCheckin, self.checkinData == nil { self.checkinData = c }
                if !finalLogs.isEmpty, self.fetchLogs.isEmpty { self.fetchLogs = finalLogs }
                if !finalOrders.isEmpty, self.recentOrders.isEmpty { self.recentOrders = finalOrders }
            }
        }
    }

    private func saveJSONAsync<T: Encodable>(_ value: T, to url: URL) {
        // JSON 编码与写盘均在后台线程执行，避免大对象编码阻塞主线程
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 灵动岛 / 实时活动 (Live Activity) 管理

    @Published var isLiveActivityActive = false
    private var currentActivity: Activity<WheaterAttributes>?
    /// 上一次推送的"显著数据"指纹，用于无变化时跳过系统刷新
    private var lastActivityFingerprint: String?
    /// 上一次写入桌面 Widget 快照的内容指纹（含里程/限充等 Widget 可见但灵动岛去重不敏感的字段）
    private var lastWidgetFingerprint: String?

    /// 依据满电 CLTC 续航推算电池包容量 (kWh)：75 度 <600 / 100 度 <850 / 150 度
    func estimateBatteryCapacityKwh(socStatus: NIOSocStatus?) -> Double {
        guard let soc = socStatus?.soc, soc > 0, let cltc = socStatus?.remainingRange, cltc > 0 else { return 75.0 }
        let fullRange = cltc / soc * 100.0
        if fullRange >= 850 { return 150.0 }
        if fullRange >= 600 { return 100.0 }
        return 75.0
    }

    /// 桌面 Widget 快照写入失败诊断标志：App Group 不可用（免费账号签名剥离等）时只在首次失败记录，
    /// 恢复成功后记录复位日志，避免每轮轮询刷屏
    private var widgetSyncFailureLogged = false

    /// 从设置页首页标题读取车名（与 Dashboard homeTitle 一致）
    private func resolveVehicleName() -> String {
        UserDefaults.standard.string(forKey: "nio_home_title") ?? "兔可可·蔚来"
    }

    func updateLiveActivity(force: Bool = false) {
        guard let resp = vehicleData, let status = resp.data?.status else { return }

        let socStatus = status.socStatus
        let soc = socStatus?.soc ?? 0
        let cltcKm = socStatus?.remainingRange
        let actKm = socStatus?.remainingActualRange
        let hasAct = (actKm ?? 0) > 0
        let stdRange = (cltcKm ?? 0).rounded().safeInt ?? 0
        let preferActual = UserDefaults.standard.bool(forKey: "nio_prefer_actual_range")

        // bestRange: 有实估用实估，没有则 CLTC × 0.795 推算
        let best = NIOVehicleLib.bestRange(cltcKm: cltcKm, actualKm: actKm)
        let mainRange = (preferActual && hasAct) ? (actKm ?? 0).rounded().safeInt ?? 0 : (hasAct ? stdRange : (best?.km ?? stdRange))
        let subRange: Int? = {
            // 实估优先时主续航已是实估，副续航不下发 CLTC（置 nil 确保各端不显示，
            // 避免"CLTC 被误标为实估"的语义混乱）；非实估优先时副续航为真实实估值
            if preferActual && hasAct { return nil }
            if hasAct { return (actKm ?? 0).rounded().safeInt }
            if let b = best, b.isEstimated { return b.km }
            return nil
        }()
        let displayRange = mainRange

        let isCharging = NIOVehicleLib.isRealCharging(socStatus: socStatus, offcarStatus: status.offcarModeStatus)
        let chargeText = NIOVehicleLib.smartChargeStateDescription(socStatus: socStatus, offcarStatus: status.offcarModeStatus)
        let power = socStatus?.chargingPower.map { $0 / 1000.0 }

        let doors = status.doorStatus ?? [:]
        let lockSts = doors["vehicle_lock_status"]?.intValue ?? 1
        let isLocked = lockSts == 1
        let isDriving = (status.exteriorStatus?.vehicleState == 1)
        let mileage = status.exteriorStatus?.mileage.flatMap { $0.rounded().safeInt }
        let win = status.windowStatus ?? [:]
        let winOpen = (win["win_posn_fl"]?.intValue ?? 0) > 0 || (win["win_posn_fr"]?.intValue ?? 0) > 0 || (win["win_posn_rl"]?.intValue ?? 0) > 0 || (win["win_posn_rr"]?.intValue ?? 0) > 0 || (win["sun_roof_posn"]?.intValue ?? 0) > 0
        let anyDoorOpen = (doors["door_ajar_front_left_status"]?.intValue ?? 1) == 0 || (doors["door_ajar_front_right_status"]?.intValue ?? 1) == 0 || (doors["door_ajar_rear_left_status"]?.intValue ?? 1) == 0 || (doors["door_ajar_rear_right_status"]?.intValue ?? 1) == 0

        let tyre = NIOVehicleLib.extractTyreInfo(from: status)
        let offcar = status.offcarModeStatus ?? [:]
        let defInfo = NIOVehicleLib.defenderModeActive(offcar)
        let pet = NIOVehicleLib.modeActive(offcar["pet_mode_status"] ?? offcar["pet_mode"])
        let camp = NIOVehicleLib.modeActive(offcar["camping_mode_status"] ?? offcar["camping_mode"] ?? offcar["camp_mode_status"])
        let powerHold = NIOVehicleLib.modeActive(offcar["power_hold_mode_status"] ?? offcar["power_hold_mode"] ?? offcar["offcar_power_hold"])

        let frdg = status.frdgStatus ?? [:]
        let frdgPwr = (frdg["frdg_pwr_sts"]?.intValue == 1)
        let frdgTemp = frdg["frdg_cur_t"]?.doubleValue ?? frdg["frdg_tar_t"]?.doubleValue
        let v2l = (socStatus?.v2lStatus == 1)
        let lvBatt = status.lvBattStatus ?? [:]
        let lvSoc = lvBatt["lv_batt_soc"]?.intValue
        let lvVolt = lvBatt["lv_batt_volt"]?.doubleValue

        // 车机固件短版本号（取不到或仅有占位文案时不显示）
        let rawFotaVer = status.fotaStatus?.currentVersion ?? ""
        let fotaInfo = NIOVehicleLib.parseFotaInfo(version: rawFotaVer)
        let vehicleVersion = fotaInfo.shortVer.isEmpty ? nil : fotaInfo.fullDisplay

        // 充电目标（上限）：target_soc_percentage 为用户设定的限充值（与看板"目标电量"同源），
        // max_soc 是满电 CLTC 相关字段而非限充，锁电 lock_soc 最后兜底
        let rawTarget = socStatus?.targetSocPercentage ?? socStatus?.maxSoc ?? socStatus?.lockSoc ?? 0
        let targetSoc = (rawTarget > soc && rawTarget <= 100) ? rawTarget : 100.0
        let capacityKwh = estimateBatteryCapacityKwh(socStatus: socStatus)
        var etaDate: Date? = nil
        if isCharging, let p = power, p > 0.3 {
            let remainKwh = max(0.0, (targetSoc - soc) / 100.0 * capacityKwh)
            if remainKwh > 0.2 {
                etaDate = Date().addingTimeInterval(remainKwh / p * 60.0)
            }
        }

        let state = WheaterAttributes.ContentState(
            vehicleName: resolveVehicleName(),
            soc: soc,
            remainingRangeKm: displayRange,
            actualRangeKm: subRange,
            mileageKm: mileage,
            isCharging: isCharging,
            chargeStateText: chargeText,
            chargingPowerKw: power,
            isDriving: isDriving,
            isLocked: isLocked,
            anyDoorOpen: anyDoorOpen,
            anyWindowOpen: winOpen,
            tyrePressFL: tyre.fl.press,
            tyrePressFR: tyre.fr.press,
            tyrePressRL: tyre.rl.press,
            tyrePressRR: tyre.rr.press,
            insideTemp: status.hvacStatus?.temperature,
            outsideTemp: status.hvacStatus?.outsideTemperature,
            defenderActive: defInfo.isActive,
            defenderWarnCount: defInfo.warnCount,
            petModeActive: pet,
            campModeActive: camp,
            powerHoldActive: powerHold,
            frdgActive: frdgPwr,
            frdgTemp: frdgTemp,
            v2lActive: v2l,
            updateTimestamp: lastVehicleFetch ?? Date(),
            themeRaw: AnimeThemeService.shared.currentStyle.rawValue,
            chargingTargetSoc: targetSoc,
            batteryCapacityKwh: capacityKwh,
            chargeEtaDate: etaDate,
            lvBattSoc: lvSoc,
            lvBattVolt: lvVolt,
            vehicleVersion: vehicleVersion,
            preferActualRange: preferActual
        )

        // 桌面 Widget 同步：仅当快照可见内容变化（或 force 主题换装）时才落盘并触发时间线刷新。
        // 此前每轮轮询（含数据完全未变的去重早退路径）都会 reloadAllTimelines，
        // 反复唤醒 Widget Extension 进程白耗电；现在以指纹节流。
        let widgetFingerprint = [
            state.significantFingerprint,
            String(format: "%.0f", targetSoc),
            "\(mileage ?? -1)",
            String(format: "%.1f", frdgTemp ?? -99),
            String(format: "%.1f", lvVolt ?? -1)
        ].joined(separator: "#")
        if force || widgetFingerprint != lastWidgetFingerprint {
            if WheaterVehicleSnapshot.save(from: state) {
                WidgetCenter.shared.reloadAllTimelines()
                if widgetSyncFailureLogged {
                    widgetSyncFailureLogged = false
                    appendLog(NIOFetchLogEntry(
                        category: "widget_sync", level: "info",
                        message: "桌面 Widget 快照恢复写入成功",
                        detail: "App Group 容器已可用，Widget 数据恢复正常同步",
                        timestamp: Date(), requestURL: nil, requestMethod: nil,
                        requestBody: nil, responsePreview: nil, statusCode: nil
                    ))
                }
            } else if !widgetSyncFailureLogged {
                widgetSyncFailureLogged = true
                appendLog(NIOFetchLogEntry(
                    category: "widget_sync", level: "error",
                    message: "桌面 Widget 快照写入失败（App Group 容器不可用），Widget 将一直显示空状态",
                    detail: "通常因安装包缺少 App Group 权限。Xcode 直装：已修复（entitlements 已挂回 target，重新 Run 注册）；TrollStore/CI 包：重新走 CI 打包（ldid 已嵌入）",
                    timestamp: Date(), requestURL: nil, requestMethod: nil,
                    requestBody: nil, responsePreview: nil, statusCode: nil
                ))
            }
            lastWidgetFingerprint = widgetFingerprint
        }

        // 灵动岛 / 实时活动仅在系统允许时进行（Widget 快照同步不受此开关影响，见上）
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // 失效引用自愈（必须在去重早退之前）：被用户长按强制下岛后系统已移除活动，
        // 残留引用 + 未变化的指纹会导致永远无法重新上岛。
        // activities 跨进程查询有开销，本轮只取一次复用。
        let systemActivities = Activity<WheaterAttributes>.activities
        if let stale = currentActivity, !systemActivities.contains(where: { $0.id == stale.id }) {
            currentActivity = nil
            lastActivityFingerprint = nil
        }

        // 去重节流：显著数据无变化时跳过更新，降低 ActivityKit 系统刷新频率与功耗
        // force = true 时绕过（如切换主题需要立即换装）
        let fingerprint = state.significantFingerprint
        if !force, fingerprint == lastActivityFingerprint {
            self.isLiveActivityActive = isLiveActivityActive || currentActivity != nil || !systemActivities.isEmpty
            return
        }

        if let activity = currentActivity ?? systemActivities.first {
            lastActivityFingerprint = fingerprint
            Task {
                await activity.update(using: state)
            }
            self.isLiveActivityActive = true
        } else {
            do {
                let attr = WheaterAttributes(vehicleId: "NIO_VEHICLE")
                let activity = try Activity<WheaterAttributes>.request(
                    attributes: attr,
                    contentState: state,
                    pushType: nil
                )
                self.currentActivity = activity
                self.lastActivityFingerprint = fingerprint
                self.isLiveActivityActive = true
            } catch {
                // 启动失败不再静默：写入 lastError 让侧栏告警卡可见（如灵动岛开关被系统关闭）
                self.lastError = "灵动岛上岛失败：\(error.localizedDescription)"
                print("[LiveActivity] 启动失败: \(error)")
            }
        }
    }

    func stopLiveActivity() {
        Task {
            for activity in Activity<WheaterAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            self.currentActivity = nil
            self.lastActivityFingerprint = nil
            self.lastWidgetFingerprint = nil
            self.isLiveActivityActive = false
            // 灵动岛已手动结束，复位控制胶囊常亮状态，避免按钮卡在绿色"常亮中"
            self.resetControlKeepAlive()
        }
    }

    /// 复位控制胶囊常亮状态：清 App Group 标志并通知系统重渲染按钮。
    /// 所有无法继续上岛的路径（未配置、实时活动被关、请求过期、手动结束灵动岛）都必须调用，
    /// 否则锁屏/控制中心按钮会永远停在绿色"常亮中"。
    func resetControlKeepAlive() {
        UserDefaults(suiteName: "group.com.YumikoToysRR.wheater")?
            .removeObject(forKey: "nio_island_keep_alive")
        // ControlWidget 注册 kind（与 IslandControlWidget.swift 的 WheaterIslandControl.controlKind
        // 一致；该文件仅编译进扩展 target，App 侧此处直接用字面量）
        ControlCenter.shared.reloadControls(ofKind: "com.YumikoToysRR.wheater.IslandRaise")
    }

    /// 控制胶囊 / 快捷指令触发的快速上岛：清除失效引用并立即重建实时活动
    func raiseLiveActivityFromControl() {
        // 无论后续能否成功上岛，先复位按钮状态（扩展侧点击时已置常亮标志，
        // 若此处因未配置/授权关闭提前 return，按钮会卡在绿色"常亮中"）
        resetControlKeepAlive()
        guard isConfigured else { return }
        // 重装 App（换签名/换账号）后系统会重置"实时活动"授权——此前此处静默 return，
        // 胶囊点了毫无反应且无任何提示；现在明确告知用户去系统设置打开
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "实时活动已被系统关闭，无法上岛：请在 系统设置 → 隐私与安全性 → 实时活动（或本 App 设置页）中允许"
            return
        }
        if vehicleData != nil {
            updateLiveActivity(force: true)
            return
        }
        // 冷启动尚无数据：拉取空闲时主动拉一轮（正在跑的拉取轮次会自行上岛，勿重复触发），
        // 并在后台等待数据就绪后强制上岛——fetchVehicle 的 isLoadingVehicle 防并发 guard
        // 会吞掉直接发起的拉取，等待兜底确保请求不被静默丢弃（20s 内每秒探测一次）。
        if !isLoadingVehicle {
            refreshAll(force: true)
        }
        Task { @MainActor [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }
                if self.vehicleData != nil {
                    self.updateLiveActivity(force: true)
                    return
                }
            }
        }
    }

    /// 控制胶囊上岛请求的跨进程接力：Control Widget 的 intent 在 Widget 扩展进程执行，
    /// 通过 App Group 标志位 + 容器文件双通道请求主 App 上岛；主 App 回前台激活时消费。
    /// 五次探测（立即 / 0.5 / 1.2 / 2.5 / 4s）覆盖扩展写标志晚于 App 激活及冷启动动画的竞态；
    /// App 运行中场景由 Darwin 通知实时触发（见 setupIslandRaiseObserver）。
    func checkPendingIslandRaise() {
        guard isConfigured else { return }
        Task { @MainActor in
            for delay in [0.0, 0.5, 1.2, 2.5, 4.0] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                // 主通道：App Group UserDefaults
                if let defaults = UserDefaults(suiteName: "group.com.YumikoToysRR.wheater"),
                   let timestamp = defaults.object(forKey: "nio_raise_island_request") as? Double {
                    defaults.removeObject(forKey: "nio_raise_island_request")
                    guard Date().timeIntervalSince1970 - timestamp < 60 else {
                        // 请求已过期（点击后 App 迟迟未消费，如用户上滑杀掉 App），
                        // 上岛不会发生，复位控制胶囊常亮状态避免按钮卡绿
                        self.resetControlKeepAlive()
                        return
                    }
                    self.raiseLiveActivityFromControl()
                    return
                }
                // 备份通道：App Group 容器文件（UserDefaults 跨进程同步有秒级延迟时兜底）
                if let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: "group.com.YumikoToysRR.wheater"
                ) {
                    let flagURL = containerURL.appendingPathComponent("raise_island_flag")
                    if let data = try? String(contentsOf: flagURL, encoding: .utf8),
                       let timestamp = Double(data.trimmingCharacters(in: .whitespacesAndNewlines)),
                       Date().timeIntervalSince1970 - timestamp < 60 {
                        try? FileManager.default.removeItem(at: flagURL)
                        self.raiseLiveActivityFromControl()
                        return
                    }
                }
            }
        }
    }

    // MARK: - 后台刷新 (BGTaskScheduler)：App 退后台后仍定期拉取车况并刷新灵动岛

    static let backgroundRefreshTaskID = "com.YumikoToysRR.wheater.refresh"

    /// App 启动时注册（必须在 didFinishLaunching 返回前完成，由 wheaterApp.init 调用）
    nonisolated static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundRefreshTask(refreshTask)
        }
    }

    /// 预约下一次后台刷新（退到后台时调用，iOS 约 15 分钟起择机执行）
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleBackgroundRefreshTask(_ task: BGAppRefreshTask) {
        // 先预约下一次，保证后台刷新链条不断
        scheduleBackgroundRefresh()

        // setTaskCompleted 只允许调用一次：过期回调与正常完成路径谁先到谁生效，
        // 二次调用会触发系统异常
        let completionGuard = BGTaskCompletionGuard()

        let work = Task { @MainActor in
            let service = NIOService.shared
            guard service.isConfigured else {
                completionGuard.finish(task, success: false)
                return
            }
            await service.fetchVehicle(force: false) // 成功后内部自动 updateLiveActivity
            await service.fetchChange(force: false)
            completionGuard.finish(task, success: true)
        }
        task.expirationHandler = {
            work.cancel()
            // Apple 要求过期时必须上报完成；缺失会导致 watchdog 直接杀进程（0x8badf00d），
            // 后台刷新链条就此中断
            completionGuard.finish(task, success: false)
        }
    }
}

/// BGTask 完成防重入闸门：expirationHandler（任意线程）与正常完成路径（主线程）
/// 只允许第一次调用生效
private final class BGTaskCompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ task: BGAppRefreshTask, success: Bool) {
        lock.lock()
        let shouldFinish = !finished
        finished = true
        lock.unlock()
        if shouldFinish {
            task.setTaskCompleted(success: success)
        }
    }
}

// MARK: - 后台定位保活（自用方案）

/// 持续低精度定位让进程在后台存活，前台轮询 Timer 因此在后台继续跑（车况准实时刷新）。
/// 纯自用保活方案：数据本身不使用、不存储；若上架 App Store 需移除
/// （指南 2.5.4 要求后台定位与用户可见的核心功能直接相关）。
@MainActor
final class NIOLocationKeepAlive: NSObject, ObservableObject {
    static let shared = NIOLocationKeepAlive()

    @Published private(set) var isKeepingAlive = false
    /// 当前定位授权状态（设置页据此展示"主动触发授权 / 跳系统设置"入口）
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    /// 总开关（UserDefaults，默认开）：需要关闭时 `defaults write nio_location_keepalive 0`
    private static let toggleKey = "nio_location_keepalive"

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.toggleKey) as? Bool ?? true
    }

    private override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
        // 保活用：不追求精度，尽量少唤醒 GPS 硬件
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.activityType = .other
        // 关键：不允许系统自动暂停定位服务，否则后台仍会被挂起
        manager.pausesLocationUpdatesAutomatically = false
        // 后台持续收回调 = 进程不被挂起（需 Info.plist UIBackgroundModes 含 location）
        manager.allowsBackgroundLocationUpdates = true
    }

    /// 幂等启动：已配置凭证才需要保活；权限未决时先发起系统授权请求
    func requestAndStart() {
        guard isEnabled, NIOService.shared.isConfigured else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break // 用户已拒绝：静默放弃，不影响任何前台功能
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isKeepingAlive = false
    }

    private func start() {
        guard !isKeepingAlive else { return }
        manager.startUpdatingLocation()
        isKeepingAlive = true
    }
}

extension NIOLocationKeepAlive: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            NIOLocationKeepAlive.shared.authorizationStatus = status
            guard NIOLocationKeepAlive.shared.isEnabled, NIOService.shared.isConfigured else { return }
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                NIOLocationKeepAlive.shared.start()
            }
        }
    }

    /// 定位数据仅为保活信号：不使用、不记录
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
