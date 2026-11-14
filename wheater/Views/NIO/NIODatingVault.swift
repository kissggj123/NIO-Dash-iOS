//
//  NIODatingVault.swift
//  wheater
//
//  恋爱好感度实验室 · 加密金库层
//
//  安全设计：
//  1. 每人的原始评分与心动留言以 AES-256-GCM 密封，密钥由本人 6 位密码经 2 万轮 SHA256 拉伸派生 ——
//     没有密码，任何人都无法解密明文（包括 App 界面本身）。
//  2. 综合分聚合金库以 Keychain 中的随机设备密钥密封，仅存双方聚合统计，界面永不展示个人原始分。
//  3. 心动留言的情绪倾向由 Apple NaturalLanguage 端内情感分析模型实时演算（数据不出本机）。
//  4. 密码验证带失败递增冷却，防止同机暴力尝试。
//

import Foundation
import CryptoKit
import Security
import NaturalLanguage
import SwiftUI

// MARK: - NaturalLanguage 实时情感分析

enum NIODatingSentiment {

    /// 端内 NLP 模型实时计算留言情绪倾向 ∈ [-1, 1]（Apple 神经引擎本地演算，不上传）
    static func score(of text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = trimmed
        let (tag, _) = tagger.tag(at: trimmed.startIndex, unit: .paragraph, scheme: .sentimentScore)
        guard let raw = tag?.rawValue, let value = Double(raw) else { return nil }
        return min(1, max(-1, value))
    }

    /// 情感解读文案（评分表实时展示用）
    static func readingDescription(for sentiment: Double?) -> (text: String, icon: String) {
        guard let s = sentiment else { return ("感应待机中，写下留言即刻演算", "🛰") }
        switch s {
        case 0.5...: return ("感应到浓烈的心动信号 +\(String(format: "%.1f", s * 6))分", "💗")
        case 0.15..<0.5: return ("感应到甜甜的暖意 +\(String(format: "%.1f", s * 6))分", "🍬")
        case -0.15..<0.15: return ("情绪平稳，心如止水 ±0", "🍃")
        case -0.5..<(-0.15): return ("感应到一丝小情绪 \(String(format: "%.1f", s * 6))分", "🌧")
        default: return ("感应到明显委屈，抱抱 TA \(String(format: "%.1f", s * 6))分", "⛈")
        }
    }
}

// MARK: - 持久化结构

/// 密码验证器（存储拉伸盐 + 摘要，绝不存储密码本身）
struct NIODatingPasswordVerifier: Codable {
    var stretchSalt: Data
    var checkSalt: Data
    var digest: Data
}

/// 单方聚合摘要（存入设备密钥密封的聚合金库，界面永不直接展示）
struct NIODatingSideSummary: Codable {
    var means: [String: Double]
    var effective: Double
    var sentiment: Double
    var chapters: Int
    var lastUpdate: Date
    /// 累计评分轮次（2026-11-14 新增，用于 EMA 平滑与稳定度判定；旧数据无此字段）
    var rounds: Int?
}

/// 聚合金库（双方摘要，设备密钥密封后持久化）
struct NIODatingCompositeVault: Codable {
    var mikan: NIODatingSideSummary?
    var xia: NIODatingSideSummary?

    func side(for member: NIODatingMember) -> NIODatingSideSummary? {
        member == .mikan ? mikan : xia
    }

    mutating func setSide(_ summary: NIODatingSideSummary, for member: NIODatingMember) {
        if member == .mikan { mikan = summary } else { xia = summary }
    }
}

// MARK: - 提交结果

enum NIODatingSubmitOutcome: Equatable {
    /// 提交成功：chapterTitle 为本章标题；deltaFromPrevious 为有效分较上一轮的变化量（首轮为 nil）
    case success(chapterTitle: String, deltaFromPrevious: Double?)
    case wrongPassword
    case locked(remainingSeconds: TimeInterval)
    case storageFailure
}

// MARK: - 金库

@MainActor
final class NIODatingVault: ObservableObject {

    static let shared = NIODatingVault()

    // MARK: 发布状态

