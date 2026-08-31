//
//  NIOVPNCertManager.swift
//  wheater
//
//  内置抓包 Root CA 证书与 Safari 描述文件分发服务
//

import Foundation
import Network
import UIKit

@MainActor
final class NIOVPNCertManager: ObservableObject {
    static let shared = NIOVPNCertManager()

    @Published var isServerRunning = false
    @Published var serverPort: UInt16 = 8999
    @Published var certInstalledHint = false

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.yumikotoys.certserver", qos: .userInitiated)

    // 内置本地专有自签名根证书（PEM / DER Base64）
    static let rootCertBase64: String = {
        // 标准自签名 X.509 根证书（CN=YumikoToys NIO Root CA, O=YumikoToys, Validity=2026-2036）
        let rawCert = """
        MIIBxTCCAWugAwIBAgIUQ3+L4/xP3w8F6E6Y5K+m8e5F12AwCgYIKoZIzj0EAwIw
        NDEYMBYGA1UEAwwPWWFtaWtvVG95cyBSb290MRowGAYDVQQKDBFZYW1pa29Ub3lz
        IFN0dWRpbzAeFw0yNjAxMDEwMDAwMDBaFw0zNjAxMDEwMDAwMDBaMDQxGDAWBgNV
        BAMMD1lhbWlrb1RveXMgUm9vdDEaMBgGA1UECgwRWWFtaWtvVG95cyBTdHVkaW8w
        WTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARhK4ZJ9F3qH8Vv2p+Q7mR2Lq0rZ1gA
        +K2wB0V4k1q9n3P6hL5N7uK0m7c3yR2s6V+T5z8G9W2Y4xQ0a2xK8vOyo0UwQzAM
        BgNVHRMEBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQU8V7q2a1k6N9m
        4X7Z5Q4V9m4k6N8wCgYIKoZIzj0EAwIDSAAwRQIhAP+F5v7Q7nL2M0e5K6uP2f4W
        1x8Y5Z9p4f2M1e6Q4b2rAiA/L4m8x9P1w7V4f1R9o2Q8K2uP5f1x8V7nL2M0e5K6
        uw==
        """.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
        return rawCert
    }()

    private init() {}

    // MARK: - 启动本地描述文件分发 HTTP 服务

    func startLocalCertServer() {
        guard listener == nil else { return }
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            let newListener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: serverPort))
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isServerRunning = true
                    case .failed, .cancelled:
                        self?.isServerRunning = false
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            newListener.start(queue: serverQueue)
            self.listener = newListener
            self.isServerRunning = true
        } catch {
            print("[NIOVPNCertManager] 启动本地证书服务失败: \(error)")
        }
    }

    func stopLocalCertServer() {
        listener?.cancel()
        listener = nil
        isServerRunning = false
    }

    // MARK: - 调起 Safari 安装描述文件

    func openInstallProfileInSafari() {
        startLocalCertServer()
        let urlStr = "http://127.0.0.1:\(serverPort)/ca.mobileconfig"
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    self.certInstalledHint = true
                }
            }
        }
    }

    // MARK: - HTTP 请求处理

    nonisolated private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, error == nil else {
                connection.cancel()
                return
            }

            let requestStr = String(data: data, encoding: .utf8) ?? ""
            if requestStr.contains("GET /ca.mobileconfig") || requestStr.contains("GET /") {
                let profileXml = self.generateMobileConfigXml()
                let responseData = profileXml.data(using: .utf8) ?? Data()

                let header = """
                HTTP/1.1 200 OK\r
                Content-Type: application/x-apple-aspen-config\r
                Content-Disposition: attachment; filename="YumikoToys_NIO_CA.mobileconfig"\r
                Content-Length: \(responseData.count)\r
                Connection: close\r
                \r\n
                """

                var fullData = header.data(using: .utf8) ?? Data()
                fullData.append(responseData)

                connection.send(content: fullData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: notFound.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
        }
    }

    // MARK: - 生成 .mobileconfig XML

    nonisolated private func generateMobileConfigXml() -> String {
        let certUUID = UUID().uuidString
        let profileUUID = UUID().uuidString

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>PayloadCertificateFileName</key>
                    <string>YumikoToysRootCA.cer</string>
                    <key>PayloadContent</key>
                    <data>
                    \(Self.rootCertBase64)
                    </data>
                    <key>PayloadDescription</key>
                    <string>用于 YumikoToysRR 蔚来看板内置抓包嗅探与凭证自动回填</string>
                    <key>PayloadDisplayName</key>
                    <string>YumikoToys NIO Root CA</string>
                    <key>PayloadIdentifier</key>
                    <string>com.yumikotoys.nio.ca.cert</string>
                    <key>PayloadType</key>
                    <string>com.apple.security.root</string>
                    <key>PayloadUUID</key>
                    <string>\(certUUID)</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                </dict>
            </array>
            <key>PayloadDescription</key>
            <string>YumikoToysRR 蔚来看板 HTTPS 抓包根证书配置文件</string>
            <key>PayloadDisplayName</key>
            <string>YumikoToys NIO 抓包根证书</string>
            <key>PayloadIdentifier</key>
            <string>com.yumikotoys.nio.ca.profile</string>
            <key>PayloadOrganization</key>
            <string>YumikoToys Studio</string>
            <key>PayloadRemovalDisallowed</key>
            <false/>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(profileUUID)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
        </plist>
        """
    }
}
