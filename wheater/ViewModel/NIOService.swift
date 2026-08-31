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

    private var dataDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("NIO_Data", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var vehicleFile: URL { dataDirectory.appendingPathComponent("vehicle.json") }
    private var cachedTyreFile: URL { dataDirectory.appendingPathComponent("cached_tyre.json") }
    private var cachedLvBattFile: URL { dataDirectory.appendingPathComponent("cached_lv_batt.json") }
    private var cachedKeyFile: URL { dataDirectory.appendingPathComponent("cached_key.json") }
    private var cachedHeatingFile: URL { dataDirectory.appendingPathComponent("cached_heating.json") }
    private var cachedWindowFile: URL { dataDirectory.appendingPathComponent("cached_window.json") }
    private var cachedFrdgFile: URL { dataDirectory.appendingPathComponent("cached_frdg.json") }
    private var cachedBoxFile: URL { dataDirectory.appendingPathComponent("cached_box.json") }
    private var cachedLightFile: URL { dataDirectory.appendingPathComponent("cached_light.json") }
    private var historyFile: URL { dataDirectory.appendingPathComponent("history.json") }
    private var checkinFile: URL { dataDirectory.appendingPathComponent("checkin.json") }
    private var logsFile: URL { dataDirectory.appendingPathComponent("logs.json") }

    private var cachedTyreStatus: [String: NIOJSONValue]? = nil
    private var cachedLvBattStatus: [String: NIOJSONValue]? = nil
    private var cachedKeyStatus: [String: NIOJSONValue]? = nil
    private var cachedHeatingStatus: [String: NIOJSONValue]? = nil
    private var cachedWindowStatus: [String: NIOJSONValue]? = nil
    private var cachedFrdgStatus: [String: NIOJSONValue]? = nil
    private var cachedBoxStatus: [String: NIOJSONValue]? = nil
    private var cachedLightStatus: [String: NIOJSONValue]? = nil
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

        // 1. 与 Electron 版 loadFetchConfig 一致的获取策略：优先原样重放抓包的完整 RVS URL。
        //    该 URL 的 field= 参数覆盖 tyre_status（胎压）等全部状态块；
        //    Widget 接口是桌面小组件的精简数据源，不含胎压块，仅作未配置 URL 时的回退。
        if !nioVehicleApiURL.isEmpty {
            let trimmedUrl = nioVehicleApiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            var fullUrl = trimmedUrl
            if !trimmedUrl.lowercased().hasPrefix("http://") && !trimmedUrl.lowercased().hasPrefix("https://") {
                fullUrl = "https://\(trimmedUrl)"
            }
            // 已配置动态签名密钥时，对 RVS URL 每次重签名（自校验通过才生效）：
            // 保留 field=tyre 等参数拿胎压，同时 sign/timestamp 每次都是新的，永不失效
            if let resigned = NIOVehicleLib.autoResignRvsURL(fullUrl, secret: nioVehicleSignSecret, algo: nioVehicleSignAlgo) {
                targetURL = URL(string: resigned)
            }
            if targetURL == nil {
                targetURL = URL(string: fullUrl)
            }
        }

        // 2. 自动切换：未配置完整 URL 或 URL 解析失败时，自动无缝切换至 Widget 动态签名模式
        if targetURL == nil && !nioVehicleId.isEmpty {
            let devId = nioDeviceId.isEmpty ? "iOS_Device_\(nioVehicleId.prefix(6))" : nioDeviceId
            if let built = NIOVehicleLib.buildWidgetURL(
                vehicleId: nioVehicleId,
                deviceId: devId,
                secret: nioVehicleSignSecret.isEmpty ? nil : nioVehicleSignSecret,
                algo: nioVehicleSignAlgo.isEmpty ? "md5_append" : nioVehicleSignAlgo
            ) {
                targetURL = built.url
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

            // 若 RVS 接口因参数签名校验不匹配（如 invalid_param 或 sign_failed），自动无感降级到小组件接口拉取并从落盘恢复胎压
            let debugMsg = (rawJson?["debug_msg"] as? String) ?? ""
            let isSignProblem = (resultCode == "sign_failed" || resultCode.contains("sign") || resultCode == "invalid_param" || debugMsg.contains("sign") || debugMsg.contains("timestamp") || debugMsg.contains("app_id"))
            if isSignProblem && finalURL.host?.contains("icar.nio.com") == true && !self.nioDeviceId.isEmpty && !self.nioVehicleId.isEmpty {
                var fallbackURL: URL? = nil
                if !self.nioVehicleSignSecret.isEmpty {
                    fallbackURL = NIOVehicleLib.buildWidgetURL(
                        vehicleId: self.nioVehicleId,
                        deviceId: self.nioDeviceId,
                        secret: self.nioVehicleSignSecret,
                        algo: self.nioVehicleSignAlgo.isEmpty ? "md5_append" : self.nioVehicleSignAlgo
                    )?.url
                }
                if fallbackURL == nil {
                    let sgn = NIOVehicleLib.extractQueryParam(from: finalURL.absoluteString, key: "sign") ?? ""
                    let ts = NIOVehicleLib.extractQueryParam(from: finalURL.absoluteString, key: "timestamp") ?? "\(Int(Date().timeIntervalSince1970))"
                    if !sgn.isEmpty {
                        let widgetStr = "https://app.nio.com/app/api/icar/v2/widget/info?widget_size=large&app_id=10002&widget_functions=rvs_set_doorlock%2Crvs_set_air_conditioner%2Crvs_set_tailgate%2Crvs_exe_findme&lang=zh-CN&region=cn&device_id=\(self.nioDeviceId)&timestamp=\(ts)&vehicle_id=\(self.nioVehicleId)&app_ver=6.7.15&sign=\(sgn)"
                        fallbackURL = URL(string: widgetStr)
                    }
                }
                if let fbURL = fallbackURL {
                    var fbReq = URLRequest(url: fbURL)
                    fbReq.httpMethod = "GET"
                    fbReq.setValue("application/json", forHTTPHeaderField: "Accept")
                    fbReq.setValue("VehicleWidgetExtension/6.7.15 (com.do1.WeiLaiApp.NIOVehicleWidget; build:2644; iOS 27.0.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
                    if !token.isEmpty { fbReq.setValue(token, forHTTPHeaderField: "Authorization") }
                    if let (fbData, fbResp) = try? await urlSession.data(for: fbReq),
                       let fbHttp = fbResp as? HTTPURLResponse, fbHttp.statusCode == 200,
                       let fbJson = (try? JSONSerialization.jsonObject(with: fbData, options: [])) as? [String: Any],
                       let fbNormData = try? JSONSerialization.data(withJSONObject: RVSRormalizer.normalize(fbJson)),
                       let fbDecoded = try? JSONDecoder().decode(NIOVehicleResponse.self, from: fbNormData) {
                        var fbFinal = fbDecoded
                        if let cached = self.cachedTyreStatus { fbFinal.data?.status?.tyreStatus = cached }
                        if let cached = self.cachedLvBattStatus { fbFinal.data?.status?.lvBattStatus = cached }
                        if let cached = self.cachedKeyStatus { fbFinal.data?.status?.keyStatus = cached }
                        if let cached = self.cachedHeatingStatus { fbFinal.data?.status?.heatingStatus = cached }
                        if let cached = self.cachedWindowStatus { fbFinal.data?.status?.windowStatus = cached }
                        if let cached = self.cachedFrdgStatus { fbFinal.data?.status?.frdgStatus = cached }
                        if let cached = self.cachedBoxStatus { fbFinal.data?.status?.boxStatus = cached }
                        if let cached = self.cachedLightStatus { fbFinal.data?.status?.lightStatus = cached }
                        self.vehicleData = fbFinal
                        self.lastVehicleFetch = Date()
                        self.lastFetchTimestamp = Date()
                        self.lastError = nil
                        self.is403Detected = false
                        saveJSONAsync(fbFinal, to: vehicleFile)
                        appendSnapshot(fbFinal)
                        updateLog(logEntry, statusCode: 200, preview: "Widget 智能回退成功（已恢复胎压缓存）")
                        return
                    }
                }
            }

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

            // 智能数据继承与落盘缓存：当车辆驻车休眠或使用精简 Widget 接口时，若未包含有效字段，自动继承与落盘全量有效数据
            // 1. 胎压
            if NIOVehicleLib.extractTyreInfo(decoded.data?.status?.tyreStatus).hasData {
                if let newTyre = decoded.data?.status?.tyreStatus {
                    self.cachedTyreStatus = newTyre
                    saveJSONAsync(newTyre, to: cachedTyreFile)
                }
            } else {
                if let oldTyre = self.vehicleData?.data?.status?.tyreStatus, NIOVehicleLib.extractTyreInfo(oldTyre).hasData {
                    decoded.data?.status?.tyreStatus = oldTyre
                } else if let cached = self.cachedTyreStatus, NIOVehicleLib.extractTyreInfo(cached).hasData {
                    decoded.data?.status?.tyreStatus = cached
                }
            }

            // 2. 12V 辅助蓄电池
            if let newLv = decoded.data?.status?.lvBattStatus, !newLv.isEmpty {
                self.cachedLvBattStatus = newLv
                saveJSONAsync(newLv, to: cachedLvBattFile)
            } else {
                if let oldLv = self.vehicleData?.data?.status?.lvBattStatus, !oldLv.isEmpty {
                    decoded.data?.status?.lvBattStatus = oldLv
                } else if let cached = self.cachedLvBattStatus, !cached.isEmpty {
                    decoded.data?.status?.lvBattStatus = cached
                }
            }

            // 3. 智能钥匙感应
            if let newKey = decoded.data?.status?.keyStatus, !newKey.isEmpty {
                self.cachedKeyStatus = newKey
                saveJSONAsync(newKey, to: cachedKeyFile)
            } else {
                if let oldKey = self.vehicleData?.data?.status?.keyStatus, !oldKey.isEmpty {
                    decoded.data?.status?.keyStatus = oldKey
                } else if let cached = self.cachedKeyStatus, !cached.isEmpty {
                    decoded.data?.status?.keyStatus = cached
                }
            }

            // 4. 座椅舒适与方向盘加热
            if let newHeat = decoded.data?.status?.heatingStatus, !newHeat.isEmpty {
                self.cachedHeatingStatus = newHeat
                saveJSONAsync(newHeat, to: cachedHeatingFile)
            } else {
                if let oldHeat = self.vehicleData?.data?.status?.heatingStatus, !oldHeat.isEmpty {
                    decoded.data?.status?.heatingStatus = oldHeat
                } else if let cached = self.cachedHeatingStatus, !cached.isEmpty {
                    decoded.data?.status?.heatingStatus = cached
                }
            }

            // 5. 车窗开度
            if let newWin = decoded.data?.status?.windowStatus, !newWin.isEmpty {
                self.cachedWindowStatus = newWin
                saveJSONAsync(newWin, to: cachedWindowFile)
            } else {
                if let oldWin = self.vehicleData?.data?.status?.windowStatus, !oldWin.isEmpty {
                    decoded.data?.status?.windowStatus = oldWin
                } else if let cached = self.cachedWindowStatus, !cached.isEmpty {
                    decoded.data?.status?.windowStatus = cached
                }
            }

            // 6. 车载冰箱与储物
            if let newFrdg = decoded.data?.status?.frdgStatus, !newFrdg.isEmpty {
                self.cachedFrdgStatus = newFrdg
                saveJSONAsync(newFrdg, to: cachedFrdgFile)
            } else {
                if let oldFrdg = self.vehicleData?.data?.status?.frdgStatus, !oldFrdg.isEmpty {
                    decoded.data?.status?.frdgStatus = oldFrdg
                } else if let cached = self.cachedFrdgStatus, !cached.isEmpty {
                    decoded.data?.status?.frdgStatus = cached
                }
            }
            if let newBox = decoded.data?.status?.boxStatus, !newBox.isEmpty {
                self.cachedBoxStatus = newBox
                saveJSONAsync(newBox, to: cachedBoxFile)
            } else {
                if let oldBox = self.vehicleData?.data?.status?.boxStatus, !oldBox.isEmpty {
                    decoded.data?.status?.boxStatus = oldBox
                } else if let cached = self.cachedBoxStatus, !cached.isEmpty {
                    decoded.data?.status?.boxStatus = cached
                }
            }

            // 7. 车外灯光
            if let newLight = decoded.data?.status?.lightStatus, !newLight.isEmpty {
                self.cachedLightStatus = newLight
                saveJSONAsync(newLight, to: cachedLightFile)
            } else {
                if let oldLight = self.vehicleData?.data?.status?.lightStatus, !oldLight.isEmpty {
                    decoded.data?.status?.lightStatus = oldLight
                } else if let cached = self.cachedLightStatus, !cached.isEmpty {
                    decoded.data?.status?.lightStatus = cached
                }
            }

            // 8. 空调与座舱温度
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

        // 自动纠正旧的 404 路由为官方网关路由
        var targetChangeURL = nioChangeApiURL
        if targetChangeURL.contains("app.nio.com/app/api/service_charge") {
            targetChangeURL = "https://gateway-front-external.nio.com/moat/1100367/api/v1/otd/car/ext/general/serviceOrder/getTabOrder?offset=0&limit=200&orderTypes=pe_shaman,pe_shaman_change,service_pe_discharge,battery_flexible_upgrade,nsom_so_maintenance,nsom_so_chauffeur,chauffeur_vehicle_delivery,so_case_accident&hash_type=sha256&lang=zh&region=US&tz_offset=28800&app_ver=6.5.3"
            self.nioChangeApiURL = targetChangeURL
        }

        do {
            guard let url = URL(string: targetChangeURL) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("VehicleWidgetExtension/6.5.3 (com.do1.WeiLaiApp.NIOVehicleWidget; build:2612; iOS 26.5.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
            let token = normalizeBearer(nioChangeAccessToken.isEmpty ? nioVehicleAccessToken : nioChangeAccessToken)
            if !token.isEmpty {
                req.setValue(token, forHTTPHeaderField: "Authorization")
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["page_num": 1, "page_size": 20])

            let (data, response) = try await urlSession.data(for: req)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 200 {
                let decoded = try JSONDecoder().decode(NIOChangeResponse.self, from: data)
                let summary = NIOOrderLib.analyzeServiceOrders(decoded)
                self.serviceSummary = summary
            } else if let code = http?.statusCode, code >= 400 {
                let text = String(data: data, encoding: .utf8) ?? ""
                appendLog(NIOFetchLogEntry(
                    category: "change", level: "warning",
                    message: "换电拉取失败: HTTP \(code)", detail: text,
                    timestamp: Date(),
                    requestURL: targetChangeURL, requestMethod: "POST",
                    requestBody: nil, responsePreview: String(text.prefix(200)), statusCode: code
                ))
            }
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

        // 自动纠正旧的 404 路由为官方网关路由
        var targetCheckinURL = nioCheckinApiURL
        if targetCheckinURL.contains("app.nio.com/app/api/users/checkin") {
            targetCheckinURL = "https://gateway-front-external.nio.com/moat/10086//n/c/award/square?event=checkin&collection_id=1843940587332317185"
            self.nioCheckinApiURL = targetCheckinURL
        }

        do {
            guard let url = URL(string: targetCheckinURL) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("VehicleWidgetExtension/6.5.3 (com.do1.WeiLaiApp.NIOVehicleWidget; build:2612; iOS 26.5.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
            let token = normalizeBearer(nioCheckinAccessToken.isEmpty ? nioVehicleAccessToken : nioCheckinAccessToken)
            if !token.isEmpty {
                req.setValue(token, forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await urlSession.data(for: req)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 200 {
                if let rawJson = try? JSONSerialization.jsonObject(with: data) {
                    if let ci = NIOOrderLib.extractCheckinData(from: rawJson) {
                        self.checkinData = ci
                        saveJSONAsync(ci, to: checkinFile)
                    }
                }
            } else if let code = http?.statusCode, code >= 400 {
                let text = String(data: data, encoding: .utf8) ?? ""
                appendLog(NIOFetchLogEntry(
                    category: "checkin", level: "warning",
                    message: "签到拉取失败: HTTP \(code)", detail: text,
                    timestamp: Date(),
                    requestURL: targetCheckinURL, requestMethod: "GET",
                    requestBody: nil, responsePreview: String(text.prefix(200)), statusCode: code
                ))
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
        let tFile = cachedTyreFile
        let lvFile = cachedLvBattFile
        let kFile = cachedKeyFile
        let htFile = cachedHeatingFile
        let wFile = cachedWindowFile
        let fFile = cachedFrdgFile
        let bFile = cachedBoxFile
        let ltFile = cachedLightFile
        let hFile = historyFile
        let cFile = checkinFile
        let lFile = logsFile
        Task.detached(priority: .userInitiated) { [weak self] in
            var fetchedAt: Date? = nil
            var vehicle: NIOVehicleResponse? = nil
            var cachedTyre: [String: NIOJSONValue]? = nil
            var cachedLv: [String: NIOJSONValue]? = nil
            var cachedKey: [String: NIOJSONValue]? = nil
            var cachedHt: [String: NIOJSONValue]? = nil
            var cachedWin: [String: NIOJSONValue]? = nil
            var cachedFrdg: [String: NIOJSONValue]? = nil
            var cachedBox: [String: NIOJSONValue]? = nil
            var cachedLt: [String: NIOJSONValue]? = nil
            var history: [NIOVehicleSnapshot] = []
            var checkin: NIOCheckinData? = nil
            var logs: [NIOFetchLogEntry] = []

            func readDict(_ url: URL) -> [String: NIOJSONValue]? {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode([String: NIOJSONValue].self, from: data)
            }

            cachedTyre = readDict(tFile)
            cachedLv = readDict(lvFile)
            cachedKey = readDict(kFile)
            cachedHt = readDict(htFile)
            cachedWin = readDict(wFile)
            cachedFrdg = readDict(fFile)
            cachedBox = readDict(bFile)
            cachedLt = readDict(ltFile)

            if let data = try? Data(contentsOf: vFile),
               let decoded = try? JSONDecoder().decode(NIOVehicleResponse.self, from: data) {
                var v = decoded
                if v.data?.status?.tyreStatus == nil || !NIOVehicleLib.extractTyreInfo(v.data?.status?.tyreStatus).hasData {
                    if let cTyre = cachedTyre { v.data?.status?.tyreStatus = cTyre }
                }
                if v.data?.status?.lvBattStatus == nil || v.data?.status?.lvBattStatus?.isEmpty == true {
                    if let cLv = cachedLv { v.data?.status?.lvBattStatus = cLv }
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

            let finalVehicle = vehicle
            let finalCachedTyre = cachedTyre
            let finalCachedLv = cachedLv
            let finalCachedKey = cachedKey
            let finalCachedHt = cachedHt
            let finalCachedWin = cachedWin
            let finalCachedFrdg = cachedFrdg
            let finalCachedBox = cachedBox
            let finalCachedLt = cachedLt
            let finalFetchedAt = fetchedAt
            let finalHistory = history
            let finalCheckin = checkin
            let finalLogs = logs

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.cachedTyreStatus = finalCachedTyre
                self.cachedLvBattStatus = finalCachedLv
                self.cachedKeyStatus = finalCachedKey
                self.cachedHeatingStatus = finalCachedHt
                self.cachedWindowStatus = finalCachedWin
                self.cachedFrdgStatus = finalCachedFrdg
                self.cachedBoxStatus = finalCachedBox
                self.cachedLightStatus = finalCachedLt
                if let v = finalVehicle {
                    self.vehicleData = v
                    self.lastVehicleFetch = finalFetchedAt
                }
                if !finalHistory.isEmpty {
                    self.history = finalHistory
                    self.updateDerivedMetrics(from: finalHistory)
                }
                if let c = finalCheckin { self.checkinData = c }
                if !finalLogs.isEmpty { self.fetchLogs = finalLogs }
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
        let fotaInfo = NIOVehicleLib.parseFotaInfo(version: rawFotaVer)
        let vehicleVersion = fotaInfo.shortVer.isEmpty ? nil : fotaInfo.fullDisplay

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
