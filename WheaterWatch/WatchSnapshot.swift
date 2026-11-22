//
//  WatchSnapshot.swift
//  YumikoToysRRWatch
//
//  腕上速览车况快照模型。
//  iPhone 端把 WheaterVehicleSnapshot 用 JSONEncoder 打包成 Data 经 WatchConnectivity
//  applicationContext 推送（「最新状态」覆盖式语义）；本模型字段名与 iPhone 端快照完全一致，
//  直接以 JSON 解码对齐，不共享源文件（原文件依赖 UIKit，watchOS 编译不过，刻意平台解耦）。
//

import Foundation

struct WatchSnapshot: Codable, Equatable {
    var vehicleName: String
    var soc: Double
    var remainingRangeKm: Int
    var actualRangeKm: Int?
    var mileageKm: Int?
    var isCharging: Bool
    var chargeStateText: String
    var chargingPowerKw: Double?
    var isDriving: Bool?
    var isLocked: Bool
    var anyDoorOpen: Bool
    var insideTemp: Double?
    var outsideTemp: Double?
    var defenderActive: Bool
    var petModeActive: Bool
    var campModeActive: Bool
    var powerHoldActive: Bool
    var v2lActive: Bool?
    var hiDryActive: Bool?
    var defrostActive: Bool?
    var overheatProtectActive: Bool?
    var chargingTargetSoc: Double?
    var chargeEtaDate: Date?
    var lvBattSoc: Int?
    var lvBattVolt: Double?
    var vehicleVersion: String?
    var preferActualRange: Bool?
    var tyrePressFL: Double?
    var tyrePressFR: Double?
    var tyrePressRL: Double?
    var tyrePressRR: Double?
    var themeRaw: String?
    var refreshNotice: String?
    var updatedAt: Date

    /// 展示续航：优先实际估算续航（用户偏好时）
    var displayRangeKm: Int {
        if let actual = actualRangeKm, actual > 0, preferActualRange == true { return actual }
        return remainingRangeKm
    }

    var tyres: [(label: String, press: Double?)] {
        [("左前", tyrePressFL), ("右前", tyrePressFR), ("左后", tyrePressRL), ("右后", tyrePressRR)]
    }
}
