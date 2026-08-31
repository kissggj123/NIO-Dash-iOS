//
//  PacketTunnelProvider.swift
//  WheaterPacketTunnel
//
//  iOS 系统级网络扩展隧道，负责路由网络流量至本地 MITM 嗅探代理
//

import NetworkExtension
import Network

class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // 1. 本地虚拟 IPv4 地址
        let ipv4Settings = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings

        // 2. HTTP/HTTPS 代理配置，将流量转发至主 App 本地端口 8998
        let proxySettings = NEProxySettings()
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: 8998)
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: 8998)
        proxySettings.httpEnabled = true
        proxySettings.httpsEnabled = true
        proxySettings.matchDomains = [""]
        settings.proxySettings = proxySettings

        // 3. DNS 配置
        settings.dnsSettings = NEDNSSettings(servers: ["223.5.5.5", "119.29.29.29", "8.8.8.8"])

        setTunnelNetworkSettings(settings) { error in
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }
}
