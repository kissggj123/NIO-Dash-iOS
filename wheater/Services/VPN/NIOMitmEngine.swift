//
//  NIOMitmEngine.swift
//  wheater
//
//  蔚来专有域名 HTTPS MITM 嗅探与凭证自动提取引擎
//

import Foundation
import Network
import UIKit

public struct NIOSniffedCredentials {
    public var vehicleId: String?
    public var deviceId: String?
    public var signSecret: String?
    public var authToken: String?
    public var fullUrl: String?
    public var appVer: String?
    public var timestamp: Date = Date()
}

@MainActor
final class NIOMitmEngine: ObservableObject {
    static let shared = NIOMitmEngine()

    @Published var isRunning = false
    @Published var proxyPort: UInt16 = 8998
    @Published var lastSniffed: NIOSniffedCredentials?
    @Published var sniffCount: Int = 0
    @Published var recentSniffLogs: [String] = []

    private var listener: NWListener?
    private let proxyQueue = DispatchQueue(label: "com.yumikotoys.mitmproxy", qos: .userInitiated, attributes: .concurrent)

    private init() {}

    // MARK: - 启动本地 MITM 代理服务

    func startProxy() {
        guard listener == nil else { return }
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            let newListener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: proxyPort))
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.addLog("🟢 抓包代理服务已在 127.0.0.1:\(self?.proxyPort ?? 8998) 启动就绪")
                    case .failed(let err):
                        self?.isRunning = false
                        self?.addLog("🔴 抓包代理异常终止: \(err)")
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] clientConn in
                self?.handleClientConnection(clientConn)
            }

            newListener.start(queue: proxyQueue)
            self.listener = newListener
            self.isRunning = true
        } catch {
            print("[NIOMitmEngine] 启动代理引擎失败: \(error)")
        }
    }

    func stopProxy() {
        listener?.cancel()
        listener = nil
        isRunning = false
        addLog("⚪️ 抓包代理已关闭")
    }

    // MARK: - 处理客户端代理连接与 HTTP/HTTPS 嗅探

    nonisolated private func handleClientConnection(_ clientConn: NWConnection) {
        clientConn.start(queue: proxyQueue)
        clientConn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, let rawData = data, error == nil else {
                clientConn.cancel()
                return
            }

            let requestStr = String(data: rawData, encoding: .utf8) ?? ""
            self.inspectAndSniffTraffic(requestStr)

            // 解析 CONNECT 隧道请求
            if requestStr.hasPrefix("CONNECT ") {
                let lines = requestStr.components(separatedBy: "\r\n")
                if let firstLine = lines.first {
                    let parts = firstLine.components(separatedBy: " ")
                    if parts.count >= 2 {
                        let targetHostPort = parts[1]
                        self.handleConnectTunnel(clientConn, target: targetHostPort)
                        return
                    }
                }
            }

            // 普通 HTTP 请求直连中继
            self.handlePlainHttpRelay(clientConn, initialData: rawData, requestStr: requestStr)
        }
    }

    // MARK: - 流量特征嗅探与凭证自动提取

    nonisolated func inspectAndSniffTraffic(_ text: String) {
        // 过滤仅关注蔚来域名
        guard text.contains("nio.com") || text.contains("vehicle") || text.contains("device_id") || text.contains("Authorization") else {
            return
        }

        var creds = NIOSniffedCredentials()
        var hasFound = false

        // 1. 提取 Authorization: Bearer <Token>
        if let tokenRange = text.range(of: "Authorization: Bearer ", options: .caseInsensitive) {
            let tokenSubstring = text[tokenRange.upperBound...]
            if let endIdx = tokenSubstring.firstIndex(of: "\r") ?? tokenSubstring.firstIndex(of: "\n") {
                let token = String(tokenSubstring[..<endIdx]).trimmingCharacters(in: .whitespaces)
                if !token.isEmpty {
                    creds.authToken = token
                    hasFound = true
                }
            }
        }

        // 2. 提取 URL 与 Query 参数
        let lines = text.components(separatedBy: "\r\n")
        for line in lines {
            if line.contains("GET ") || line.contains("POST ") || line.contains("https://") || line.contains("http://") {
                if let urlRange = line.range(of: "http") {
                    let urlSub = String(line[urlRange.lowerBound...]).components(separatedBy: " ").first ?? ""
                    creds.fullUrl = urlSub
                }

                // 提取 vehicle_id
                if let vid = extractParam(from: line, key: "vehicle_id") {
                    creds.vehicleId = vid
                    hasFound = true
                } else if line.contains("/vehicle/") {
                    // /api/1/vehicle/{id}/status 模式
                    let parts = line.components(separatedBy: "/vehicle/")
                    if parts.count > 1 {
                        let vidPart = parts[1].components(separatedBy: "/").first?.components(separatedBy: "?").first ?? ""
                        if !vidPart.isEmpty && vidPart.count >= 8 {
                            creds.vehicleId = vidPart
                            hasFound = true
                        }
                    }
                }

                // 提取 device_id
                if let did = extractParam(from: line, key: "device_id") {
                    creds.deviceId = did
                    hasFound = true
                }

                // 提取 app_ver
                if let ver = extractParam(from: line, key: "app_ver") {
                    creds.appVer = ver
                }
            }
        }

        if hasFound {
            Task { @MainActor [weak self] in
                self?.applySniffedCredentials(creds)
            }
        }
    }

    nonisolated private func extractParam(from str: String, key: String) -> String? {
        let pattern = "\(key)=([^&\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count)),
              let range = Range(match.range(at: 1), in: str) else {
            return nil
        }
        return String(str[range])
    }

    @MainActor
    private func applySniffedCredentials(_ creds: NIOSniffedCredentials) {
        self.lastSniffed = creds
        self.sniffCount += 1

        let service = NIOService.shared
        var updatedFields: [String] = []

        if let vid = creds.vehicleId, !vid.isEmpty {
            service.nioVehicleId = vid
            updatedFields.append("Vehicle ID (\(vid.prefix(6))…)")
        }
        if let did = creds.deviceId, !did.isEmpty {
            service.nioDeviceId = did
            updatedFields.append("Device ID")
        }
        if let token = creds.authToken, !token.isEmpty {
            service.nioVehicleAccessToken = token
            updatedFields.append("Token")
        }
        if let url = creds.fullUrl, !url.isEmpty, url.contains("icar.nio.com") {
            service.nioVehicleApiURL = url
            updatedFields.append("RVS URL")
        }

        if !updatedFields.isEmpty {
            let msg = "🎉 成功捕获并自动回填: " + updatedFields.joined(separator: ", ")
            addLog(msg)

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // 发送全局广播通知 UI 刷新
            NotificationCenter.default.post(name: NSNotification.Name("NIO_SNIFF_SUCCESS"), object: nil)

            // 触发一次全量刷新
            service.refreshAll()
        }
    }

    private func addLog(_ log: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        recentSniffLogs.insert("[\(timestamp)] \(log)", at: 0)
        if recentSniffLogs.count > 50 {
            recentSniffLogs.removeLast()
        }
    }

    // MARK: - HTTPS CONNECT 隧道转发

    nonisolated private func handleConnectTunnel(_ clientConn: NWConnection, target: String) {
        let parts = target.components(separatedBy: ":")
        let hostStr = parts.first ?? ""
        let portInt = UInt16(parts.count > 1 ? parts[1] : "443") ?? 443

        let host = NWEndpoint.Host(hostStr)
        let port = NWEndpoint.Port(rawValue: portInt) ?? .https

        let serverParams = NWParameters.tcp
        let serverConn = NWConnection(host: host, port: port, using: serverParams)
        serverConn.start(queue: proxyQueue)

        // 响应 200 Connection Established
        let okResp = "HTTP/1.1 200 Connection Established\r\n\r\n".data(using: .utf8) ?? Data()
        clientConn.send(content: okResp, completion: .contentProcessed({ [weak self] err in
            if err == nil {
                self?.bridgeConnections(client: clientConn, server: serverConn)
            } else {
                clientConn.cancel()
                serverConn.cancel()
            }
        }))
    }

    // MARK: - HTTP 明文请求中继

    nonisolated private func handlePlainHttpRelay(_ clientConn: NWConnection, initialData: Data, requestStr: String) {
        // 从 Host 标头中提取目标
        var targetHost = "app.nio.com"
        var targetPort: UInt16 = 80
        if let hostRange = requestStr.range(of: "Host: ", options: .caseInsensitive) {
            let hostSub = requestStr[hostRange.upperBound...]
            if let endIdx = hostSub.firstIndex(of: "\r") ?? hostSub.firstIndex(of: "\n") {
                let h = String(hostSub[..<endIdx]).trimmingCharacters(in: .whitespaces)
                let hp = h.components(separatedBy: ":")
                targetHost = hp.first ?? targetHost
                if hp.count > 1, let p = UInt16(hp[1]) { targetPort = p }
            }
        }

        let host = NWEndpoint.Host(targetHost)
        let port = NWEndpoint.Port(rawValue: targetPort) ?? .http

        let serverConn = NWConnection(host: host, port: port, using: .tcp)
        serverConn.start(queue: proxyQueue)

        serverConn.send(content: initialData, completion: .contentProcessed({ [weak self] err in
            if err == nil {
                self?.bridgeConnections(client: clientConn, server: serverConn)
            } else {
                clientConn.cancel()
                serverConn.cancel()
            }
        }))
    }

    // MARK: - 双向数据中继转发

    nonisolated private func bridgeConnections(client: NWConnection, server: NWConnection) {
        // Client -> Server
        relayLoop(from: client, to: server, isFromClient: true)
        // Server -> Client
        relayLoop(from: server, to: client, isFromClient: false)
    }

    nonisolated private func relayLoop(from source: NWConnection, to destination: NWConnection, isFromClient: Bool) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self = self, let chunk = data, error == nil else {
                source.cancel()
                destination.cancel()
                return
            }

            if isFromClient {
                if let str = String(data: chunk, encoding: .utf8) {
                    self.inspectAndSniffTraffic(str)
                }
            }

            destination.send(content: chunk, completion: .contentProcessed({ sendErr in
                if sendErr == nil && !isComplete {
                    self.relayLoop(from: source, to: destination, isFromClient: isFromClient)
                } else {
                    source.cancel()
                    destination.cancel()
                }
            }))
        }
    }
}
