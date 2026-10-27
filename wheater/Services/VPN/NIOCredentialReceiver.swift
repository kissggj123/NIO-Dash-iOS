//
//  NIOCredentialReceiver.swift
//  wheater
//
//  本地凭证接收服务器 — Shadowrocket 脚本直推模式
//  监听 127.0.0.1:8997，接收 Shadowrocket / Surge 脚本 POST 过来的蔚来凭证 JSON，
//  自动回填并触发系统通知与震动，无需用户手动操作。
//

import Foundation
import Network
import UIKit
import UserNotifications

@MainActor
final class NIOCredentialReceiver: ObservableObject {
    static let shared = NIOCredentialReceiver()

    @Published var isListening = false
    @Published var lastReceivedAt: Date?
    @Published var receiveCount: Int = 0
    @Published var statusMessage: String = "未启动"
    /// 上次成功应用的完整凭证指纹（token+vehicleId+deviceId），用于去重：
    /// 相同凭证重复推送时静默忽略，不再震动/覆盖剪贴板/弹提示
    private var lastAppliedFingerprint: String = ""

    private let port: UInt16 = 8997
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.yumikotoys.credential-receiver", qos: .userInitiated)

    private init() {}

    // MARK: - 启动接收服务器

    func startListening() {
        guard listener == nil else { return }
        statusMessage = "🟡 正在启动端口 8997…"
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))

            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isListening = true
                        self?.statusMessage = "🟢 等待 Shadowrocket 推送凭证…"
                    case .failed(let err):
                        self?.isListening = false
                        self?.listener = nil
                        self?.statusMessage = "🔴 启动失败: \(err)"
                    case .cancelled:
                        self?.isListening = false
                        self?.statusMessage = "⚪️ 已停止"
                    default: break
                    }
                }
            }

            l.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }

            l.start(queue: queue)
            self.listener = l
        } catch {
            statusMessage = "🔴 NWListener 创建失败: \(error)"
        }
    }

    func stopListening() {
        listener?.cancel()
        listener = nil
        isListening = false
        statusMessage = "⚪️ 已停止"
    }

    // MARK: - 处理入连接

    nonisolated private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        // 最多读取 64KB
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            defer { conn.cancel() }
            guard let self, let data, !data.isEmpty else { return }
            let raw = String(decoding: data, as: UTF8.self)
            self.parseHTTPAndApply(raw)
        }
    }

    // MARK: - 解析 HTTP 请求并提取 JSON body

    /// 清洗手工粘贴/脚本推送字段的常见杂质：markdown 反引号、包裹引号、首尾空白；
    /// 数组形态（如 ["/app/web/..."] 伪 token）视为无效
    nonisolated static func clean(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.count >= 2, (v.hasPrefix("`") && v.hasSuffix("`"))
            || (v.hasPrefix("\"") && v.hasSuffix("\"")) {
            v = String(v.dropFirst().dropLast())
        }
        v = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("[") { return "" }
        return v
    }

    nonisolated private func parseHTTPAndApply(_ raw: String) {
        // 分离 HTTP header 和 body（\r\n\r\n 分隔）
        let separator = "\r\n\r\n"
        guard let sepRange = raw.range(of: separator) else { return }
        let body = String(raw[sepRange.upperBound...])

        guard !body.isEmpty,
              let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        let token      = Self.clean(json["vehicle_token"] as? String ?? json["token"] as? String ?? "")
        let vehicleId  = Self.clean(json["vehicle_id"]    as? String ?? "")
        let deviceId   = Self.clean(json["device_id"]     as? String ?? "")
        let vehicleUrl = Self.clean(json["vehicle_url"]   as? String ?? "")
        let rvsUrl     = Self.clean(json["rvs_url"]       as? String ?? "")
        let sign       = Self.clean(json["sign"]          as? String ?? "")
        let timestamp  = Self.clean(json["timestamp"]     as? String ?? "")
        // 防多端登录指纹字段（shadowrocket / mitmproxy 脚本同步推送）
        let userGuid   = Self.clean(json["user_guid"]     as? String ?? "")
        let appVer     = Self.clean(json["app_ver"]       as? String ?? "")
        let userAgent  = Self.clean(json["user_agent"]    as? String ?? "")

        Task { @MainActor [weak self] in
            self?.applyCredentials(
                token: token, vehicleId: vehicleId,
                deviceId: deviceId, vehicleUrl: !rvsUrl.isEmpty ? rvsUrl : vehicleUrl,
                sign: sign, timestamp: timestamp,
                userGuid: userGuid, appVer: appVer, userAgent: userAgent
            )
        }
    }

    // MARK: - 回填凭证

    @MainActor
    private func applyCredentials(token: String, vehicleId: String,
                                  deviceId: String, vehicleUrl: String,
                                  sign: String, timestamp: String = "",
                                  userGuid: String = "", appVer: String = "", userAgent: String = "") {
        let service = NIOService.shared
        var applied: [String] = []
        // 设备标识：device_id 优先，User-Guid 兜底（网关请求无 query device_id）
        let effectiveDeviceId = deviceId.isEmpty ? userGuid : deviceId

        // 去重：核心三要素（token+vehicleId+deviceId）与上次完全相同 → 静默忽略。
        // 重复推送不再震动、不覆盖剪贴板、不弹横幅，只轻量记录时间。
        let fingerprint = "\(token)|\(vehicleId)|\(effectiveDeviceId)"
        if fingerprint == lastAppliedFingerprint {
            lastReceivedAt = Date()
            statusMessage = "🔁 重复推送已忽略（凭证未变化）"
            return
        }

        if !token.isEmpty     { service.nioVehicleAccessToken = token;  applied.append("Token") }
        if !vehicleId.isEmpty { service.nioVehicleId         = vehicleId; applied.append("VehicleID") }
        if !effectiveDeviceId.isEmpty { service.nioDeviceId = effectiveDeviceId; applied.append("DeviceID") }
        if !sign.isEmpty      { service.nioVehicleApiSign    = sign }
        if !timestamp.isEmpty { service.nioVehicleApiTimestamp = timestamp }
        if !vehicleUrl.isEmpty, vehicleUrl.contains("nio.com") {
            service.nioVehicleApiURL = vehicleUrl
            applied.append("API URL")
        }
        // 防多端登录指纹：存 UserDefaults 供统一 UA 构造与诊断
        if !appVer.isEmpty {
            UserDefaults.standard.set(appVer, forKey: "nio_captured_app_ver")
            applied.append("AppVer")
        }
        if !userAgent.isEmpty {
            UserDefaults.standard.set(userAgent, forKey: "nio_captured_user_agent")
        }

        guard !applied.isEmpty else {
            statusMessage = "⚠️ 收到推送但未找到有效凭证"
            return
        }

        receiveCount += 1
        lastAppliedFingerprint = fingerprint
        lastReceivedAt = Date()
        let summary = applied.joined(separator: " · ")
        statusMessage = "✅ 已回填: \(summary)"

        // 自动复制精简凭证 JSON 到剪贴板
        var clipDict: [String: String] = [:]
        if !token.isEmpty     { clipDict["vehicle_token"] = token }
        if !vehicleId.isEmpty { clipDict["vehicle_id"]    = vehicleId }
        if !effectiveDeviceId.isEmpty { clipDict["device_id"] = effectiveDeviceId }
        if !vehicleUrl.isEmpty { clipDict["vehicle_url"]  = vehicleUrl }
        if !sign.isEmpty      { clipDict["sign"]          = sign }
        if !appVer.isEmpty    { clipDict["app_ver"]       = appVer }
        if !userGuid.isEmpty  { clipDict["user_guid"]     = userGuid }
        if let clipData = try? JSONSerialization.data(withJSONObject: clipDict, options: [.prettyPrinted, .sortedKeys]),
           let clipStr = String(data: clipData, encoding: .utf8) {
            UIPasteboard.general.string = clipStr
        }

        // 震动
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)

        // 系统通知横幅
        let content = UNMutableNotificationContent()
        content.title = "🌸 蔚来凭证已自动回填！"
        content.body  = "Shadowrocket 推送成功: \(summary)"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )

        // 广播刷新
        NotificationCenter.default.post(name: NSNotification.Name("NIO_SNIFF_SUCCESS"), object: nil)
        service.refreshAll(force: true)
    }
}