    /// 双方是否都完成密码设置
    @Published private(set) var isConfigured = false
    /// 当前聚合快照（双方都完成首轮评分后生成；仅含聚合信息）
    @Published private(set) var snapshot: NIODatingCompositeSnapshot?
    /// 蜜柑是否已评过分
    @Published private(set) var hasMikanRated = false
    /// 夏老师是否已评过分
    @Published private(set) var hasXiaRated = false
    /// 上一次提交的章节标题（用于成功横幅）
    @Published private(set) var lastSubmitOutcome: NIODatingSubmitOutcome?
    /// 关系阶段：初识心动期 / 深度关系期（决定维度体系与权重）
    @Published private(set) var stage: NIODatingStage = .firstSpark

    private let defaults = UserDefaults.standard

    // MARK: 存储键

    private enum StoreKey {
        static func verifier(_ m: NIODatingMember) -> String { "nio_dating_verifier_\(m.rawValue)" }
        static func sealedScores(_ m: NIODatingMember) -> String { "nio_dating_sealed_\(m.rawValue)" }
        static func failedCount(_ m: NIODatingMember) -> String { "nio_dating_failed_\(m.rawValue)" }
        static func lockUntil(_ m: NIODatingMember) -> String { "nio_dating_lock_\(m.rawValue)" }
        static let compositeVault = "nio_dating_composite_vault"
        static let snapshot = "nio_dating_snapshot"
        static let stage = "nio_dating_stage"
    }

    private init() {
        refreshConfigState()
    }

    /// 指定成员是否已设置密码（引导期中断后可断点续设）
    func isMemberConfigured(_ member: NIODatingMember) -> Bool {
        loadVerifier(for: member) != nil
    }

    /// 从磁盘刷新配置与快照状态（冷启动 / 重置后调用）
    func refreshConfigState() {
        isConfigured = loadVerifier(for: .mikan) != nil && loadVerifier(for: .xia) != nil
        if let raw = defaults.string(forKey: StoreKey.stage),
           let saved = NIODatingStage(rawValue: raw) {
            stage = saved
        }
        snapshot = loadSnapshot()
        let vault = loadCompositeVault()
        hasMikanRated = vault?.mikan != nil
        hasXiaRated = vault?.xia != nil
    }

    /// 切换关系阶段：两套维度体系不同，切换会清空双方评分（密码保留）
    func applyStage(_ newStage: NIODatingStage) {
        guard newStage != stage else { return }
        for member in NIODatingMember.allCases {
            defaults.removeObject(forKey: StoreKey.sealedScores(member))
        }
        defaults.removeObject(forKey: StoreKey.compositeVault)
        defaults.removeObject(forKey: StoreKey.snapshot)
        snapshot = nil
        hasMikanRated = false
        hasXiaRated = false
        lastSubmitOutcome = nil
        stage = newStage
        defaults.set(newStage.rawValue, forKey: StoreKey.stage)
    }

    // MARK: 常驻入口标记（触发彩蛋后设置页显示入口）

    /// UserDefaults 键：恋爱实验室是否已被发现（设置页常驻入口的开关）
    static let discoveredKey = "nio_dating_lab_discovered"

    /// 触发彩蛋（关于页点击兔子头像）后调用：设置页将出现常驻入口
    static func markDiscovered() {
        UserDefaults.standard.set(true, forKey: discoveredKey)
    }

    // MARK: 密码设置（引导期）

    /// 为成员设置 6 位密码（写入验证器；一人仅可设置一次，重置实验室后才可重来）
    func configurePassword(for member: NIODatingMember, code: String) -> Bool {
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else { return false }
        guard loadVerifier(for: member) == nil else { return false }

        let stretchSalt = NIODatingCrypto.randomBytes(16)
        let checkSalt = NIODatingCrypto.randomBytes(16)
        let stretched = NIODatingCrypto.stretch(password: code, salt: stretchSalt)
        let digest = NIODatingCrypto.checkDigest(stretched: stretched, checkSalt: checkSalt)

        let verifier = NIODatingPasswordVerifier(stretchSalt: stretchSalt, checkSalt: checkSalt, digest: digest)
        guard let data = try? JSONEncoder().encode(verifier) else { return false }
        defaults.set(data, forKey: StoreKey.verifier(member))
        clearFailures(for: member)
        isConfigured = loadVerifier(for: .mikan) != nil && loadVerifier(for: .xia) != nil
        return true
    }

    // MARK: 密码验证（带防暴力冷却）

