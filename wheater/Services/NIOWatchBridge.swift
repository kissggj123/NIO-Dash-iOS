//
//  NIOWatchBridge.swift
//  wheater
//
//  iPhone → Apple Watch 数据桥（v5.7 watchOS 腕上速览）：
//  主 App 每次刷新车况成功后，把 WheaterVehicleSnapshot JSON 以 applicationContext
//  推送到已配对手表（覆盖式「最新状态」语义，手表下次激活/收包即渲染）。
//  手表端不持有任何凭证、不发任何网络请求，仅被动接收展示。
//

import Foundation
import WatchConnectivity

final class NIOWatchBridge: NSObject {
    static let shared = NIOWatchBridge()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// App 启动时调用一次：激活会话（delegate 需在激活前设置）
    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// 推送最新快照（JSON Data 打包进 applicationContext）
    func push(snapshotData: Data) {
        guard let s = session, s.activationState == .activated else { return }
        try? s.updateApplicationContext(["snapshot": snapshotData])
    }
}

extension NIOWatchBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // 手表切换（多表配对）后在新表会话上重新激活并补推
        session.activate()
    }
}
