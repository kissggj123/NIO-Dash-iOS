//
//  NIODatingModels.swift
//  wheater
//
//  恋爱好感度实验室 · 心理学模型层
//  理论基础：Sternberg 爱情三角理论 / Gottman 关系研究 / 依恋理论 / 回应性模型
//

import Foundation

// MARK: - 成员

/// 实验室成员（蜜柑 🍊 与 夏老师 🫧）
enum NIODatingMember: String, Codable, CaseIterable, Identifiable {
    case mikan
    case xia

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .mikan: return "🍊"
        case .xia: return "🫧"
        }
    }

    var displayName: String {
        switch self {
        case .mikan: return "蜜柑"
        case .xia: return "夏老师"
        }
    }

    var fullTitle: String { "\(emoji) \(displayName)" }

    /// 对方成员
    var counterpart: NIODatingMember { self == .mikan ? .xia : .mikan }
}

// MARK: - 关系阶段

/// 关系阶段：初识心动期（刚认识/暧昧初期）与深度关系期（稳定交往）采用两套独立维度与权重体系
enum NIODatingStage: String, Codable, CaseIterable, Identifiable {
    /// 初识心动期：适用第一次见面 / 暧昧初期（维度取自人际吸引与初次互动研究）
    case firstSpark
    /// 深度关系期：适用稳定交往中的伴侣（Sternberg 三角 + Gottman + 依恋体系）
    case deepBond

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstSpark: return "初识心动期"
        case .deepBond: return "深度关系期"
        }
    }

    var subtitle: String {
        switch self {
        case .firstSpark: return "刚认识 / 暧昧初期 · 人际吸引研究维度"
        case .deepBond: return "稳定交往伴侣 · Sternberg + Gottman 维度"
        }
    }

    /// 旧快照无阶段字段时按深度关系期处理（兼容 v1 数据）
    static func from(key: String?) -> NIODatingStage {
        NIODatingStage(rawValue: key ?? "") ?? .deepBond
    }
}

// MARK: - 评分维度（心理学理论映射）

struct NIODatingDimension: Identifiable {
    let key: String
    let icon: String
    let nameCN: String
    let nameEN: String
    /// 评分时引导思考的问题
    let question: String
    /// 心理学依据（可展开查看）
    let citation: String
    /// 权重：承诺与沟通最高（长期关系满意度最强预测因子），激情最低（自然衰减）
    let weight: Double
    /// 权重设置理由（评分表实时展示，说明该维度在综合计算中的作用）
    let weightRationale: String

    var id: String { key }
}

enum NIODatingPsychology {

    /// 按关系阶段返回对应维度集（两套体系独立设计与加权）
    static func dimensions(for stage: NIODatingStage) -> [NIODatingDimension] {
        stage == .firstSpark ? firstSparkDimensions : deepBondDimensions
    }

    /// 深度关系期六维：三维度来自 Sternberg 爱情三角，三维度来自 Gottman / 依恋 / 回应性研究
    static let deepBondDimensions: [NIODatingDimension] = [
        NIODatingDimension(
            key: "intimacy",
            icon: "💞",
            nameCN: "亲密",
            nameEN: "Intimacy",
            question: "你们能安心分享彼此最隐秘的想法与脆弱吗？",
            citation: "Sternberg (1986) 爱情三角理论：亲密指心灵贴近、彼此理解与支持的程度，是信任与自我表露的积累。",
            weight: 0.20,
            weightRationale: "亲密是沟通与回应性的上游能力（自我表露深度是亲密感最强可操作指标）"
        ),
        NIODatingDimension(
            key: "passion",
            icon: "🌹",
            nameCN: "激情",
            nameEN: "Passion",
            question: "想到 TA 时，心跳还会不自觉加速吗？",
            citation: "Sternberg (1986)：激情是爱与欲的驱力。研究显示激情会随时间自然衰减，需要主动经营。",
            weight: 0.15,
            weightRationale: "激情存在公认的自然衰减曲线，与承诺同权会系统性低估长期关系质量（Aron & Aron, 1986）"
        ),
        NIODatingDimension(
            key: "commitment",
            icon: "⚓️",
            nameCN: "承诺",
            nameEN: "Commitment",
            question: "愿意为这段关系的长期未来持续投入吗？",
            citation: "Rusbult (1983) 投资模型：承诺由满意度、投资规模与替代选择共同决定，是关系稳定的核心预测指标。",
            weight: 0.20,
            weightRationale: "承诺是关系存续与维持行为的核心预测因子（Rusbult 投资模型，1983）"
        ),
        NIODatingDimension(
            key: "communication",
            icon: "💬",
            nameCN: "沟通",
            nameEN: "Communication",
            question: "出现分歧时，你们依然能好好说话吗？",
            citation: "Gottman & Silver (1999)：沟通方式（尤其冲突时的「软启动」）是婚姻幸福最强预测因子之一。",
            weight: 0.20,
            weightRationale: "冲突时的沟通方式是婚姻质量最强的行为预测因子（Gottman 纵向研究，1994）"
        ),
        NIODatingDimension(
            key: "security",
            icon: "🛟",
            nameCN: "安全感",
            nameEN: "Security",
            question: "在 TA 身边，你能放心地做自己吗？",
            citation: "Bowlby (1969) / Hazan & Shaver (1987) 依恋理论：伴侣是成年人的「安全基地」，稳定回应塑造安全型依恋。",
            weight: 0.15,
            weightRationale: "安全基地可用性塑造关系满意度，但效应已部分体现在亲密与沟通中（Hazan & Shaver, 1987）"
        ),
        NIODatingDimension(
            key: "responsiveness",
            icon: "🎯",
            nameCN: "回应性",
            nameEN: "Responsiveness",
            question: "TA 能及时接住你的情绪信号，并给出回应吗？",
            citation: "Reis & Shaver (1988) 回应性模型 / Gottman「情感邀请」：日常微小时刻的回应质量决定情感账户余额。",
            weight: 0.10,
            weightRationale: "日常微观回应持续累积联结，但其效应与亲密、安全感高度重叠（Reis & Shaver, 1988）"
        )
    ]

