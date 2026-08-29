//
//  NIOService.swift
//  wheater
//
//  蔚来 NIO 数据服务（iOS 原生适配版）
//

import Foundation
import Combine
import SwiftUI
import ActivityKit

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
    @Published var checkinData: NIOCheckinData?
    @Published var history: [NIOVehicleSnapshot] = []
    @Published var dailyPaths: [NIODailyPath] = []
    @Published var dailyMileageDeltas: [NIODailyDelta] = []
    @Published var fetchLogs: [NIOFetchLogEntry] = []

    @Published var isLoadingVehicle = false
    @Published var isLoadingChange = false
    @Published var isLoadingCheckin = false
    @Published var lastError: String?
    @Published var lastVehicleFetch: Date?
    @Published var is403Detected = false

    var isConfigured: Bool {
        if nioVehicleApiMode == "widget" || (!nioVehicleId.isEmpty && !nioDeviceId.isEmpty && !nioVehicleSignSecret.isEmpty) {
            return !nioVehicleId.isEmpty && !nioDeviceId.isEmpty && !nioVehicleAccessToken.isEmpty
        }
        return !nioVehicleApiURL.isEmpty && !nioVehicleAccessToken.isEmpty
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

    private var dataDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("NIO_Data", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var vehicleFile: URL { dataDirectory.appendingPathComponent("vehicle.json") }
    private var historyFile: URL { dataDirectory.appendingPathComponent("history.json") }
    private var checkinFile: URL { dataDirectory.appendingPathComponent("checkin.json") }
    private var logsFile: URL { dataDirectory.appendingPathComponent("logs.json") }

    private var lastFetchTimestamp: Date? = nil

    private init() {
        loadPersistedData()
        startScheduling()
        setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 进入后台暂停轮询定时器，彻底杜绝后台无效网络唤醒与并发冲突
            self?.vehicleTimer?.invalidate()
            self?.vehicleTimer = nil
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 回到前台后平滑恢复调度，若数据已超 2 分钟则轻量刷新一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let self = self else { return }
                if let last = self.lastVehicleFetch, Date().timeIntervalSince(last) > 120 {
                    Task { await self.fetchVehicle(force: false) }
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
            Task { @MainActor in
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

    func refreshAll() {
        Task {
            async let v: () = fetchVehicle(force: true)
            async let c: () = fetchChange()
            async let k: () = fetchCheckin()
            _ = await (v, c, k)
            self.lastVehicleFetch = Date()
        }
    }

    // MARK: - 车辆数据拉取

    func fetchVehicle(force: Bool = false) async {
        guard isConfigured else { return }
        guard !isLoadingVehicle else { return }

        // 防抖节流阀：防止 10 秒内双端或连续点击造成的并发突发请求
        if !force, let last = lastFetchTimestamp, Date().timeIntervalSince(last) < 10.0 {
            return
        }

        var targetURL: URL? = nil

        // 1. 若配置为 Widget 签名模式，或具备完整的 Widget 参数，动态生成带当前时间戳和签名的 URL
        if nioVehicleApiMode == "widget" || (!nioVehicleId.isEmpty && !nioDeviceId.isEmpty && !nioVehicleSignSecret.isEmpty) {
            if let built = NIOVehicleLib.buildWidgetURL(
                vehicleId: nioVehicleId,
                deviceId: nioDeviceId,
                secret: nioVehicleSignSecret.isEmpty ? nil : nioVehicleSignSecret,
                algo: nioVehicleSignAlgo.isEmpty ? "md5_append" : nioVehicleSignAlgo
            ) {
                targetURL = built.url
            }
        }

        // 2. 若不是动态 Widget 模式，使用配置的 URL
        if targetURL == nil && !nioVehicleApiURL.isEmpty {
            let trimmedUrl = nioVehicleApiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUrl.lowercased().hasPrefix("http://") && !trimmedUrl.lowercased().hasPrefix("https://") {
                targetURL = URL(string: "https://\(trimmedUrl)")
            } else {
                targetURL = URL(string: trimmedUrl)
            }
        }

        guard let finalURL = targetURL else {
            lastError = "车辆 API URL 无效"
            return
        }

        isLoadingVehicle = true
        defer { isLoadingVehicle = false }

        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        req.setValue("application/json,text/json,text/plain", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")

        // 动态提取抓包 URL 中的 app_ver，构造与抓包完全匹配的原生 User-Agent 与 Host 标头（移植自 ha-nio）
        let appVer = NIOVehicleLib.extractQueryParam(from: finalURL.absoluteString, key: "app_ver") ?? "6.5.3"
        req.setValue("NextevCar/\(appVer) (com.do1.WeiLaiApp; build:2586; iOS 26.2.1) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")

        let host = finalURL.host?.lowercased() ?? ""
        if host.contains("icar.nio.com") {
            req.setValue("tsp.nio.com", forHTTPHeaderField: "Host")
        }

        let token = normalizeBearer(nioVehicleAccessToken)
        if !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "Authorization")
        }

        let logEntry = NIOFetchLogEntry(
            category: "vehicle", level: "info",
            message: "车辆 · 开始拉取…",
            detail: nil, timestamp: Date(),
            requestURL: finalURL.absoluteString, requestMethod: "GET",
            requestBody: nil, responsePreview: nil, statusCode: nil
        )
        appendLog(logEntry)

        var httpResponse: HTTPURLResponse? = nil
        var responseText: String = ""

        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw NIOError.invalidJSON }
            httpResponse = http
            let text = String(data: data, encoding: .utf8) ?? ""
            responseText = text

            let rawJson = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
            let resultCode = (rawJson?["result_code"] as? String) ?? (rawJson?["resultCode"] as? String) ?? ""
            let debugMsg = (rawJson?["debug_msg"] as? String) ?? ""

            // 精准区分【签名不匹配 sign_failed】与【账号 Token 被踢 auth_failed】
            if resultCode == "sign_failed" || resultCode.contains("sign") {
                self.is403Detected = true
                let hint = "签名校验被拒 (sign_failed)：抓包 URL 的签名与当前 App 版本不匹配。请在蔚来 App 中下拉刷新重新抓取完整的状态 URL（请勿改动任何参数）。"
                self.lastError = hint
                updateLog(logEntry, statusCode: http.statusCode, preview: String(text.prefix(300)))
                throw NIOError.unauthorized403(hint)
            }

            if http.statusCode == 403 || http.statusCode == 401 || resultCode == "auth_failed" || resultCode.contains("auth") || resultCode.contains("token") {
                self.is403Detected = true
                let hint = "鉴权 Token 失效：蔚来账号已在其他设备重新登录或已过期。请重新抓取并更新 Token。"
                self.lastError = hint
                updateLog(logEntry, statusCode: http.statusCode, preview: String(text.prefix(300)))
                throw NIOError.unauthorized403(hint)
            }

            if http.statusCode != 200 {
                throw NIOError.httpError(http.statusCode, String(text.prefix(500)))
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NIOError.emptyResponse
            }

            guard let rawDict = rawJson else { throw NIOError.invalidJSON }

            let normalized = RVSRormalizer.normalize(rawDict)
            let normalizedData = try JSONSerialization.data(withJSONObject: normalized)
            var decoded = try JSONDecoder().decode(NIOVehicleResponse.self, from: normalizedData)

            // 智能数据继承：当车辆驻车休眠时，若接口未包含有效胎压或空调温度，自动继承上一轮有效数据
            if !NIOVehicleLib.extractTyreInfo(decoded.data?.status?.tyreStatus).hasData {
                if let oldTyre = self.vehicleData?.data?.status?.tyreStatus, NIOVehicleLib.extractTyreInfo(oldTyre).hasData {
                    decoded.data?.status?.tyreStatus = oldTyre
                }
            }
            if decoded.data?.status?.hvacStatus?.temperature == nil {
                if let oldTemp = self.vehicleData?.data?.status?.hvacStatus?.temperature {
                    if decoded.data?.status?.hvacStatus != nil {
                        decoded.data?.status?.hvacStatus?.temperature = oldTemp
                    } else {
                        decoded.data?.status?.hvacStatus = NIOHvacStatus(temperature: oldTemp)
                    }
                }
            }
            if decoded.data?.status?.hvacStatus?.outsideTemperature == nil {
                if let oldOutTemp = self.vehicleData?.data?.status?.hvacStatus?.outsideTemperature {
                    decoded.data?.status?.hvacStatus?.outsideTemperature = oldOutTemp
                }
            }

            self.vehicleData = decoded
            self.lastVehicleFetch = Date()
            self.lastFetchTimestamp = Date()
            self.lastError = nil
            self.is403Detected = false

            // 同步刷新 iOS 灵动岛与锁屏实时活动
            self.updateLiveActivity()

            saveJSONAsync(decoded, to: vehicleFile)
            appendSnapshot(decoded)
            updateLog(logEntry, statusCode: http.statusCode, preview: String(text.prefix(200)))

            if let checkedIn = decoded.data?.checkedIn {
                let ci = NIOCheckinData(
                    checkedIn: checkedIn.checked ?? false,
                    continuousDays: checkedIn.days ?? 0
                )
                self.checkinData = ci
                saveJSONAsync(ci, to: checkinFile)
            }
        } catch let err as DecodingError {
            let desc: String
            switch err {
            case .typeMismatch(let type, let context):
                desc = "类型不匹配: 期望 \(type), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)"
            case .valueNotFound(let type, let context):
                desc = "缺少值: \(type), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)"
            case .keyNotFound(let key, let context):
                desc = "缺少字段: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)"
            case .dataCorrupted(let context):
                desc = "数据损坏: 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)"
            @unknown default:
                desc = err.localizedDescription
            }
            self.lastError = desc
            appendLog(NIOFetchLogEntry(
                category: "vehicle", level: "error",
                message: "解析失败：\(desc)", detail: desc,
                timestamp: Date(),
                requestURL: finalURL.absoluteString, requestMethod: "GET",
                requestBody: nil, responsePreview: responseText.isEmpty ? nil : String(responseText.prefix(300)), statusCode: httpResponse?.statusCode
            ))
        } catch {
            let nsErr = error as NSError
            if error is CancellationError || (error as? URLError)?.code == .cancelled || nsErr.code == NSURLErrorCancelled || error.localizedDescription.lowercased().contains("cancel") {
                // 正常任务取消，静默忽略，不设置 lastError，不写入错误日志
                return
            }
            let msg = error.localizedDescription
            self.lastError = msg
            appendLog(NIOFetchLogEntry(
                category: "vehicle", level: "error",
                message: "拉取失败：\(msg)", detail: msg,
                timestamp: Date(),
                requestURL: finalURL.absoluteString, requestMethod: "GET",
                requestBody: nil, responsePreview: responseText.isEmpty ? nil : String(responseText.prefix(300)), statusCode: httpResponse?.statusCode
            ))
        }
    }

    // MARK: - 换电服务拉取

    func fetchChange() async {
        guard !nioChangeApiURL.isEmpty else { return }
        guard !isLoadingChange else { return }
        isLoadingChange = true
        defer { isLoadingChange = false }

        do {
            guard let url = URL(string: nioChangeApiURL) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let token = normalizeBearer(nioChangeAccessToken.isEmpty ? nioVehicleAccessToken : nioChangeAccessToken)
            if !token.isEmpty {
                req.setValue(token, forHTTPHeaderField: "Authorization")
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["page_num": 1, "page_size": 20])

            let (data, _) = try await urlSession.data(for: req)
            let decoded = try JSONDecoder().decode(NIOChangeResponse.self, from: data)
            let summary = NIOOrderLib.analyzeServiceOrders(decoded)
            self.serviceSummary = summary
        } catch {
            // 静默失败
        }
    }

    // MARK: - 签到拉取

    func fetchCheckin() async {
        guard !nioCheckinApiURL.isEmpty else { return }
        guard !isLoadingCheckin else { return }
        isLoadingCheckin = true
        defer { isLoadingCheckin = false }

        do {
            guard let url = URL(string: nioCheckinApiURL) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let token = normalizeBearer(nioCheckinAccessToken.isEmpty ? nioVehicleAccessToken : nioCheckinAccessToken)
            if !token.isEmpty {
                req.setValue(token, forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await urlSession.data(for: req)
            if let ci = try? JSONDecoder().decode(NIOCheckinData.self, from: data) {
                self.checkinData = ci
                saveJSONAsync(ci, to: checkinFile)
            }
        } catch {
            // 静默失败
        }
    }

    // MARK: - 智能识别与一键填充

    func smartParseInput(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

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
        let hFile = historyFile
        let cFile = checkinFile
        let lFile = logsFile
        Task.detached(priority: .userInitiated) { [weak self] in
            var fetchedAt: Date? = nil
            var vehicle: NIOVehicleResponse? = nil
            var history: [NIOVehicleSnapshot] = []
            var checkin: NIOCheckinData? = nil
            var logs: [NIOFetchLogEntry] = []

            if let data = try? Data(contentsOf: vFile),
               let decoded = try? JSONDecoder().decode(NIOVehicleResponse.self, from: data) {
                vehicle = decoded
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

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if let vehicle = vehicle {
                    self.vehicleData = vehicle
                    self.lastVehicleFetch = fetchedAt
                }
                if !history.isEmpty {
                    self.history = history
                    self.updateDerivedMetrics(from: history)
                }
                if let checkin = checkin { self.checkinData = checkin }
                if !logs.isEmpty { self.fetchLogs = logs }
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

    /// 依据满电 CLTC 续航推算电池包容量 (kWh)：75 度 <600 / 100 度 <850 / 150 度
    private func estimateBatteryCapacityKwh(socStatus: NIOSocStatus?) -> Double {
        guard let soc = socStatus?.soc, soc > 0, let cltc = socStatus?.remainingRange, cltc > 0 else { return 75.0 }
        let fullRange = cltc / soc * 100.0
        if fullRange >= 850 { return 150.0 }
        if fullRange >= 600 { return 100.0 }
        return 75.0
    }

    func updateLiveActivity(force: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let resp = vehicleData, let status = resp.data?.status else { return }

        let socStatus = status.socStatus
        let soc = socStatus?.soc ?? 0
        let cltcKm = socStatus?.remainingRange
        let actKm = socStatus?.remainingActualRange
        let hasAct = (actKm ?? 0) > 0
        let stdRange = Int(round(cltcKm ?? 0))
        let preferActual = UserDefaults.standard.bool(forKey: "nio_prefer_actual_range")

        // bestRange: 有实估用实估，没有则 CLTC × 0.795 推算
        let best = NIOVehicleLib.bestRange(cltcKm: cltcKm, actualKm: actKm)
        let mainRange = (preferActual && hasAct) ? Int(round(actKm!)) : (hasAct ? stdRange : (best?.km ?? stdRange))
        let subRange: Int? = {
            if preferActual && hasAct { return stdRange }
            if hasAct { return Int(round(actKm!)) }
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
        let mileage = status.exteriorStatus?.mileage.map { Int(round($0)) }
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
        let shortFotaVer = NIOVehicleLib.shortFotaVersion(rawFotaVer)
        let vehicleVersion = (rawFotaVer.isEmpty || shortFotaVer == "智能系统") ? nil : shortFotaVer

        // 充电目标（上限优先，锁电兜底）与充满 ETA
        let rawTarget = socStatus?.maxSoc ?? socStatus?.lockSoc ?? 0
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
            vehicleName: "兔可可 · 蔚来",
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
            updateTimestamp: Date(),
            themeRaw: AnimeThemeService.shared.currentStyle.rawValue,
            chargingTargetSoc: targetSoc,
            batteryCapacityKwh: capacityKwh,
            chargeEtaDate: etaDate,
            lvBattSoc: lvSoc,
            lvBattVolt: lvVolt,
            vehicleVersion: vehicleVersion,
            preferActualRange: preferActual
        )

        // 去重节流：显著数据无变化时跳过更新，降低 ActivityKit 系统刷新频率与功耗
        // force = true 时绕过（如切换主题需要立即换装）
        let fingerprint = state.significantFingerprint
        if !force, fingerprint == lastActivityFingerprint {
            self.isLiveActivityActive = isLiveActivityActive || currentActivity != nil || !Activity<WheaterAttributes>.activities.isEmpty
            return
        }

        if let activity = currentActivity ?? Activity<WheaterAttributes>.activities.first {
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
            self.isLiveActivityActive = false
        }
    }
}