    /// 当前成员剩余锁定秒数（0 = 未锁定）
    func lockoutRemaining(for member: NIODatingMember) -> TimeInterval {
        let until = defaults.double(forKey: StoreKey.lockUntil(member))
        let remaining = until - Date().timeIntervalSince1970
        return max(0, remaining)
    }

    /// 冷却阶梯：3 次 → 30 秒；5 次 → 2 分钟；8 次 → 10 分钟；12 次 → 1 小时
    private static let lockoutSchedule: [(fails: Int, seconds: TimeInterval)] = [
        (3, 30), (5, 120), (8, 600), (12, 3600)
    ]

    func verifyPassword(_ code: String, for member: NIODatingMember, registerFailure: Bool) -> Bool {
        guard let verifier = loadVerifier(for: member) else { return false }

        let stretched = NIODatingCrypto.stretch(password: code, salt: verifier.stretchSalt)
        let digest = NIODatingCrypto.checkDigest(stretched: stretched, checkSalt: verifier.checkSalt)
        let ok = digest == verifier.digest

        if ok {
            clearFailures(for: member)
        } else if registerFailure {
            let key = StoreKey.failedCount(member)
            let fails = defaults.integer(forKey: key) + 1
            defaults.set(fails, forKey: key)
            if let rule = Self.lockoutSchedule.last(where: { fails >= $0.fails }) {
                let until = Date().timeIntervalSince1970 + rule.seconds
                defaults.set(until, forKey: StoreKey.lockUntil(member))
            }
        }
        return ok
    }

    private func clearFailures(for member: NIODatingMember) {
        defaults.removeObject(forKey: StoreKey.failedCount(member))
        defaults.removeObject(forKey: StoreKey.lockUntil(member))
    }

    // MARK: 个人评分读取（密码解封）

    /// 用密码解封本人上次的评分（含留言）。密码错误或无记录返回 nil。
    func loadScores(for member: NIODatingMember, code: String) -> NIODatingScores? {
        guard let verifier = loadVerifier(for: member) else { return nil }
        let key = NIODatingCrypto.stretch(password: code, salt: verifier.stretchSalt)
        guard let sealedBase64 = defaults.string(forKey: StoreKey.sealedScores(member)),
              let sealed = Data(base64Encoded: sealedBase64),
              let plain = NIODatingCrypto.open(sealed: sealed, using: key) else { return nil }
        return try? JSONDecoder().decode(NIODatingScores.self, from: plain)
    }

    // MARK: 提交评分（解封 → 重新密封 → 聚合 → 快照）

