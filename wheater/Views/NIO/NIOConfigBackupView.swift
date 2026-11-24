//
//  NIOConfigBackupView.swift
//  wheater
//
//  全量配置备份与恢复 — 解决重装 App 后所有手动配置丢失的问题
//
//  导出：把 App 自身 UserDefaults 域的全部键值（NIO Token / API 地址 / 轮询 /
//        灵动岛开关 / 主题等所有手动配置）+ 收件箱载荷打包为 JSON 存到「文件」App。
//  导入：从「文件」App 选择备份 JSON，整包写回 UserDefaults。
//        @Published 属性在启动时从 UserDefaults 初始化，恢复后需重启 App 生效。
//
//  注意：内置签名密钥随 NIO_Secrets.plist 打包，重装后自动恢复，无需备份；
//        若你在设置页手动覆盖过密钥，它会作为普通 UserDefaults 键一并备份。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 备份文件文档

struct NIOConfigBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var json: [String: Any]

    init(json: [String: Any]) {
        self.json = json
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = obj
        } else {
            throw CocoaError(.propertyListReadCorrupt)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let obj = JSONSerialization.isValidJSONObject(json)
            ? (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
            : Data("{}".utf8)
        return FileWrapper(regularFileWithContents: obj)
    }
}

// MARK: - 备份视图

struct NIOConfigBackupView: View {
    @State private var isExporting = false
    @State private var exportDocument: NIOConfigBackupDocument?
    @State private var isImporting = false
    @State private var pendingImportDocument: NIOConfigBackupDocument?
    @State private var showRestoreConfirm = false
    @State private var resultText: String?
    @State private var resultIsError = false
    // 备份范围勾选（合集导出：可单独导出车辆凭证 / 观星，或全选整包）
    @State private var scopeVehicle = true
    @State private var scopeStargazing = true
    @State private var scopeCore = true

    private var selectedScopes: [String] {
        var s: [String] = []
        if scopeVehicle { s.append("vehicle") }
        if scopeStargazing { s.append("stargazing") }
        if scopeCore { s.append("core") }
        return s
    }

    private var scopeLabel: String {
        let all = selectedScopes.count == 3
        if all { return "整包" }
        let names = ["vehicle": "车辆凭证", "stargazing": "观星", "core": "基础偏好"]
        return selectedScopes.compactMap { names[$0] }.joined(separator: "+")
    }