    static func dimension(forKey key: String) -> NIODatingDimension? {
        deepBondDimensions.first { $0.key == key } ?? firstSparkDimensions.first { $0.key == key }
    }

    /// 初识心动期六维：维度取自人际吸引与初次互动研究（第一次见面 / 暧昧初期适用）
    /// 权重设计：初识阶段各信号相对独立（尚未形成关系结构），权重趋平；心动吸引与畅聊感略高
    static let firstSparkDimensions: [NIODatingDimension] = [
        NIODatingDimension(
            key: "attraction",
            icon: "💫",
            nameCN: "心动吸引",
            nameEN: "Attraction",
            question: "见到 TA 的第一眼，心跳有没有不自觉加速？",
            citation: "Aron et al. (1997) 亲近感生成实验：外表与气质吸引是关系启动的第一信号，但存在光环效应，需与其他信号交叉验证。",
            weight: 0.20,
            weightRationale: "初识期最强信号，但光环效应会放大它，故不独大（Aron, 1997）"
        ),
        NIODatingDimension(
            key: "flow",
            icon: "🗣",
            nameCN: "畅聊感",
            nameEN: "Conversation Flow",
            question: "和 TA 聊天的时候，时间是不是过得特别快？",
            citation: "Aron et al. (1997)《人际亲近感的实验生成》：渐进式自我表露（36 问）是亲近感最可靠的生成器，对话流畅度是它的外在表现。",
            weight: 0.20,
            weightRationale: "对话流畅度是渐进式自我表露成功的外在标志（Aron, 1997）"
        ),
        NIODatingDimension(
            key: "similarity",
            icon: "🌱",
            nameCN: "相似共鸣",
            nameEN: "Similarity",
            question: "兴趣、笑点、价值观，有没有意外地同频？",
            citation: "Byrne (1971) 相似-吸引效应：态度与偏好的相似性是人际吸引最稳定的预测因子之一，尤其体现在价值观与幽默感上。",
            weight: 0.15,
            weightRationale: "相似性是长期吸引的稳定预测因子，但初识期样本量小，需更多场景验证（Byrne, 1971）"
        ),
        NIODatingDimension(
            key: "comfort",
            icon: "🛟",
            nameCN: "舒适边界",
            nameEN: "Comfort",
            question: "在 TA 身边能放松做自己，没有压力和紧绷感吗？",
            citation: "初识期研究：无压力的相处体验（边界被尊重、不刻意讨好）是判断关系是否值得继续的最珍贵早期信号。",
            weight: 0.15,
            weightRationale: "舒适感是初识期最珍贵也最诚实的信号——勉强感几乎无法长期伪装"
        ),
        NIODatingDimension(
            key: "responsiveness",
            icon: "🎯",
            nameCN: "回应性",
            nameEN: "Responsiveness",
            question: "你抛出的话题和梗，TA 都接得住吗？",
            citation: "Reis & Shaver (1988) 回应性模型：初识互动中的「表达—理解—回应」循环，是未来亲密感最早期的预演。",
            weight: 0.15,
            weightRationale: "微观回应是亲密循环的最早预演，但对初识关系尚缺累积效应（Reis & Shaver, 1988）"
        ),
        NIODatingDimension(
            key: "continuation",
            icon: "🔮",
            nameCN: "再见意愿",
            nameEN: "Continuation Interest",
            question: "分开之后，心里已经开始期待下一次见面了吗？",
            citation: "关系启动研究：再接触意愿是关系能否发展的最强前置预测指标——没有「想再见」，一切后续维度都无从展开。",
            weight: 0.15,
            weightRationale: "再接触意愿是关系发展的最强前置预测，但初识期的意愿波动大，故不独大"
        )
    ]