    func submit(scores: NIODatingScores, for member: NIODatingMember, code: String) -> NIODatingSubmitOutcome {
        // 0. 冷却检查
        let remaining = lockoutRemaining(for: member)
        if remaining > 0 {
            let outcome = NIODatingSubmitOutcome.locked(remainingSeconds: remaining)
            lastSubmitOutcome = outcome
            return outcome
        }

        // 1. 密码验证（失败计数）
        guard verifyPassword(code, for: member, registerFailure: true) else {
            let outcome = NIODatingSubmitOutcome.wrongPassword
            lastSubmitOutcome = outcome
            return outcome
        }

        // 2. NaturalLanguage 端内实时情感演算
        let sentiment = NIODatingSentiment.score(of: scores.note) ?? 0

        // 3. EMA 纵向平滑：本轮占 60%、历史占 40%，降低单次情绪噪声
        //    （个人密封区仍保存本轮原始分，聚合金库只存平滑后的聚合摘要）
        let currentStage = stage
        let previousSummary = loadCompositeVault()?.side(for: member)
        var smoothedMeans: [String: Double] = [:]
        for dim in NIODatingPsychology.dimensions(for: currentStage) {
            let newValue = scores.value(forKey: dim.key)
            if let oldValue = previousSummary?.means[dim.key] {
                smoothedMeans[dim.key] = NIODatingEngine.emaSmoothed(previous: oldValue, new: newValue)
            } else {
                smoothedMeans[dim.key] = newValue
            }
        }

        // 4. 有效分 = 平滑后维度分的加权均分 + 本轮情绪加成（±6 封顶）
        var weightedTotal = 0.0
        for dim in NIODatingPsychology.dimensions(for: currentStage) {
            weightedTotal += (smoothedMeans[dim.key] ?? 0) * dim.weight
        }
        let effective = min(100, max(0, weightedTotal + sentiment * 6.0))

        // 5. 密封个人原始评分（AES-256-GCM，密码派生密钥）
        guard let verifier = loadVerifier(for: member) else {
            lastSubmitOutcome = .storageFailure
            return .storageFailure
        }
        let key = NIODatingCrypto.stretch(password: code, salt: verifier.stretchSalt)
        guard let plain = try? JSONEncoder().encode(scores),
              let sealed = NIODatingCrypto.seal(plain, using: key) else {
            lastSubmitOutcome = .storageFailure
            return .storageFailure
        }
        defaults.set(sealed.base64EncodedString(), forKey: StoreKey.sealedScores(member))

        // 6. 更新聚合金库（设备密钥密封；仅存平滑聚合摘要，永不展示个人原始分）
        var compositeVault = loadCompositeVault() ?? NIODatingCompositeVault()
        let summary = NIODatingSideSummary(
            means: smoothedMeans,
            effective: effective,
            sentiment: sentiment,
            chapters: previousSummary.map { $0.chapters + 1 } ?? 1,
            lastUpdate: Date(),
            rounds: (previousSummary?.rounds ?? 0) + 1
        )
        compositeVault.setSide(summary, for: member)
        guard saveCompositeVault(compositeVault) else {
            lastSubmitOutcome = .storageFailure
            return .storageFailure
        }

        // 7. 重算聚合快照（仅双方均完成首轮评分后生成）
        rebuildSnapshot(from: compositeVault)

        let chapterTitle = NIODatingChapters.title(forChapter: summary.chapters)
        // EMA 语义透明化：展示有效分较上一轮的变化量（首轮无对比基准）
        let deltaFromPrevious = previousSummary.map { effective - $0.effective }
        let outcome = NIODatingSubmitOutcome.success(chapterTitle: chapterTitle, deltaFromPrevious: deltaFromPrevious)
        lastSubmitOutcome = outcome
        return outcome
    }

    /// 依据聚合金库重算快照（聚合口径，无个人明细泄露）
    private func rebuildSnapshot(from compositeVault: NIODatingCompositeVault) {
        guard let mikan = compositeVault.mikan, let xia = compositeVault.xia else {
            snapshot = nil
            hasMikanRated = compositeVault.mikan != nil
            hasXiaRated = compositeVault.xia != nil
            if snapshot == nil { defaults.removeObject(forKey: StoreKey.snapshot) }
            return
        }

        let overall = NIODatingEngine.compositeOverall(mikanEffective: mikan.effective, xiaEffective: xia.effective)
        let harmony = NIODatingEngine.harmony(mikanMeans: mikan.means, xiaMeans: xia.means)

        // 聚合维度均分（仅用于类型判定与分级展示，按当前关系阶段的维度体系）
        let currentStage = stage
        var compositeMeans: [String: Double] = [:]
        var bands: [String: Int] = [:]
        var weakestKey: String?
        var weakestValue = 101.0
        for dim in NIODatingPsychology.dimensions(for: currentStage) {
            let m = mikan.means[dim.key] ?? 0
            let x = xia.means[dim.key] ?? 0
            let mean = (m + x) / 2
            compositeMeans[dim.key] = mean
            bands[dim.key] = NIODatingEngine.band(for: mean)
            if mean < weakestValue {
                weakestValue = mean
                weakestKey = dim.key
            }
        }

        // 深度关系期做 Sternberg 类型判定；初识心动期 loveTypeKey 仅存占位（UI 用火花等级）
        let loveType = NIODatingEngine.classifyLoveType(compositeMeans: compositeMeans)
        let rank = NIODatingEngine.rank(for: overall)
        let balance = NIODatingEngine.balanceScore(compositeMeans: compositeMeans)

        let newSnapshot = NIODatingCompositeSnapshot(
            overall: overall,
            dimensionBands: bands,
            harmony: harmony,
            loveTypeKey: loveType.key,
            rankKey: rank.key,
            combinedChapters: mikan.chapters + xia.chapters,
            advice: NIODatingEngine.advice(stage: currentStage, weakestDimensionKey: weakestKey, harmony: harmony, balance: balance),
            mikanLastUpdate: mikan.lastUpdate,
            xiaLastUpdate: xia.lastUpdate,
            generatedAt: Date(),
            balance: balance,
            mikanRounds: mikan.rounds,
            xiaRounds: xia.rounds,
            stageKey: currentStage.rawValue
        )

        snapshot = newSnapshot
        hasMikanRated = true
        hasXiaRated = true

        if let data = try? JSONEncoder().encode(newSnapshot) {
            defaults.set(data, forKey: StoreKey.snapshot)
        }
    }