    private var defaultFileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let kind = selectedScopes.count == 3 ? "" : "_\(selectedScopes.joined(separator: "-"))"
        return "yumikotoys_backup\(kind)_\(f.string(from: Date()))"
    }

    /// 永不备份/恢复的键：运行日志（体积大且无恢复价值）
    private static let excludedKeyFragments = ["log", "logs"]

    /// 键 → 备份范围分类（stargazing / vehicle / core，可多属）
    static func scopeKey(_ key: String) -> Set<String> {
        var scopes: Set<String> = []
        let k = key.lowercased()
        if k.contains("stargazing") { scopes.insert("stargazing") }
        if k.contains("vehicle") || k.contains("token") || k.contains("device_id")
            || k.contains("user_agent") || k.contains("captured") || k.contains("sign")
            || k.contains("api_url") || k.contains("checkin") || k.contains("fetch")
            || k.contains("push_payload") || k.contains("widget") {
            scopes.insert("vehicle")
        }
        if scopes.isEmpty { scopes.insert("core") }
        return scopes
    }

    /// 导出载荷：按勾选范围过滤的持久域键值 + 元信息（backup_scopes 标记范围，恢复端据此识别）
    private func buildBackupPayload(scopes: [String]) -> [String: Any] {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let domain = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        let isFull = scopes.count >= 3
        let filtered = domain.filter { key, _ in
            if Self.excludedKeyFragments.contains(where: { key.lowercased().contains($0) }) { return false }
            if isFull { return true }
            return !Self.scopeKey(key).isDisjoint(with: scopes)
        }
        let iso = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "backup_version": 1,
            "backup_scopes": scopes,
            "backup_kind": isFull ? "full" : "custom",
            "exported_at": iso.string(from: Date()),
            "app_version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "",
            "build": (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "",
            "bundle_id": bundleID,
            "defaults": filtered
        ]
        // 收件箱载荷（内含最近一次直推的凭证与抓包样本）仅整车导出时带上
        if scopes.contains("vehicle"), let inbox = UserDefaults.standard.object(forKey: "nio_last_push_payload") {
            payload["nio_last_push_payload"] = inbox
        }
        return payload
    }

    /// 恢复：整包写回 UserDefaults，返回恢复的键数量（智能识别卡粘贴备份时也会调用）
    @discardableResult
    static func restore(from payload: [String: Any]) -> Int {
        guard payload["backup_version"] != nil,
              let defaults = payload["defaults"] as? [String: Any] else { return 0 }
        let ud = UserDefaults.standard
        var count = 0
        for (key, value) in defaults where !excludedKeyFragments.contains(where: { key.lowercased().contains($0) }) {
            // 观星存档/规则是 Data 类型（JSON 里为 base64 字符串），走专用恢复保证类型正确
            if key.contains("stargazing") { continue }
            switch value {
            case let n as NSNumber:
                // JSON 反序列化里 Bool 与数字都是 NSNumber，用 CF 类型区分避免 true 变 1.0
                if CFGetTypeID(n) == CFBooleanGetTypeID() { ud.set(n.boolValue, forKey: key) }
                else { ud.set(n, forKey: key) }
            case let s as String: ud.set(s, forKey: key)
            case let d as Date: ud.set(d, forKey: key)
            case let data as Data: ud.set(data, forKey: key)
            case let a as [Any]: ud.set(a, forKey: key)
            case let dict as [String: Any]: ud.set(dict, forKey: key)
            default: continue
            }
            count += 1
        }
        // 观星数据专用恢复：行程去重合并入库 + 解析规则合并（旧档已补全内容不丢）
        let stargazingCount = StargazingTripStore.shared.restoreBackupStargazing(from: defaults)
        ud.synchronize()
        return count + stargazingCount
    }

    var body: some View {
        Form {
            Section {
                Text("把 App 内所有手动配置（Token、API 地址、车控与灵动岛设置、轮询间隔、主题偏好等）打包成 JSON 存到「文件」App。重装 App 后从文件导入即可完整恢复，无需重新抓包配置。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("备份范围") {
                Toggle("车辆凭证与抓包（Token/API/设备指纹）", isOn: $scopeVehicle)
                    .font(.system(size: 12))
                Toggle("观星行程与解析规则", isOn: $scopeStargazing)
                    .font(.system(size: 12))
                Toggle("基础偏好与其他配置（主题等）", isOn: $scopeCore)
                    .font(.system(size: 12))
            }

            Section("备份") {
                Button {
                    let scopes = selectedScopes
                    guard !scopes.isEmpty else {
                        showResult("请至少勾选一个备份范围", isError: true)
                        return
                    }
                    exportDocument = NIOConfigBackupDocument(json: buildBackupPayload(scopes: scopes))
                    isExporting = true
                } label: {
                    Label("导出\(scopeLabel)备份到「文件」", systemImage: "square.and.arrow.up")
                }
                if selectedScopes.count < 3 {
                    Text("已按勾选范围过滤，文件名含范围标记；恢复时自动识别，只还原对应部分")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Section("恢复") {
                Button {
                    isImporting = true
                } label: {
                    Label("从「文件」导入备份", systemImage: "square.and.arrow.down")
                }
                Text("导入会覆盖当前全部同名配置。恢复完成后请杀掉 App 重新打开，所有页面即按备份配置刷新。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let resultText {
                Section {
                    Label(resultText, systemImage: resultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(resultIsError ? .orange : .green)
                }
            }

            Section("说明") {
                LabeledContent("内置签名密钥", value: "随 App 打包，重装自动恢复")
                    .font(.system(size: 11))
                LabeledContent("手动覆盖的密钥", value: "包含在备份中")
                    .font(.system(size: 11))
                LabeledContent("历史数据/日志", value: "不包含（仅配置）")
                    .font(.system(size: 11))
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultFileName
        ) { result in
            switch result {
            case .success(let url):
                showResult("已备份到：\(url.lastPathComponent)", isError: false)
            case .failure(let error):
                showResult("备份失败：\(error.localizedDescription)", isError: true)
            }
        }
        .sheet(isPresented: $isImporting) {
            // SwiftUI fileImporter 对重装/迁移恢复的文件（UTI 元数据缺失）会置灰不可选，
            // 改用 UIDocumentPicker 不过滤类型，选中后自行校验 backup_version
            NIODocumentPicker { result in
                isImporting = false
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    do {
                        // 不指定编码让系统自动探测（重装/微信中转的文件可能是 UTF-16/带 BOM）
                        let raw = try String(contentsOf: url)
                        let text = StargazingTripStore.sanitizeJSONText(raw)
                        guard let data = text.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                            if parsed == nil {
                                showResult("JSON 解析失败：文件内容不是有效 JSON（已尝试 BOM 清洗与截取）", isError: true)
                            } else {
                                showResult("不是有效的备份文件：顶层不是 JSON 对象", isError: true)
                            }
                            return
                        }
                        guard obj["backup_version"] != nil else {
                            let keys = obj.keys.prefix(5).joined(separator: "、")
                            showResult("不是有效的备份文件（缺少 backup_version，顶层键：\(keys)…）", isError: true)
                            return
                        }
                        pendingImportDocument = NIOConfigBackupDocument(json: obj)
                        showRestoreConfirm = true
                    } catch {
                        showResult("读取失败：\(error.localizedDescription)", isError: true)
                    }
                case .failure(let error):
                    showResult("读取失败：\(error.localizedDescription)", isError: true)
                }
            }
        }
        .confirmationDialog(
            "确认恢复备份？当前同名配置将被覆盖",
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("恢复并覆盖", role: .destructive) {
                if let doc = pendingImportDocument {
                    let count = Self.restore(from: doc.json)
                    showResult(count > 0 ? "已恢复 \(count) 项配置，请重启 App 生效" : "备份为空，未恢复任何配置",
                               isError: count == 0)
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func showResult(_ text: String, isError: Bool) {
        resultText = text
        resultIsError = isError
    }
}