    /// 心理学小贴士库（每次随机展示一条）
    static let tips: [String] = [
        "戈特曼对数千对伴侣的观察研究发现：稳定幸福的关系中，积极互动与消极互动比约为 5:1 —— 今天先给 TA 五句夸奖，再提一个小建议吧 (Gottman, 1994)。",
        "非暴力沟通四步法：观察 → 感受 → 需要 → 请求。以「我」开头表达需求，而不是以「你」开头指责 (Rosenberg, 2003)。",
        "爱的五种语言：肯定的话语、精心时刻、接收礼物、服务行动、身体接触。弄清对方的主导爱语，付出才不会错频道 (Chapman, 1992)。",
        "自我扩张模型：一起尝试新鲜、有挑战的共同经历，能显著提升关系满意度与激情 (Aron & Aron, 1986)。",
        "依恋研究：伴侣的稳定回应就是最好的「安全基地」。当 TA 倾诉时，先回应情绪，再解决问题 (Bowlby, 1969)。",
        "Gottman「情感邀请」(bids)：TA 随口的一句分享、一个眼神都是情感邀请。「转向」而非「转离」，是关系存续的关键。",
        "积极错觉研究：对伴侣保持适度理想化的人，关系满意度和持久度反而更高 (Murray et al., 1996)。",
        "感激是关系的助推器：具体地说出感谢的原因（而不是一句笼统的谢谢），能显著加深联结 (Algoe, 2012)。",
        "戈特曼「软启动」：开启困难话题时以温和描述开场，前 3 分钟的基调往往决定整场对话的走向。",
        "「二十秒规则」：每天给对方一个 20 秒以上的真诚拥抱，催产素会替你巩固依恋联结。"
    ]
}

// MARK: - 章节标题（恋爱小说感）

enum NIODatingChapters {
    static let titles: [String] = [
        "初遇的信号", "心动的频率", "并肩的温差", "月色的注脚",
        "悄悄的靠近", "温柔的证词", "星轨的交汇", "灯火的同谋",
        "心跳的伏笔", "时间的礼物", "晴天的约定", "梦境的边检",
        "口袋里的糖", "雨伞的半径", "名字的重量"
    ]

    /// 第 N 章 → 标题（循环取用）
    static func title(forChapter chapter: Int) -> String {
        guard chapter >= 1, !titles.isEmpty else { return "序章" }
        let index = (chapter - 1) % titles.count
        return titles[index]
    }
}

// MARK: - 心动火花等级（初识心动期）

struct NIODatingSparkLevel: Identifiable {
    let key: String
    let emoji: String
    let title: String
    let summary: String
    let citation: String

    var id: String { key }
}

// MARK: - 评分数据

/// 一次评分记录（0-100 分制，仅密码持有者本人可见明文）
/// values 以维度 key 存储，兼容初识心动期与深度关系期两套维度体系
struct NIODatingScores: Codable, Equatable {
    var values: [String: Double] = [:]
    /// 心动留言（仅本人与心理引擎可见，对方永远看不到原文）
    var note: String = ""
    /// 章节序号（第几次提交）
    var chapter: Int = 1
    var updatedAt: Date = Date()

    func value(forKey key: String, default defaultValue: Double = 60) -> Double {
        values[key] ?? defaultValue
    }

    mutating func setValue(_ value: Double, forKey key: String) {
        values[key] = value
    }

    var means: [String: Double] { values }
}

// MARK: - 爱情类型（Sternberg 七类型）

struct NIODatingLoveType: Identifiable {
    let key: String
    let emoji: String
    let title: String
    let summary: String
    let citation: String

    var id: String { key }

    /// 判定阈值：维度均分 ≥ 65 视为该成分「显著」
    static let threshold: Double = 65
}

// MARK: - 相性评级

struct NIODatingRank: Identifiable {
    let key: String
    let emoji: String
    let title: String
    /// 是否合适的一句话判定
    let verdict: String

    var id: String { key }
}

// MARK: - 综合快照（仅聚合信息，双方可见）

