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

    nonisolated private func parseHTTPAndApply(_ raw: String) {
        // 分离 HTTP header 和 body（\r\n\r\n 分隔）
        let separator = "\r\n\r\n"
        guard let sepRange = raw.range(of: separator) else { return }
        let body = String(raw[sepRange.upperBound...])

        guard !body.isEmpty,
              let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        let token      = json["vehicle_token"] as? String ?? json["token"] as? String ?? ""
        let vehicleId  = json["vehicle_id"]    as? String ?? ""
        let deviceId   = json["device_id"]     as? String ?? ""
        let vehicleUrl = json["vehicle_url"]   as? String ?? ""
        let sign       = json["sign"]          as? String ?? ""

        Task { @MainActor [weak self] in
            self?.applyCredentials(
                token: token, vehicleId: vehicleId,
                deviceId: deviceId, vehicleUrl: vehicleUrl, sign: sign
            )
        }
    }

    // MARK: - 回填凭证

    @MainActor
    private func applyCredentials(token: String, vehicleId: String,
                                  deviceId: String, vehicleUrl: String, sign: String) {
        let service = NIOService.shared
        var applied: [String] = []

        if !token.isEmpty     { service.nioVehicleAccessToken = token;  applied.append("Token") }
        if !vehicleId.isEmpty { service.nioVehicleId         = vehicleId; applied.append("VehicleID") }
        if !deviceId.isEmpty  { service.nioDeviceId          = deviceId;  applied.append("DeviceID") }
        if !vehicleUrl.isEmpty, vehicleUrl.contains("nio.com") {
            service.nioVehicleApiURL = vehicleUrl
            applied.append("API URL")
        }

        guard !applied.isEmpty else {
            statusMessage = "⚠️ 收到推送但未找到有效凭证"
            return
        }

        receiveCount += 1
        lastReceivedAt = Date()
        let summary = applied.joined(separator: " · ")
        statusMessage = "✅ 已回填: \(summary)"

        // 自动复制精简凭证 JSON 到剪贴板
        var clipDict: [String: String] = [:]
        if !token.isEmpty     { clipDict["vehicle_token"] = token }
        if !vehicleId.isEmpty { clipDict["vehicle_id"]    = vehicleId }
        if !deviceId.isEmpty  { clipDict["device_id"]     = deviceId }
        if !vehicleUrl.isEmpty { clipDict["vehicle_url"]  = vehicleUrl }
        if !sign.isEmpty      { clipDict["sign"]          = sign }
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
        service.refreshAll()
    }
}
