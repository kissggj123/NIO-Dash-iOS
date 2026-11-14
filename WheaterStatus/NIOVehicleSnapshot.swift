//
//  WheaterVehicleSnapshot.swift
//  WheaterStatus
//
//  桌面 Widget 共享车况快照 (v5.2.0)
//  App 端每次刷新车况后写入 App Group；WidgetKit 时间线读取渲染。
//  本文件同时编译进主 App 与 Widget Extension 两个 target。
//

import Foundation
import SwiftUI
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
            themeRaw: "strawberryShake", refreshNotice: "已更新", updatedAt: Date()
        )
    }
}

// MARK: - 小组件 / 锁屏实时活动 自定义背景（App Group 共享）
// App 端导入图片 → 缩放压缩后写入 App Group 容器；
// Widget / LiveActivity 进程直接读取同一文件渲染，文字对比度由遮罩层保证。

/// 展示位：三个渲染场景各自独立裁剪与存储
enum NIOWidgetBackgroundSlot: String, CaseIterable, Identifiable {
    case small   // 桌面小尺寸 1:1
    case medium  // 桌面中尺寸 2.2:1
    case lock    // 锁屏实时活动卡片 ≈1.55:1

    var id: String { rawValue }

    var fileName: String { "nio_widget_bg_\(rawValue).jpg" }

    /// 视口宽高比（裁剪与预览共用）
    var ratio: CGFloat {
        switch self {
        case .small: return 1
        case .medium: return 2.2
        case .lock: return 1.55
        }
    }

    var displayName: String {
        switch self {
        case .small: return "小尺寸"
        case .medium: return "中尺寸"
        case .lock: return "锁屏卡片"
        }
    }

    /// 兜底顺序：自身优先，其余补位（只裁一个尺寸也能先全局生效）
    var fallbackSlots: [NIOWidgetBackgroundSlot] {
        [self] + NIOWidgetBackgroundSlot.allCases.filter { $0 != self }
    }
}

enum NIOWidgetBackgroundMode: String {
    case theme    // 跟随主题渐变（默认）
    case custom   // 自定义图片
}