struct NIODatingCompositeSnapshot: Codable, Equatable {
    /// 综合好感度 0-100（双方有效分的均值）
    var overall: Double
    /// 各维度聚合分级（0-3 档，量化后无法反推个人原始分）
    var dimensionBands: [String: Int]
    /// 默契指数 0-100（双方各维度评分的接近程度）
    var harmony: Double
    /// Sternberg 爱情类型 key
    var loveTypeKey: String
    /// 相性评级 key
    var rankKey: String
    /// 双方累计章节数
    var combinedChapters: Int
    /// 定制建议（基于最弱维度生成）
    var advice: String
    var mikanLastUpdate: Date?
    var xiaLastUpdate: Date?
    var generatedAt: Date
    /// 六维均衡度 0-100（2026-11-14 新增，旧快照无此字段）
    var balance: Double?
    /// 蜜柑累计评分轮次（用于稳定度判定）
    var mikanRounds: Int?
    /// 夏老师累计评分轮次
    var xiaRounds: Int?

    var loveType: NIODatingLoveType { NIODatingEngine.loveType(forKey: loveTypeKey) }
    var rank: NIODatingRank { NIODatingEngine.rank(forKey: rankKey) }

    /// 关系阶段（2026-11-14 新增：初识心动期 / 深度关系期；旧快照无此字段按深度关系期处理）
    var stageKey: String?
    var stage: NIODatingStage { NIODatingStage.from(key: stageKey) }
    /// 初识心动期的火花等级（深度关系期为 nil，使用爱情类型）
    var sparkLevel: NIODatingSparkLevel? {
        stage == .firstSpark ? NIODatingEngine.sparkLevel(for: overall) : nil
    }

    /// 双方轮次合计（稳定度评估用）
    var combinedRounds: Int { (mikanRounds ?? 0) + (xiaRounds ?? 0) }
}

// MARK: - 评分引擎（纯函数）

enum NIODatingEngine {

    /// 指数移动平均（EMA）平滑：多轮评分纵向聚合，α=0.6 让本轮占主导、历史做缓冲，
    /// 降低单次情绪噪声对聚合结果的冲击（纵向追踪优于单次横断的方法学原则）
    static func emaSmoothed(previous: Double, new: Double, alpha: Double = 0.6) -> Double {
        previous + alpha * (new - previous)
    }

    /// 依据六维聚合均分计算均衡度：100 − 2.2 × 维度总体标准差（按所有维度值直接计算，阶段无关）
    /// 维度间显著失衡（如激情远高于沟通）提示结构性风险，补短板比拔峰值更有效
    static func balanceScore(compositeMeans: [String: Double]) -> Double {
        let values = Array(compositeMeans.values)
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let sigma = variance.squareRoot()
        return max(0, min(100, 100 - sigma * 2.2))
    }

    /// 评分表实时分段解读（0-100 原始分 → 分区描述）
    static func scoreBandInterpretation(for value: Double) -> (label: String, description: String) {
        switch value {
        case 90...: return ("优秀区", "超过绝大多数伴侣的典型水平")
        case 75..<90: return ("良好区", "高于伴侣样本的常见水平")
        case 60..<75: return ("稳定区", "处于伴侣平均水平的常态区间")
        case 45..<60: return ("待培育区", "略低于常见水平，值得留意")
        default: return ("关注区", "显著低于典型水平，建议温柔沟通")
        }
    }

    /// 结果稳定度：轮次越多，EMA 平滑后的结论越可信
    static func stabilityLevel(combinedRounds: Int) -> (label: String, description: String) {
        switch combinedRounds {
        case ..<2: return ("初测期", "单轮评分噪声较大，结论仅供参考")
        case 2...3: return ("校准中", "趋势正在形成，多评几轮更可信")
        case 4...7: return ("稳定追踪", "多轮平滑生效，结论趋于稳定")
        default: return ("高信度追踪", "长期纵向数据支撑，结论可信度高")
        }
    }

    /// 加权均分：按关系阶段取维度集与权重（深度期承诺/沟通优先，初识期各信号趋平）
    static func weightedMean(of scores: NIODatingScores, stage: NIODatingStage) -> Double {
        var total = 0.0
        var weightSum = 0.0
        for dim in NIODatingPsychology.dimensions(for: stage) {
            total += scores.value(forKey: dim.key) * dim.weight
            weightSum += dim.weight
        }
        guard weightSum > 0 else { return 0 }
        return total / weightSum
    }

    /// 有效分 = 加权均分 + 留言情绪加成（±6 分封顶）
    static func effectiveScore(of scores: NIODatingScores, sentiment: Double?, stage: NIODatingStage) -> Double {
        let base = weightedMean(of: scores, stage: stage)
        let boost = (sentiment ?? 0) * 6.0
        return min(100, max(0, base + boost))
    }

    /// 综合分 = 双方有效分的均值
    static func compositeOverall(mikanEffective: Double, xiaEffective: Double) -> Double {
        (mikanEffective + xiaEffective) / 2
    }