    // MARK: 重置

    /// 销毁实验室全部数据（密码、评分、留言、聚合快照）
    func resetAll() {
        for member in NIODatingMember.allCases {
            defaults.removeObject(forKey: StoreKey.verifier(member))
            defaults.removeObject(forKey: StoreKey.sealedScores(member))
            clearFailures(for: member)
        }
        defaults.removeObject(forKey: StoreKey.compositeVault)
        defaults.removeObject(forKey: StoreKey.snapshot)
        defaults.removeObject(forKey: StoreKey.stage)
        snapshot = nil
        hasMikanRated = false
        hasXiaRated = false
        isConfigured = false
        stage = .firstSpark
        lastSubmitOutcome = nil
    }

    // MARK: - 私有读写

    private func loadVerifier(for member: NIODatingMember) -> NIODatingPasswordVerifier? {
        guard let data = defaults.data(forKey: StoreKey.verifier(member)) else { return nil }
        return try? JSONDecoder().decode(NIODatingPasswordVerifier.self, from: data)
    }

    private func loadCompositeVault() -> NIODatingCompositeVault? {
        guard let base64 = defaults.string(forKey: StoreKey.compositeVault),
              let sealed = Data(base64Encoded: base64) else { return nil }
        guard let deviceKey = NIODatingKeychain.loadOrCreateDeviceKey() else { return nil }
        guard let plain = NIODatingCrypto.open(sealed: sealed, using: deviceKey) else { return nil }
        return try? JSONDecoder().decode(NIODatingCompositeVault.self, from: plain)
    }

    private func saveCompositeVault(_ vault: NIODatingCompositeVault) -> Bool {
        guard let deviceKey = NIODatingKeychain.loadOrCreateDeviceKey() else { return false }
        guard let plain = try? JSONEncoder().encode(vault) else { return false }
        guard let sealed = NIODatingCrypto.seal(plain, using: deviceKey) else { return false }
        defaults.set(sealed.base64EncodedString(), forKey: StoreKey.compositeVault)
        return true
    }

    private func loadSnapshot() -> NIODatingCompositeSnapshot? {
        guard let data = defaults.data(forKey: StoreKey.snapshot) else { return nil }
        return try? JSONDecoder().decode(NIODatingCompositeSnapshot.self, from: data)
    }
}

// MARK: - 密码学原语

enum NIODatingCrypto {

    /// 密码拉伸：盐值 + 2 万轮 SHA256 迭代，拖慢 6 位数字密码的离线穷举
    static func stretch(password: String, salt: Data, rounds: Int = 20_000) -> SymmetricKey {
        var digest = SHA256.hash(data: salt + Data(password.utf8))
        for _ in 0..<rounds {
            digest = SHA256.hash(data: salt + Data(digest))
        }
        return SymmetricKey(data: Data(digest))
    }

    /// 验证摘要（与拉伸密钥独立加盐，避免验证器本身泄露密钥可用性）
    static func checkDigest(stretched: SymmetricKey, checkSalt: Data) -> Data {
        let raw = stretched.withUnsafeBytes { Data($0) }
        return Data(SHA256.hash(data: checkSalt + raw))
    }

    /// AES-256-GCM 密封（认证加密，防篡改）
    static func seal(_ plaintext: Data, using key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.seal(plaintext, using: key) else { return nil }
        return box.combined
    }

    /// AES-256-GCM 解封（密钥错误 / 密文被篡改返回 nil）
    static func open(sealed: Data, using key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = bytes.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        return Data(bytes)
    }
}

// MARK: - Keychain 设备密钥

enum NIODatingKeychain {

    private static let service = "com.yumikotoys.rr.datinglab"
    private static let account = "device-key"

    /// 读取或首次生成 32 字节随机设备密钥（存 Keychain，随设备走，永不导出）
    static func loadOrCreateDeviceKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }

        // 首次生成
        let fresh = NIODatingCrypto.randomBytes(32)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: fresh,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { return nil }
        return SymmetricKey(data: fresh)
    }
}
