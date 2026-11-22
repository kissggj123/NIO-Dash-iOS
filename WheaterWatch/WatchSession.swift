//
//  WatchSession.swift
//  YumikoToysRRWatch
//
//  WatchConnectivity 接收端：iPhone 主 App 每次刷新车况后以 applicationContext
//  推送最新快照（覆盖式「最新状态」语义），手表在此解码并驱动 UI。
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchSession: NSObject, ObservableObject {
    static let shared = WatchSession()

    @Published var snapshot: WatchSnapshot?
    @Published var isReachable = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = sessionDelegate
        session.activate()
    }

    /// 跨 actor 持有 delegate（非隔离小对象，仅做线程跳转）
    private nonisolated let sessionDelegate = SessionDelegate()

    func apply(data: Data) {
        guard let snap = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        self.snapshot = snap
    }
}

/// WCSessionDelegate 要求非隔离实现；收到数据后跳回主 actor 更新 UI
final class SessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            WatchSession.shared.isReachable = session.isReachable
            // 激活后立即取一次已缓存的 applicationContext（iPhone 可能在手表未连接时已更新）
            if let data = session.receivedApplicationContext["snapshot"] as? Data {
                WatchSession.shared.apply(data: data)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in
            WatchSession.shared.apply(data: data)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            WatchSession.shared.isReachable = session.isReachable
        }
    }
}