    /// 默契指数：双方各维度评分的平均接近程度（按共有维度键计算，阶段无关）
    static func harmony(mikanMeans: [String: Double], xiaMeans: [String: Double]) -> Double {
        var diffs: [Double] = []
        for (key, mikanValue) in mikanMeans {
            guard let xiaValue = xiaMeans[key] else { continue }
            diffs.append(abs(mikanValue - xiaValue))
        }
        guard !diffs.isEmpty else { return 0 }
        let meanDiff = diffs.reduce(0, +) / Double(diffs.count)
        return max(0, 100 - meanDiff)
    }

    /// 维度聚合分级（0=待培育 1=稳定 2=良好 3=极佳）
    /// 分级量化展示：即使知道自己的原始分，也只能把对方分数反推到一个区间
    static func band(for value: Double) -> Int {
        switch value {
        case 90...: return 3
        case 75..<90: return 2
        case 60..<75: return 1
        default: return 0
        }
    }

    static let bandLabels = ["待培育", "稳定", "良好", "极佳"]
    static let bandIcons = ["🌱", "🌿", "🌸", "✨"]

    // MARK: 心动火花等级（初识心动期专用）

    static let sparkLevels: [NIODatingSparkLevel] = [
        NIODatingSparkLevel(
            key: "fireworks", emoji: "🎆",
            title: "烟花级心动",
            summary: "罕见的强火花 —— 吸引、畅聊与想再见同时拉满。别犹豫，尽快约下一次。",
            citation: "关系启动研究：初识期三大信号（吸引 / 表露 / 再见意愿）同时高企时，关系发展概率最高。"
        ),
        NIODatingSparkLevel(
            key: "strongSpark", emoji: "✨",
            title: "强火花",
            summary: "好感信号强烈且清晰 —— 非常值得再约下一次，让火花有燃烧的机会。",
            citation: "再接触意愿是关系发展最强前置预测指标；强火花若不及时跟进会自然冷却。"
        ),
        NIODatingSparkLevel(
            key: "clearSpark", emoji: "💥",
            title: "明显火花",
            summary: "心动清晰可辨 —— 多创造相处机会，在更多场景里验证这份好感。",
            citation: "Byrne (1971)：相似性需要更多共同场景才能被充分验证。"
        ),
        NIODatingSparkLevel(
            key: "smallFlame", emoji: "🕯",
            title: "小火苗",
            summary: "有苗头但尚不稳定 —— 初识期的波动很正常，再观察几次再下判断。",
            citation: "首因效应存在光环放大，单次印象的置信度有限，需要重复验证。"
        ),
        NIODatingSparkLevel(
            key: "dimLight", emoji: "🌫",
            title: "微光",
            summary: "目前更接近普通朋友区 —— 不必强求，也不必急着下结论。",
            citation: "吸引研究：友谊区与心动区的边界并非不可跨越，但强扭的火花不可靠。"
        ),
        NIODatingSparkLevel(
            key: "noSpark", emoji: "💧",
            title: "火花未燃",
            summary: "顺其自然，不必勉强 —— 好的关系从来不是硬凑出来的。",
            citation: "相互喜欢 (reciprocity of liking) 研究的推论：单方面的火花难以持久。"
        )
    ]

    /// 初识心动期：综合分映射心动火花等级
    static func sparkLevel(for overall: Double) -> NIODatingSparkLevel {
        switch overall {
        case 90...: return sparkLevels[0]
        case 80..<90: return sparkLevels[1]
        case 70..<80: return sparkLevels[2]
        case 60..<70: return sparkLevels[3]
        case 50..<60: return sparkLevels[4]
        default: return sparkLevels[5]
        }
    }

    // MARK: 爱情类型判定

