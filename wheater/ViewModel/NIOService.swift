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

    private var cachedTyreStatus: [String: NIOJSONValue]? = nil
    private var cachedLvBattStatus: [String: NIOJSONValue]? = nil
    private var cachedFotaStatus: NIOFotaStatus? = nil
    private var cachedDoorStatus: [String: NIOJSONValue]? = nil
    private var cachedKeyStatus: [String: NIOJSONValue]? = nil
    private var cachedHeatingStatus: [String: NIOJSONValue]? = nil
    private var cachedWindowStatus: [String: NIOJSONValue]? = nil
    private var cachedFrdgStatus: [String: NIOJSONValue]? = nil
    private var cachedBoxStatus: [String: NIOJSONValue]? = nil
    private var cachedLightStatus: [String: NIOJSONValue]? = nil
    private var cachedOffcarStatus: [String: NIOJSONValue]? = nil
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

    // MARK: - 车辆双 API 协同调度拉取架构 (参考 nio-dash / ha-nio)
    // 链路 1 (Widget 动态签名接口): 专精拉取实时 SOC 电量、充电状态/功率、行车状态、车辆闭锁、实时定位与温度 (动态签名永不过期)
    // 链路 2 (RVS 全量遥测接口): 专精拉取 4 轮胎压/胎温、车机固件 FOTA、12V 小电瓶电压/电量、7门车窗天窗开度全景、车外灯光、座椅方向盘加热、车载冰箱、离车守卫/露营/宠物模式

    func fetchVehicle(force: Bool = false) async {
        guard isConfigured else { return }
        guard !isLoadingVehicle else { return }

        // 防抖节流阀：防止短时间连续点击造成的并发突发请求
        if !force, let last = lastFetchTimestamp, Date().timeIntervalSince(last) < 8.0 {
            return
        }

        isLoadingVehicle = true
        defer {
            isLoadingVehicle = false
            scheduleNextVehiclePoll()
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

        // 2. 获取 RVS 全量遥测状态 (低频全量)
        var rvsStatus: NIOVehicleStatus? = nil
        if let rvsUrl = buildRvsTargetURL() {
            rvsStatus = await fetchRvsData(url: rvsUrl, token: token)
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
            self.lastError = "车辆数据拉取失败，请检查网络或重新抓包"
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

    private func buildRvsTargetURL() -> URL? {
        if !nioVehicleApiURL.isEmpty {
            let trimmed = nioVehicleApiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            var fullUrl = trimmed
            if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
                fullUrl = "https://\(trimmed)"
            }
            if let resigned = NIOVehicleLib.autoResignRvsURL(fullUrl, secret: nioVehicleSignSecret, algo: nioVehicleSignAlgo) {
                return URL(string: resigned)
            }
            return URL(string: fullUrl)
        }
        return nil
    }

    private func fetchWidgetData(url: URL, token: String) async -> NIOVehicleStatus? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        let appVer = NIOVehicleLib.extractQueryParam(from: url.absoluteString, key: "app_ver") ?? "6.7.15"
        req.setValue("VehicleWidgetExtension/\(appVer) (com.do1.WeiLaiApp.NIOVehicleWidget; build:2644; iOS 27.0.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
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
            }
        } catch {
            updateLog(logEntry, statusCode: nil, preview: error.localizedDescription)
        }
        return nil
    }

    private func fetchRvsData(url: URL, token: String) async -> NIOVehicleStatus? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json,text/json,text/plain", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        let appVer = NIOVehicleLib.extractQueryParam(from: url.absoluteString, key: "app_ver") ?? "6.5.3"
        req.setValue("NextevCar/\(appVer) (com.do1.WeiLaiApp; build:2586; iOS 26.2.1) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
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

        if let vid = widget?.vehicleId ?? rvs?.vehicleId ?? (base.data?.status?.vehicleId), !(vid ?? "").isEmpty {
            base.data?.status?.vehicleId = vid
        }

        return base
    }

    // MARK: - 换电服务拉取

    func fetchChange() async {
        guard isConfigured else { return }
        guard !isLoadingChange else { return }
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

        for (index, targetChangeURL) in candidates.enumerated() {
            guard let url = URL(string: targetChangeURL) else { continue }
            let isAppNio = targetChangeURL.contains("app.nio.com")

            // 尝试 POST 请求
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
                req.setValue("VehicleWidgetExtension/6.7.15 (com.do1.WeiLaiApp.NIOVehicleWidget; build:2644; iOS 27.0.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
                req.setValue(token, forHTTPHeaderField: "Authorization")
                req.httpBody = try? JSONSerialization.data(withJSONObject: isAppNio ? ["page_num": 1, "page_size": 20] : ["offset": 0, "limit": 200])

                let (data, response) = try await urlSession.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let decoded = try? JSONDecoder().decode(NIOChangeResponse.self, from: data) {
                        let summary = NIOOrderLib.analyzeServiceOrders(decoded)
                        self.serviceSummary = summary
                        return
                    }
                }
            } catch { }

            // 若 POST 404/405 则尝试 GET 请求
            if isAppNio {
                do {
                    var req = URLRequest(url: url)
                    req.httpMethod = "GET"
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.setValue("VehicleWidgetExtension/6.7.15 (com.do1.WeiLaiApp.NIOVehicleWidget; build:2644; iOS 27.0.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
                    req.setValue(token, forHTTPHeaderField: "Authorization")

                    let (data, response) = try await urlSession.data(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        if let decoded = try? JSONDecoder().decode(NIOChangeResponse.self, from: data) {
                            let summary = NIOOrderLib.analyzeServiceOrders(decoded)
                            self.serviceSummary = summary
                            return
                        }
                    }
                } catch { }
            }
        }
    }

    // MARK: - 签到拉取

    func fetchCheckin() async {
        guard isConfigured else { return }
        guard !isLoadingCheckin else { return }
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

        for (index, targetCheckinURL) in candidates.enumerated() {
            guard let url = URL(string: targetCheckinURL) else { continue }
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
                req.setValue("VehicleWidgetExtension/6.7.15 (com.do1.WeiLaiApp.NIOVehicleWidget; build:2644; iOS 27.0.0) Alamofire/5.9.1", forHTTPHeaderField: "User-Agent")
                req.setValue(token, forHTTPHeaderField: "Authorization")

                let (data, response) = try await urlSession.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let rawJson = try? JSONSerialization.jsonObject(with: data) {
                        if let ci = NIOOrderLib.extractCheckinData(from: rawJson) {
                            self.checkinData = ci
                            saveJSONAsync(ci, to: checkinFile)
                            return
                        }
                    }
                }
            } catch { }
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

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.cachedTyreStatus = finalCachedTyre
                self.cachedLvBattStatus = finalCachedLv
                self.cachedFotaStatus = finalCachedFota
                self.cachedDoorStatus = finalCachedDoor
                self.cachedKeyStatus = finalCachedKey
                self.cachedHeatingStatus = finalCachedHt
                self.cachedWindowStatus = finalCachedWin
                self.cachedFrdgStatus = finalCachedFrdg
                self.cachedBoxStatus = finalCachedBox
                self.cachedLightStatus = finalCachedLt
                self.cachedOffcarStatus = finalCachedOff
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