struct NIOWidgetBackgroundStore {
    private static let modeKey = "nio_widget_bg_mode"
    private static let scrimKey = "nio_widget_bg_scrim"
    /// 最长边像素上限：控制 App Group 容器体积，Widget 渲染尺寸远小于此
    private static let maxDimension: CGFloat = 1024
    /// 解码缓存：限制容量防止 Widget 扩展进程内存超限（扩展内存预算极低，
    /// 多个组件同时渲染时 1024px 位图 ×4MB/张 很容易触发 jetsam → 背景显示失败/骨架占位）。
    /// 配合 ImageIO 降采样解码，单张位图 ≈2.7MB，3 张上限峰值可控
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 3
        return cache
    }()

    static func fileURL(for slot: NIOWidgetBackgroundSlot) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WheaterVehicleSnapshot.appGroupID)?
            .appendingPathComponent(slot.fileName)
    }

    static func hasCustomImage(for slot: NIOWidgetBackgroundSlot) -> Bool {
        guard let url = fileURL(for: slot) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 渲染入口的轻量判断：仅检查文件存在（不触发解码）。
    /// 此前锁屏卡/小组件先用 loadImage（解码 1024px 位图）判断有无背景，
    /// 焦点视图内又解码一次 → 双份位图叠加触发扩展进程内存峰值 → 实时活动壁纸加载失败。
    static func hasRenderableImage(for slot: NIOWidgetBackgroundSlot) -> Bool {
        guard mode == .custom else { return false }
        return slot.fallbackSlots.contains { hasCustomImage(for: $0) }
    }

    // MARK: 实时活动锁屏卡渲染诊断（真机排障探针）

    private static let laDebugKey = "nio_la_bg_debug"
    private static let widgetDebugKey = "nio_widget_bg_debug"

    /// 实时活动每次归档渲染时记录真实状态（文件有无 / 解码结果 / 模式 / 版本号），
    /// App 设置页读取展示 —— 静态分析无法确定的"扩展进程里到底发生了什么"以此为准
    static func recordLockRenderDebug(
        gate: Bool, baked: Bool, focal: Bool, source: Bool, themeRaw: String?
    ) {
        let defaults = UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)
        let line = "gate=\(gate ? 1 : 0) mode=\(mode.rawValue) baked=\(baked ? 1 : 0) "
            + "focal=\(focal ? 1 : 0) src=\(source ? 1 : 0) "
            + "lockFile=\(hasCustomImage(for: .lock) ? 1 : 0) smallFile=\(hasCustomImage(for: .small) ? 1 : 0) "
            + "stamp=\(backgroundStamp) theme=\(themeRaw ?? "nil") t=\(Int(Date().timeIntervalSince1970))"
        // 只有变化才写，避免归档渲染高频重复写盘
        guard defaults?.string(forKey: laDebugKey) != line else { return }
        defaults?.set(line, forKey: laDebugKey)
    }

    /// 桌面小组件渲染探针：小组件必会重渲染，用于验证扩展进程能否写 App Group 诊断
    static func recordWidgetRenderDebug(slot: NIOWidgetBackgroundSlot, baked: Bool) {
        let defaults = UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)
        let line = "slot=\(slot.rawValue) mode=\(mode.rawValue) baked=\(baked ? 1 : 0) "
            + "file=\(hasCustomImage(for: slot) ? 1 : 0) "
            + "stamp=\(backgroundStamp) t=\(Int(Date().timeIntervalSince1970))"
        guard defaults?.string(forKey: widgetDebugKey) != line else { return }
        defaults?.set(line, forKey: widgetDebugKey)
    }

    static var lockRenderDebug: String? {
        UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.string(forKey: laDebugKey)
    }

    static var widgetRenderDebug: String? {
        UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.string(forKey: widgetDebugKey)
    }

    /// 是否存在任意展示位的自定义图
    static var hasCustomImage: Bool {
        NIOWidgetBackgroundSlot.allCases.contains { hasCustomImage(for: $0) }
    }

    /// 旧版单文件背景迁移：拷贝到三个展示位后移除旧文件（仅 App 端调用）
    static func migrateLegacyIfNeeded() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WheaterVehicleSnapshot.appGroupID) else { return }
        let legacy = base.appendingPathComponent("nio_widget_bg.jpg")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        for slot in NIOWidgetBackgroundSlot.allCases {
            let target = base.appendingPathComponent(slot.fileName)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.copyItem(at: legacy, to: target)
            }
        }
        try? FileManager.default.removeItem(at: legacy)
    }

    // MARK: 背景版本号（实时活动重绘驱动）

    private static let stampKey = "nio_widget_bg_stamp"
    /// 背景图片/模式变更时递增；随 ContentState 下发使指纹去重感知背景变化
    static var backgroundStamp: Int {
        UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.integer(forKey: stampKey) ?? 0
    }
    /// App 端监听：背景变更后立即强制推一次实时活动更新（LA 不吃 reloadAllTimelines）
    static let backgroundChangedNotification = Notification.Name("nioWidgetBackgroundChanged")

    @discardableResult
    private static func bumpStamp() -> Int {
        let defaults = UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)
        let next = (defaults?.integer(forKey: stampKey) ?? 0) + 1
        defaults?.set(next, forKey: stampKey)
        imageCache.removeAllObjects()
        Task { @MainActor in
            NotificationCenter.default.post(name: backgroundChangedNotification, object: nil)
        }
        return next
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

    /// App 端：压缩落盘（最长边 1024，JPEG 0.85），写入指定展示位
    static func save(image: UIImage, for slot: NIOWidgetBackgroundSlot) -> Bool {
        guard let url = fileURL(for: slot) else { return false }
        let resized = downscale(image)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            bumpStamp()
            reloadWidgets()
            return true
        } catch {
            return false
        }
    }

    /// Widget / LiveActivity 端：仅自定义模式下读取；自身缺失时按兜底顺序补位。
    /// ImageIO 降采样解码（紧凑位图）+ autoreleasepool，避免扩展进程内存峰值
    static func loadImage(for slot: NIOWidgetBackgroundSlot) -> UIImage? {
        guard mode == .custom else { return nil }
        return slot.fallbackSlots.lazy.compactMap { decodedImage(fileURL(for: $0), cacheKey: $0.rawValue) }.first
    }

    /// 清除单个展示位（回退到其他展示位补位 / 主题渐变）
    static func clear(slot: NIOWidgetBackgroundSlot) {
        guard let url = fileURL(for: slot) else { return }
        try? FileManager.default.removeItem(at: url)
        if let src = sourceFileURL(for: slot) {
            try? FileManager.default.removeItem(at: src)
        }
        setFocal(nil, for: slot)
        bumpStamp()
        reloadWidgets()
    }

    /// 清除全部展示位，恢复主题渐变
    static func clearAll() {
        for slot in NIOWidgetBackgroundSlot.allCases {
            guard let url = fileURL(for: slot) else { continue }
            try? FileManager.default.removeItem(at: url)
            if let src = sourceFileURL(for: slot) {
                try? FileManager.default.removeItem(at: src)
            }
            setFocal(nil, for: slot)
        }
        bumpStamp()
        reloadWidgets()
    }

    // MARK: 内部

    /// 方向归一 + 降采样：Live Photo / HEIC 的 EXIF 方向经 UIImage.draw 重绘烘焙为正立像素，
    /// 后续裁剪/渲染统一基于正立坐标（否则 cgImage 与 size 坐标系不一致会导致方向颠倒）
    static func prepare(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return image }
        let scale = min(1, maxEdge / longest)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        prepare(image, maxEdge: maxDimension)
    }

    /// 背景变化后立即刷新桌面小组件时间线（锁屏实时活动随下次更新生效）
    private static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: 遮罩微调（上帝模式）

    /// 遮罩颜色方向：跟随主题深浅 / 强制深色压暗 / 强制浅色提亮
    enum ScrimStyle: String {
        case auto
        case dark
        case light
    }

    private static let scrimStyleKey = "nio_widget_bg_scrim_style"
    private static let scrimTopKey = "nio_widget_bg_scrim_top"
    private static let scrimBottomKey = "nio_widget_bg_scrim_bottom"

    static var scrimStyle: ScrimStyle {
        get {
            UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?
                .string(forKey: scrimStyleKey).flatMap(ScrimStyle.init(rawValue:)) ?? .auto
        }
        set {
            UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.set(newValue.rawValue, forKey: scrimStyleKey)
            reloadWidgets()
        }
    }

    /// 遮罩起点浓度（左上角，0 ~ 0.85）。滑条拖动中只写值，拖动结束统一 reload
    static var scrimTopOpacity: Double {
        get { UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.object(forKey: scrimTopKey) as? Double ?? 0.38 }
        set { UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.set(newValue, forKey: scrimTopKey) }
    }

    /// 遮罩终点浓度（右下角，0 ~ 0.85）
    static var scrimBottomOpacity: Double {
        get { UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.object(forKey: scrimBottomKey) as? Double ?? 0.16 }
        set { UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.set(newValue, forKey: scrimBottomKey) }
    }

    /// 主题方向遮罩渐变；scrimEnabled=false 时返回 nil（不叠遮罩）
    static func scrimGradient(isDarkTheme: Bool) -> LinearGradient? {
        guard scrimEnabled else { return nil }
        let dark: Bool
        switch scrimStyle {
        case .auto: dark = isDarkTheme
        case .dark: dark = true
        case .light: dark = false
        }
        let base = dark ? Color.black : Color.white
        return LinearGradient(
            colors: [base.opacity(min(scrimTopOpacity, 1)), base.opacity(min(scrimBottomOpacity, 1))],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// App 端滑条拖动结束 / 开关切换后统一请求刷新
    static func reloadAllTimelines() {
        reloadWidgets()
    }

    /// 自定义背景 + 遮罩下校正主题文字色调：
    /// 压暗 → 浅色字；提亮 → 深色字；跟随主题 / 无自定义背景 → 原样
    static func adjustedTheme(from base: WheaterThemeColors) -> WheaterThemeColors {
        guard hasCustomImage, scrimEnabled else { return base }
        switch scrimStyle {
        case .auto: return base
        case .dark: return base.overridingTextTone(dark: true)
        case .light: return base.overridingTextTone(dark: false)
        }
    }

    // MARK: 焦点元数据（修复裁剪区域与实际容器比例不一致的偏差）
    // 裁剪按固定比例烘焙，而小组件/锁屏卡片实际容器比例随设备与内容行数动态变化，
    // scaledToFill 居中裁切会产生取景偏移。焦点填充：渲染端按真实容器尺寸重算变换。

    /// 裁剪时记录的取景信息（均为相对源图的归一化值）
    struct NIOWidgetBackgroundFocal: Codable {
        var cx: CGFloat      // 取景中心 x
        var cy: CGFloat      // 取景中心 y
        var covW: CGFloat    // 取景口可见宽度占比
        var covH: CGFloat    // 取景口可见高度占比
    }

    private static func focalKey(_ slot: NIOWidgetBackgroundSlot) -> String { "nio_widget_bg_focal_\(slot.rawValue)" }
    static func sourceFileURL(for slot: NIOWidgetBackgroundSlot) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WheaterVehicleSnapshot.appGroupID)?
            .appendingPathComponent("nio_widget_bg_\(slot.rawValue)_src.jpg")
    }

    static func setFocal(_ focal: NIOWidgetBackgroundFocal?, for slot: NIOWidgetBackgroundSlot) {
        let defaults = UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)
        if let focal, let data = try? JSONEncoder().encode(focal) {
            defaults?.set(data, forKey: focalKey(slot))
        } else {
            defaults?.removeObject(forKey: focalKey(slot))
        }
    }

    /// 按兜底顺序取焦点（与补图顺序一致，保证图与焦点同源）
    static func focal(for slot: NIOWidgetBackgroundSlot) -> NIOWidgetBackgroundFocal? {
        for candidate in slot.fallbackSlots {
            if let data = UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)?.data(forKey: focalKey(candidate)),
               let focal = try? JSONDecoder().decode(NIOWidgetBackgroundFocal.self, from: data) {
                return focal
            }
        }
        return nil
    }

    /// 裁剪来源整图（1024px 方向归一）；按兜底顺序取，与焦点同源
    static func sourceImage(for slot: NIOWidgetBackgroundSlot) -> UIImage? {
        guard mode == .custom else { return nil }
        return slot.fallbackSlots.lazy.compactMap { decodedImage(sourceFileURL(for: $0), cacheKey: "src_\($0.rawValue)") }.first
    }

    /// ImageIO 降采样解码：位图最长边压到 maxDimension 内，渲染时才不会按原图全量展开。
    /// 此前 UIImage(data:) 惰性解码会在首帧绘制时按原始像素展开大位图，
    /// 实时活动 + 多小组件同帧渲染叠加触发 jetsam → 壁纸整页消失
    private static func decodedImage(_ url: URL?, cacheKey: String) -> UIImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let key = cacheKey as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let decoded: UIImage? = autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,   // 烘焙 EXIF 方向
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }
        guard let image = decoded else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    /// App 端：保存裁剪来源整图（不触发刷新，由随后 save(image:for:) 统一 bump）
    @discardableResult
    static func saveSource(_ image: UIImage, for slot: NIOWidgetBackgroundSlot) -> Bool {
        guard let url = sourceFileURL(for: slot) else { return false }
        let prepared = prepare(image, maxEdge: maxDimension)
        guard let jpeg = prepared.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: 背景保存方案（三套可切换的完整配置：三张裁剪图 + 源图 + 焦点 + 遮罩参数）

    private struct PresetData: Codable {
        var mode: String
        var scrimEnabled: Bool
        var scrimStyle: String
        var scrimTop: Double
        var scrimBottom: Double
        var focals: [String: NIOWidgetBackgroundFocal]
    }

    private static func presetDir(_ index: Int) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WheaterVehicleSnapshot.appGroupID)?
            .appendingPathComponent("nio_widget_bg_presets/\(index)", isDirectory: true)
    }

    static func hasPreset(_ index: Int) -> Bool {
        guard let dir = presetDir(index) else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("preset.json").path)
    }

    /// 把当前完整配置（三张裁剪图 + 源图 + 焦点 + 遮罩参数）存入方案槽位
    @discardableResult
    static func savePreset(_ index: Int) -> Bool {
        guard let dir = presetDir(index) else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var focals: [String: NIOWidgetBackgroundFocal] = [:]
        for slot in NIOWidgetBackgroundSlot.allCases {
            let baked = dir.appendingPathComponent(slot.fileName)
            if let from = fileURL(for: slot), FileManager.default.fileExists(atPath: from.path) {
                try? FileManager.default.removeItem(at: baked)
                try? FileManager.default.copyItem(at: from, to: baked)
            }
            if let from = sourceFileURL(for: slot), FileManager.default.fileExists(atPath: from.path) {
                let target = dir.appendingPathComponent("nio_widget_bg_\(slot.rawValue)_src.jpg")
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: from, to: target)
            }
            if let f = focal(for: slot) { focals[slot.rawValue] = f }
        }
        let payload = PresetData(
            mode: mode.rawValue,
            scrimEnabled: scrimEnabled,
            scrimStyle: scrimStyle.rawValue,
            scrimTop: scrimTopOpacity,
            scrimBottom: scrimBottomOpacity,
            focals: focals
        )
        guard let json = try? JSONEncoder().encode(payload) else { return false }
        do {
            try json.write(to: dir.appendingPathComponent("preset.json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 应用方案槽位（文件回填 + 设置恢复 + 强制刷新，未存的展示位保持清除状态）
    @discardableResult
    static func applyPreset(_ index: Int) -> Bool {
        guard let dir = presetDir(index),
              let json = try? Data(contentsOf: dir.appendingPathComponent("preset.json")),
              let payload = try? JSONDecoder().decode(PresetData.self, from: json) else { return false }

        // 先清空当前（不逐步 bump）
        for slot in NIOWidgetBackgroundSlot.allCases {
            if let url = fileURL(for: slot) { try? FileManager.default.removeItem(at: url) }
            if let src = sourceFileURL(for: slot) { try? FileManager.default.removeItem(at: src) }
            setFocal(nil, for: slot)
        }

        for slot in NIOWidgetBackgroundSlot.allCases {
            let baked = dir.appendingPathComponent(slot.fileName)
            if let to = fileURL(for: slot), FileManager.default.fileExists(atPath: baked.path) {
                try? FileManager.default.removeItem(at: to)
                try? FileManager.default.copyItem(at: baked, to: to)
            }
            let src = dir.appendingPathComponent("nio_widget_bg_\(slot.rawValue)_src.jpg")
            if let to = sourceFileURL(for: slot), FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.removeItem(at: to)
                try? FileManager.default.copyItem(at: src, to: to)
            }
            if let f = payload.focals[slot.rawValue] {
                setFocal(f, for: slot)
            }
        }

        // 直接写底层 UserDefaults，避免逐项 setter 各自触发 reload
        let defaults = UserDefaults(suiteName: WheaterVehicleSnapshot.appGroupID)
        defaults?.set(payload.mode, forKey: modeKey)
        defaults?.set(payload.scrimEnabled, forKey: scrimKey)
        defaults?.set(payload.scrimStyle, forKey: scrimStyleKey)
        defaults?.set(payload.scrimTop, forKey: scrimTopKey)
        defaults?.set(payload.scrimBottom, forKey: scrimBottomKey)

        bumpStamp()
        reloadWidgets()
        Task { @MainActor in
            NotificationCenter.default.post(name: backgroundChangedNotification, object: nil)
        }
        return true
    }
}

/// 焦点填充背景视图：有焦点元数据时按真实容器尺寸重算取景（任何比例下与裁剪所见一致），
/// 无元数据回退烘焙图 scaledToFill，再回退主题渐变。
/// focalEnabled=false（实时活动锁屏卡）：GeometryReader + 显式像素 frame 的定位图
/// 在实时活动归档快照渲染中不可靠（整图渲染为空白），直接用烘焙裁剪图 scaledToFill。
struct NIOWidgetFocalBackground: View {
    let slot: NIOWidgetBackgroundSlot
    let theme: WheaterThemeColors
    var focalEnabled: Bool = true

    var body: some View {
        if focalEnabled {
            focalBody
        } else {
            bakedBody
        }
    }

    /// 焦点精确取景（小组件用）
    private var focalBody: some View {
        GeometryReader { geo in
            let container = geo.size
            if let focal = NIOWidgetBackgroundStore.focal(for: slot),
               let src = NIOWidgetBackgroundStore.sourceImage(for: slot) {
                let srcW = src.size.width, srcH = src.size.height
                // 覆盖范围映射：取景口宽度占比对准容器宽；同时保证纵向铺满
                let scale = max(container.width / (srcW * max(focal.covW, 0.05)),
                                container.height / srcH)
                let fx = focal.cx * srcW * scale
                let fy = focal.cy * srcH * scale
                // 焦点对准容器中心，并钳制不露出图外
                let posX = min(max(container.width / 2 + (srcW * scale / 2 - fx),
                                   container.width - srcW * scale / 2), srcW * scale / 2)
                let posY = min(max(container.height / 2 + (srcH * scale / 2 - fy),
                                   container.height - srcH * scale / 2), srcH * scale / 2)
                Image(uiImage: src)
                    .resizable()
                    .frame(width: srcW * scale, height: srcH * scale)
                    .position(x: posX, y: posY)
            } else {
                bakedBody
            }
        }
    }

    /// 烘焙裁剪图直接铺满（实时活动锁屏卡用，无 GeometryReader 依赖）
    @ViewBuilder
    private var bakedBody: some View {
        if let baked = NIOWidgetBackgroundStore.loadImage(for: slot) {
            Color.clear
                .overlay(Image(uiImage: baked).resizable().scaledToFill())
                .clipped()
        } else {
            LinearGradient(colors: [theme.background, theme.backgroundSoft],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