    static let loveTypes: [NIODatingLoveType] = [
        NIODatingLoveType(
            key: "consummate", emoji: "💫",
            title: "完美之爱",
            summary: "亲密、激情与承诺三要素齐备，Sternberg 理论中最完整的爱。请继续用心浇灌。",
            citation: "Sternberg (1986)：三成分俱高时构成完美之爱 (Consummate Love)，需要持续行动维持。"
        ),
        NIODatingLoveType(
            key: "romantic", emoji: "🌹",
            title: "浪漫之爱",
            summary: "亲密与激情俱高，感情炽热而贴近。下一步是让承诺跟上心动的节奏。",
            citation: "Sternberg (1986)：亲密+激情（缺承诺）构成浪漫之爱 (Romantic Love)。"
        ),
        NIODatingLoveType(
            key: "companionate", emoji: "🏠",
            title: "伴侣之爱",
            summary: "深情且稳定，像最信任的战友。偶尔制造新鲜感，能让火花重新点燃。",
            citation: "Sternberg (1986)：亲密+承诺（激情较低）构成伴侣之爱 (Companionate Love)，常见于长期关系。"
        ),
        NIODatingLoveType(
            key: "fatuous", emoji: "🎡",
            title: "炽热之爱",
            summary: "激情与承诺都很高，但深层的了解还需要时间。多创造深度对话的机会。",
            citation: "Sternberg (1986)：激情+承诺（缺亲密）构成愚昧之爱 (Fatuous Love)，如闪婚式恋情。"
        ),
        NIODatingLoveType(
            key: "liking", emoji: "🫂",
            title: "知己之爱",
            summary: "深厚的理解与亲近，但心动信号偏弱。诚实面对：是爱，还是最好的朋友？",
            citation: "Sternberg (1986)：仅亲密显著构成喜欢 (Liking)，即亲密友谊式的情感。"
        ),
        NIODatingLoveType(
            key: "infatuated", emoji: "💥",
            title: "迷恋之爱",
            summary: "心跳很响，了解还浅。慢下来，去认识面具背后的那个真实的人。",
            citation: "Sternberg (1986)：仅激情显著构成迷恋 (Infatuation)，典型的一见钟情式状态。"
        ),
        NIODatingLoveType(
            key: "empty", emoji: "📜",
            title: "空洞之爱",
            summary: "承诺还在，温度不足。这段关系需要重新注入亲密与心动。",
            citation: "Sternberg (1986)：仅承诺显著构成空洞之爱 (Empty Love)。"
        ),
        NIODatingLoveType(
            key: "growing", emoji: "🌱",
            title: "萌芽之爱",
            summary: "各成分仍在低位生长。别急，所有的深爱都始于愿意开始。",
            citation: "Sternberg (1986)：三成分均不显著时接近无爱 (Nonlove)，但关系是动态可成长的。"
        )
    ]

    /// 依据聚合后的三维均分判定爱情类型（仅使用聚合值，不泄露个人原始分）
    static func classifyLoveType(compositeMeans: [String: Double]) -> NIODatingLoveType {
        func mean(_ key: String) -> Double { compositeMeans[key] ?? 0 }
        let intimacy = mean("intimacy") >= NIODatingLoveType.threshold
        let passion = mean("passion") >= NIODatingLoveType.threshold
        let commitment = mean("commitment") >= NIODatingLoveType.threshold

        switch (intimacy, passion, commitment) {
        case (true, true, true): return loveType(forKey: "consummate")
        case (true, true, false): return loveType(forKey: "romantic")
        case (true, false, true): return loveType(forKey: "companionate")
        case (false, true, true): return loveType(forKey: "fatuous")
        case (true, false, false): return loveType(forKey: "liking")
        case (false, true, false): return loveType(forKey: "infatuated")
        case (false, false, true): return loveType(forKey: "empty")
        default: return loveType(forKey: "growing")
        }
    }

    static func loveType(forKey key: String) -> NIODatingLoveType {
        loveTypes.first { $0.key == key } ?? loveTypes[loveTypes.count - 1]
    }

    // MARK: 相性评级

    static let ranks: [NIODatingRank] = [
        NIODatingRank(
            key: "sss", emoji: "💎",
            title: "SSS 天作之合",
            verdict: "灵魂高度同频的一对，请务必珍惜这段关系。"
        ),
        NIODatingRank(
            key: "ss", emoji: "💞",
            title: "SS 双向奔赴",
            verdict: "心动与默契兼具，非常合适的一对。"
        ),
        NIODatingRank(
            key: "s", emoji: "🌸",
            title: "S 心动进行时",
            verdict: "关系健康升温中，合适且充满潜力。"
        ),
        NIODatingRank(
            key: "a", emoji: "🌱",
            title: "A 稳步升温",
            verdict: "基础扎实，用心经营会越来越好。"
        ),
        NIODatingRank(
            key: "b", emoji: "🌾",
            title: "B 需要浇灌",
            verdict: "关系需要更多养分：多些倾听，也多些表达。"
        ),
        NIODatingRank(
            key: "c", emoji: "🫧",
            title: "C 坦诚对话期",
            verdict: "建议来一次温柔的深度沟通，把心里话说给对方。"
        )
    ]

    static func rank(for overall: Double) -> NIODatingRank {
        switch overall {
        case 90...: return ranks[0]
        case 80..<90: return ranks[1]
        case 70..<80: return ranks[2]
        case 60..<70: return ranks[3]
        case 50..<60: return ranks[4]
        default: return ranks[5]
        }
    }

    static func rank(forKey key: String) -> NIODatingRank {
        ranks.first { $0.key == key } ?? ranks[3]
    }

    // MARK: 定制建议（基于最弱聚合维度）

