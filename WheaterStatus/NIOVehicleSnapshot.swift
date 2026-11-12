//
//  WheaterVehicleSnapshot.swift
//  WheaterStatus
//
//  桌面 Widget 共享车况快照 (v5.2.0)
//  App 端每次刷新车况后写入 App Group；WidgetKit 时间线读取渲染。
//  本文件同时编译进主 App 与 Widget Extension 两个 target。
//

import Foundation
import UIKit
import WidgetKit

struct WheaterVehicleSnapshot: Codable {
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

    static let appGroupID = "group.com.YumikoToysRR.wheater"
    private static let storeKey = "nio_vehicle_snapshot_v1"

    /// App 端：从 Live Activity 状态提取并落盘（App Group UserDefaults）。
    /// 写入后读回验证，返回是否真正落盘成功（无 App Group 权限时 set 静默失败，读回为 nil）。
    @discardableResult
    static func save(from state: WheaterAttributes.ContentState) -> Bool {
        let snapshot = WheaterVehicleSnapshot(
            vehicleName: state.vehicleName,
            soc: state.soc,
            remainingRangeKm: state.remainingRangeKm,
            actualRangeKm: state.actualRangeKm,
            mileageKm: state.mileageKm,
            isCharging: state.isCharging,
            chargeStateText: state.chargeStateText,
            chargingPowerKw: state.chargingPowerKw,
            isDriving: state.isDriving,
            isLocked: state.isLocked,
            anyDoorOpen: state.anyDoorOpen,
            insideTemp: state.insideTemp,
            outsideTemp: state.outsideTemp,
            defenderActive: state.defenderActive,
            petModeActive: state.petModeActive,
            campModeActive: state.campModeActive,
            powerHoldActive: state.powerHoldActive,
            v2lActive: state.v2lActive,
            hiDryActive: state.hiDryActive,
            defrostActive: state.defrostActive,
            overheatProtectActive: state.overheatProtectActive,
            chargingTargetSoc: state.chargingTargetSoc,
            chargeEtaDate: state.chargeEtaDate,
            lvBattSoc: state.lvBattSoc,
            lvBattVolt: state.lvBattVolt,
            vehicleVersion: state.vehicleVersion,
            preferActualRange: state.preferActualRange,
            tyrePressFL: state.tyrePressFL,
            tyrePressFR: state.tyrePressFR,
            tyrePressRL: state.tyrePressRL,
            tyrePressRR: state.tyrePressRR,
            themeRaw: state.themeRaw,
            refreshNotice: state.refreshNotice,
            updatedAt: state.updateTimestamp
        )
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: storeKey)
        return defaults.data(forKey: storeKey) != nil
    }

    /// Widget 端：读取最新快照
    static func load() -> WheaterVehicleSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storeKey) else { return nil }
        return try? JSONDecoder().decode(WheaterVehicleSnapshot.self, from: data)
    }

    /// Widget 占位预览数据
    static var demo: WheaterVehicleSnapshot {
        WheaterVehicleSnapshot(
            vehicleName: "ET5 · 自然奇境版",
            soc: 78, remainingRangeKm: 412, actualRangeKm: 356, mileageKm: 18650,
            isCharging: true, chargeStateText: "直流快充中", chargingPowerKw: 68.5,
            isDriving: false, isLocked: true, anyDoorOpen: false,
            insideTemp: 22.5, outsideTemp: 16.0,
            defenderActive: false, petModeActive: false, campModeActive: false,
            powerHoldActive: false, v2lActive: false, hiDryActive: false,
            defrostActive: false, overheatProtectActive: false, chargingTargetSoc: 90,
            chargeEtaDate: Date().addingTimeInterval(42 * 60),
            lvBattSoc: 96, lvBattVolt: 12.8, vehicleVersion: nil,
            preferActualRange: false,
            tyrePressFL: 2.5, tyrePressFR: 2.5, tyrePressRL: 2.4, tyrePressRR: 2.4,
            themeRaw: "kawaiiLight", refreshNotice: "已更新", updatedAt: Date()
        )
    }
}

// MARK: - 小组件 / 锁屏实时活动 自定义背景（App Group 共享）
// App 端导入图片 → 缩放压缩后写入 App Group 容器；
// Widget / LiveActivity 进程直接读取同一文件渲染，文字对比度由遮罩层保证。

enum NIOWidgetBackgroundMode: String {
    case theme    // 跟随主题渐变（默认）
    case custom   // 自定义图片
}

struct NIOWidgetBackgroundStore {
    private static let modeKey = "nio_widget_bg_mode"
    private static let scrimKey = "nio_widget_bg_scrim"
    private static let fileName = "nio_widget_bg.jpg"
    /// 最长边像素上限：控制 App Group 容器体积，Widget 渲染尺寸远小于此
    private static let maxDimension: CGFloat = 1024

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WheaterVehicleSnapshot.appGroupID)?
            .appendingPathComponent(fileName)
    }

    static var hasCustomImage: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: 模式与遮罩

    static var mode: NIOWidgetBackgroundMode {
        get {
            UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?
                .string(forKey: modeKey).flatMap(NIOWidgetBackgroundMode.init(rawValue:)) ?? .theme
        }
        set {
            UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.set(newValue.rawValue, forKey: modeKey)
            reloadWidgets()
        }
    }

    /// 遮罩层开关：自定义图片上叠加深/浅色渐变，保证主题文字可读（默认开）
    static var scrimEnabled: Bool {
        get {
            UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?
                .object(forKey: scrimKey) as? Bool ?? true
        }
        set {
            UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.set(newValue, forKey: scrimKey)
            reloadWidgets()
        }
    }

    // MARK: 图片读写

    /// App 端：压缩落盘（最长边 1024，JPEG 0.85）
    static func save(image: UIImage) -> Bool {
        guard let url = fileURL else { return false }
        let resized = downscale(image)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            reloadWidgets()
            return true
        } catch {
            return false
        }
    }

    /// Widget / LiveActivity 端：仅自定义模式下读取
    static func loadImage() -> UIImage? {
        guard mode == .custom, let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        reloadWidgets()
    }

    // MARK: 内部

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 背景变化后立即刷新桌面小组件时间线（锁屏实时活动随下次更新生效）
    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