    static func advice(stage: NIODatingStage, weakestDimensionKey: String?, harmony: Double, balance: Double? = nil) -> String {
        var lines: [String] = []
        if let key = weakestDimensionKey, let dim = NIODatingPsychology.dimension(forKey: key) {
            let line: String
            if stage == .firstSpark {
                // 初识心动期：干预聚焦"关系启动"动作，而非长期关系维护
                switch key {
                case "attraction":
                    line = "\(dim.icon) 心动吸引偏低：第一印象的火花可以慢热 —— 不用一次印象下结论，也不必勉强自己凑火花。"
                case "flow":
                    line = "\(dim.icon) 畅聊感偏低：试试 Aron (1997) 的渐进式自我表露 —— 从轻话题到深话题分层聊，亲近感是可以被设计的。"
                case "similarity":
                    line = "\(dim.icon) 相似共鸣偏低：聊聊彼此的「热爱清单」—— 相似性需要在更多场景里验证，它重要但未必是必需品。"
                case "comfort":
                    line = "\(dim.icon) 舒适边界偏低：放慢节奏 —— 初识期最珍贵的信号是「和 TA 相处没有压力」，勉强感几乎无法长期伪装。"
                case "responsiveness":
                    line = "\(dim.icon) 回应性偏低：留意 TA 是否接得住你的话题与情绪信号 —— 这是情感邀请最早期也最诚实的形态。"
                case "continuation":
                    line = "\(dim.icon) 再见意愿偏低：诚实面对心里的答案；如果其实有，主动一次也无妨 —— 再接触意愿是关系发展的最强前置预测。"
                default:
                    line = "\(dim.icon) 初识的信号有限 —— 最重要的不是分数，而是相处时你是否感觉舒服。"
                }
            } else {
                switch key {
                case "intimacy":
                    line = "\(dim.icon) 亲密维度偏低：每周留一段只属于你们的「深度对话时间」，轮流分享最近的脆弱与梦想（自我表露是亲密感的燃料）。"
                case "passion":
                    line = "\(dim.icon) 激情维度偏低：一起做一件两人都没做过的新鲜事 —— 自我扩张模型证实，共同的新体验能重新点燃心动。"
                case "commitment":
                    line = "\(dim.icon) 承诺维度偏低：一起制定一个可实现的共同目标（旅行基金、共同技能），让「我们」的叙事不断累积。"
                case "communication":
                    line = "\(dim.icon) 沟通维度偏低：练习 Rosenberg 非暴力沟通 —— 描述观察、表达感受、说出需要、提出请求，冲突时先软启动。"
                case "security":
                    line = "\(dim.icon) 安全感维度偏低：把「稳定回应」放在第一位 —— 情绪先于方案，让 TA 知道你在（依恋理论中的安全基地）。"
                case "responsiveness":
                    line = "\(dim.icon) 回应性维度偏低：留意 Gottman 说的「情感邀请」—— TA 的每次小分享都值得你放下手机 20 秒认真接住。"
                default:
                    line = "\(dim.icon) 保持温柔与好奇，关系会在细节里生长。"
                }
            }
            lines.append(line)
        }
        if harmony < 70 {
            let harmonyLine = stage == .firstSpark
                ? "💫 你们对这次见面的感知存在温差 —— 初识期这很常见，多一次共同经历就能校准彼此的读数。"
                : "💫 默契指数不高：你们对这段关系的感知存在温差，Gottman 的「爱情地图」练习可以帮到你们 —— 轮流考考对方：最近在担心什么？最期待什么？"
            lines.append(harmonyLine)
        }
        if let balance, balance < 62 {
            lines.append("⚖️ 六维出现失衡：某一项显著拖后腿时，补短板比拔高优势更有效 —— 本期建议优先照顾最弱维度。")
        }
        if lines.isEmpty {
            lines.append(stage == .firstSpark
                         ? "💖 各信号均衡且默契在线 —— 这是个不错的开始，记得趁热打铁约下一次。"
                         : "💖 各维度均衡且默契在线。保持现在的样子，记得偶尔把感谢说出口。")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 依据文案库（看板每项数据的「📐 依据」展开内容）

enum NIODatingEvidence {

    /// 综合好感度
    static let overall = """
    计算链路：六维滑条（0-100）→ 按关系阶段加权均分 → + 留言情绪加成（±6 分封顶）→ 个人有效分 → 双方有效分均值 = 综合好感度。

    深度关系期权重（承诺/沟通/亲密 0.20 ＞ 激情/安全感 0.15 ＞ 回应性 0.10）：承诺水平与冲突沟通质量是长期关系存续最稳定的预测因子（Gottman, 1999; Rusbult, 1983）；激情存在自然衰减曲线故降权（Sternberg, 1986）。

    初识心动期权重（心动吸引/畅聊感 0.20 ＞ 相似共鸣/舒适边界/回应性/再见意愿 0.15）：初识期各信号相对独立、尚未形成关系结构，权重趋平；吸引与畅聊感略高，因为它们是关系启动的第一与第二信号（Aron, 1997; Byrne, 1971）。

    情绪加成：留言情绪由 Apple NaturalLanguage 端内情感分析模型实时演算（-1 ~ +1），×6 计入有效分。依据表达性写作研究（Pennebaker, 1997）；幅度限制在 6%，让结构性评估不被一时情绪淹没。

    纵向平滑：多轮提交时，各维度分按指数移动平均（EMA, α=0.6）平滑 —— 本轮占 60%、历史占 40%，降低单次情绪噪声。
    """

    /// 心动火花等级（初识心动期专用）
    static let firstSpark = """
    初识心动期采用「人际吸引研究」维度体系（Aron et al., 1997 亲近感生成实验；Byrne, 1971 相似-吸引效应；Reis & Shaver, 1988 回应性模型），不套用 Sternberg 承诺三角 —— 第一次见面谈「承诺」没有心理学意义。

    火花等级由综合分映射：≥90 烟花级 / ≥80 强火花 / ≥70 明显火花 / ≥60 小火苗 / ≥50 微光 / ＜50 火花未燃。依据：初识期三大信号（吸引 / 畅聊 / 再见意愿）同时高企时，关系发展概率最高；「再接触意愿」是关系启动最强前置预测指标。

    初识期的单次评分噪声大（首因光环效应），建议多轮评分让 EMA 平滑给出更稳定的读数。
    """

    /// 相性评级
    static let rank = """
    评级区间：SSS ≥90（天作之合）/ SS ≥80（双向奔赴）/ S ≥70（心动进行时）/ A ≥60（稳步升温）/ B ≥50（需要浇灌）/ C ＜50（坦诚对话期）。

    依据：评分为成长取向设计 —— 即使最低档也指向具体可行动作（深度沟通）而非评判性结论，与 Gottman「关系永远可以通过改变交互模式而改善」的立场一致（Gottman & Silver, 1999）。
    """

    /// 爱情类型
    static let loveType = """
    判定规则（深度关系期专用）：取双方三维（亲密/激情/承诺）聚合均分，≥65 视为该成分「显著」，八种组合对应 Sternberg 爱情三角理论的八种爱情类型（Sternberg, 1986, Psychological Review 93(2)）。

    初识心动期不进行此项判定（第一次见面谈承诺无心理学意义），改用「心动火花等级」（见火花区依据）。

    使用聚合值而非任何一方原始分，既保证结论反映关系整体，也保护双方原始分的私密性。
    """

    /// 默契指数
    static let harmony = """
    计算式：默契指数 = 100 − 双方六维评分的平均绝对差。互评越接近，指数越高。

    依据：共情准确性研究显示，准确感知伴侣内心状态的能力与关系满意度正相关，长期「感知错位」是关系恶化的早期信号（Ickes, 1993）；Gottman 的「爱情地图」表明幸福伴侣对彼此内心世界保有详细且不断更新的认知（Gottman & Silver, 1999）。
    """

    /// 六维聚合分级
    static let dimensionBands = """
    分级规则：待培育（＜60）/ 稳定（60-74）/ 良好（75-89）/ 极佳（≥90）。

    分级量化是刻意的隐私设计：聚合维度分是双方均值，若显示精确值，任何一方都能用「2 × 聚合分 − 自己的分」反推对方原始分；分级后反推只能得到一个区间。
    """

    /// 六维均衡度
    static let balance = """
    计算式：均衡度 = 100 − 2.2 × 六维聚合分的总体标准差。

    依据：关系研究显示维度间显著失衡（如激情远高于沟通）提示结构性风险 —— 单一优势维度无法补偿短板对整体满意度的影响。均衡度高说明你们的感情「没有明显瘸腿」，这比某一项特别突出更值得珍惜。
    """

    /// 经营建议
    static let advice = """
    生成规则：由当前最弱聚合维度映射至循证干预 —— 亲密→深度对话（自我表露研究）、激情→共同新体验（自我扩张模型）、承诺→共同目标（投资模型）、沟通→非暴力沟通、安全感→稳定回应（依恋理论）、回应性→情感邀请（Gottman）。默契低时追加爱情地图练习，失衡时提示补短板。

    所有干预均来自公开发表的实证研究，可安全实践。
    """

    /// 结果稳定度
    static let stability = """
    稳定度由双方累计评分轮次决定：0-1 轮为初测期（噪声大）、2-3 轮校准中、4-7 轮稳定追踪、8 轮以上为高信度追踪。

    依据：纵向研究优于单次横断测量的方法论原则 —— 轮次越多，EMA 平滑（α=0.6）后的结论越能反映关系的真实轨迹而非一时情绪。
    """
}
