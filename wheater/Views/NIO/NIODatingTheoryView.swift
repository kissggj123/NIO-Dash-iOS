import SwiftUI

// MARK: - 心理学理论依据 · 原生理论页
// 实验室的全量理论文档视图：章节内容与看板「📐 依据」共用同一数据源（NIODatingEvidence /
// NIODatingPsychology），文案更新自动同步；本页补全概述 / 隐私设计 / 伦理声明 / 参考文献四块

/// 心理学理论依据页（从看板入口以 sheet 呈现，禁用下滑误关）
struct NIODatingTheoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeService = AnimeThemeService.shared
    @ObservedObject private var vault = NIODatingVault.shared

    private var sakuraPink: Color { themeService.accentColor() }
    private var mintCyan: Color { themeService.glowColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }

    /// 理论页按当前关系阶段展示对应维度体系
    private var stage: NIODatingStage { vault.stage }

    var body: some View {
        NavigationStack {
            ZStack {
                themeService.backgroundPrimary().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        overviewSection
                        dimensionSection
                        pipelineSection
                        verdictSection
                        privacySection
                        ethicsSection
                        referencesSection

                        Text("恋爱好感度实验室 · 理论文档 v5.1 · 与 App 内「📐 依据」同源")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("心理学理论依据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sakuraPink)
                }
            }
        }
    }

    // MARK: 头部

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("📚")
                .font(.system(size: 44))
                .shadow(color: sakuraPink.opacity(0.2), radius: 10)
            Text("心理学理论依据")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
                )
            Text("实验室的每一次评分、每一条结论，都建立在公开发表的实证研究之上")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(sectionCard)
    }

    // MARK: 01 系统概述

    private var overviewSection: some View {
        theoryCard(index: "01", title: "系统概述", icon: "🧭") {
            theoryParagraph("""
            实验室采用「双向盲评」机制：双方在同一台设备上各持独立密码，互不可见对方的原始分数与留言，只能看到聚合后的综合结论 —— 评价的匿名性让每一条打分都更接近真实态度（社会称许性偏差的最小化设计）。

            设计哲学是「信度 — 效度 — 趣味」三角：信度上用纵向追踪与稳健统计压低单轮噪声；效度上每个维度都取自有文献支撑的构念，权重按其对关系满意度的预测力分配；趣味上用章节连载、火花等级与结论卡把严肃量表变成一场两个人的小实验。
            """)
            theoryParagraph("""
            全部结论均由双方评分聚合而来 —— 看板永远不知道也不会泄露任何一方的原始打分。本页与看板中每项数据的「📐 依据」同源，随时可交叉对照。
            """)
        }
    }

    // MARK: 02 六维模型

    private var dimensionSection: some View {
        theoryCard(index: "02", title: "六维评分模型", icon: "🧬") {
            theoryParagraph("""
            当前关系阶段：「\(stage.displayName)」。两套阶段体系独立设计与加权 —— 初识心动期用人际吸引研究维度，深度关系期用 Sternberg 三角 + 关系科学维度，第一次见面谈「承诺」与稳定交往谈「火花」同样是效度错误。
            """)

            ForEach(NIODatingPsychology.dimensions(for: stage)) { dim in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(dim.icon)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(dim.nameCN) · \(dim.nameEN)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(NIOThemePaint.text)
                        }
                        Spacer()
                        Text(String(format: "权重 %.0f%%", dim.weight * 100))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(sakuraPink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(sakuraPink.opacity(0.12)))
                    }

                    // 权重条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(NIOThemePaint.stroke.opacity(0.5))
                            Capsule()
                                .fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * dim.weight / 0.25)
                        }
                    }
                    .frame(height: 5)

                    Text("⚖️ \(dim.weightRationale)")
                        .font(.system(size: 10))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.62))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("📖 \(dim.citation)")
                        .font(.system(size: 10, design: .serif))
                        .italic()
                        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(NIOThemePaint.well)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.overall)
        }
    }

    // MARK: 03 综合计算流水线

    private var pipelineSection: some View {
        theoryCard(index: "03", title: "综合计算流水线", icon: "⚙️") {
            theoryParagraph("""
            每次提交后，评分经过七步流水线才成为看板上的结论 —— 每一步都对应一种已知的测量误差及其校正方法：
            """)
            pipelineStep(no: "1", title: "情感演算", desc: "留言情绪由 Apple NaturalLanguage 端内模型实时打分（±6 封顶），让结构性评估不被一时情绪淹没")
            pipelineStep(no: "2", title: "首测先验收缩", desc: "首轮聚合起点 = 0.8×本轮 + 0.2×中性先验 70 分，防止单轮极端印象锚定长期轨迹（首测均值回归）")
            pipelineStep(no: "3", title: "自适应 EMA 平滑", desc: "α 随轮次递减（0.70 → 0.40-0.50），早期快速吸收、后期结论趋稳（信度累积曲线）")
            pipelineStep(no: "4", title: "默许偏差过滤", desc: "单轮各维度几乎同分（σ<5）判定为未做真实区分，该轮证据降权 0.1（Paulhus, 1991）")
            pipelineStep(no: "5", title: "加权聚合", desc: "维度分按阶段权重加权 → 有效分；默契指数 = 100×e^(−加权感知差/30)（距离衰减非线性）")
            pipelineStep(no: "6", title: "稳健趋势估计", desc: "Theil–Sen 配对斜率中位数（抗离群点）+ Mann–Kendall 显著性检验（|z|>1.96 才当真）")
            pipelineStep(no: "7", title: "滞后判定与信度", desc: "评级 / 类型 / 火花全部带边界滞后缓冲防抖；连续信度 = 1−e^(−n/5) 随轮次指数累积")
        }
    }

    // MARK: 04 结论判定

    private var verdictSection: some View {
        theoryCard(index: "04", title: "结论判定逻辑", icon: "🎯") {
            theoryParagraph("""
            看板上的每一类结论都由聚合计量映射而来：初识心动期输出「心动火花等级」（综合分六档映射），深度关系期输出 Sternberg 爱情类型（亲密 / 激情 / 承诺三成分 × 65 分阈值）。全部判定使用聚合值，个人原始分不参与任何展示。
            """)
            NIODatingEvidenceDisclosure(text: stage == .firstSpark ? NIODatingEvidence.firstSpark : NIODatingEvidence.loveType)
            NIODatingEvidenceDisclosure(text: NIODatingEvidence.rank)
            NIODatingEvidenceDisclosure(text: NIODatingEvidence.harmony)
            NIODatingEvidenceDisclosure(text: NIODatingEvidence.trend)
            NIODatingEvidenceDisclosure(text: NIODatingEvidence.stability)
            NIODatingEvidenceDisclosure(text: NIODatingEvidence.aron36)
        }
    }

    // MARK: 05 隐私与加密设计

    private var privacySection: some View {
        theoryCard(index: "05", title: "隐私与加密设计", icon: "🔐") {
            theoryParagraph("""
            个人原始分与留言以 AES-256-GCM 认证加密密封，密钥由本人 6 位密码经 2 万轮 SHA256 拉伸派生 —— 没有密码，任何人（包括对方与 App 自身界面）都无法解封。同一密码的派生密钥在一次会话内缓存复用（键为盐+密码的 SHA256 摘要，不存明文），让验证毫秒级响应而不牺牲安全性。

            聚合维度的分级量化展示（待培育 / 稳定 / 良好 / 极佳）是一种隐私保护设计：即使知道自己的原始分，也只能把对方的分数反推到一个区间而非精确值。密码连续输错触发递增冷却（30 秒 → 1 小时），抑制暴力穷举。
            """)
        }
    }

    // MARK: 06 伦理声明

    private var ethicsSection: some View {
        theoryCard(index: "06", title: "伦理声明", icon: "🫶") {
            theoryParagraph("""
            这是一份为两个人设计的趣味关系实验，不是临床评估工具。与标准化量表（如 CBI、RCI）相比，实验室的维度做了游戏化简化，分数不具备诊断效力。

            三点已知局限：① 自评数据天然受心境与记忆影响，评分应尽量在冷静时完成；② 结论的意义在于打开对话而非给出裁判 —— 建议双方在情绪平稳时一起看板讨论；③ 火花低不等于关系差，初次测量的噪声远大于信号，请让多轮数据说话。

            唯一的「使用规范」：请把这份实验当作了解彼此的放大镜，而不是审判对方的尺子。
            """)
        }
    }

    // MARK: 07 参考文献

    private var referencesSection: some View {
        theoryCard(index: "07", title: "参考文献", icon: "📖") {
            ForEach(Array(NIODatingReferences.all.enumerated()), id: \.offset) { _, ref in
                HStack(alignment: .top, spacing: 8) {
                    Text("[\(ref.no)]")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(sakuraPink)
                    Text(ref.text)
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: 复用组件

    private var sectionCard: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(NIOThemePaint.fill)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(NIOThemePaint.stroke, lineWidth: 1)
            )
    }

    private func theoryCard(
        index: String,
        title: String,
        icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(icon) \(index)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(sakuraPink))
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionCard)
    }

    private func theoryParagraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(NIOThemePaint.text.opacity(0.78))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pipelineStep(no: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(no)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(lavenderDream))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.62))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

/// 参考文献列表（理论页专用，与 Evidence 文案中的引用对应）
enum NIODatingReferences {
    struct Reference {
        let no: Int
        let text: String
    }

    static let all: [Reference] = [
        Reference(no: 1, text: "Sternberg, R. J. (1986). A triangular theory of love. Psychological Review, 93(2), 119-135."),
        Reference(no: 2, text: "Gottman, J. M., & Levenson, R. W. (1992). Marital processes predictive of later dissolution. Journal of Consulting and Clinical Psychology, 60(1), 1-9."),
        Reference(no: 3, text: "Gottman, J. M., & Silver, N. (1999). The Seven Principles for Making Marriage Work. Crown Publishers."),
        Reference(no: 4, text: "Bowlby, J. (1969). Attachment and Loss: Vol. 1. Attachment. Basic Books."),
        Reference(no: 5, text: "Reis, H. T., & Shaver, P. (1988). Intimacy as an interpersonal process. In Handbook of Personal Relationships. Wiley."),
        Reference(no: 6, text: "Aron, A., Melinat, E., Aron, E. N., Vallone, R. D., & Bator, R. J. (1997). The experimental generation of interpersonal closeness. Personality and Social Psychology Bulletin, 23(4), 363-377."),
        Reference(no: 7, text: "Byrne, D. (1971). The Attraction Paradigm. Academic Press."),
        Reference(no: 8, text: "Ickes, W. (1993). Empathic accuracy. Journal of Personality, 61(4), 587-610."),
        Reference(no: 9, text: "Paulhus, D. L. (1991). Measurement and control of response bias. In Measures of Personality and Social Psychological Attitudes. Academic Press."),
        Reference(no: 10, text: "Karney, B. R., & Bradbury, T. N. (1995). The longitudinal course of marital quality and stability. Psychological Bulletin, 118(1), 3-34."),
        Reference(no: 11, text: "Theil, H. (1950). A rank-invariant method of linear and polynomial regression analysis. Nederl. Akad. Wetensch. Proc., 53."),
        Reference(no: 12, text: "Sen, P. K. (1968). Estimates of the regression coefficient based on Kendall's tau. Journal of the American Statistical Association, 63(324), 1379-1389."),
        Reference(no: 13, text: "Mann, H. B. (1945). Nonparametric tests against trend. Econometrica, 13(3), 245-259."),
        Reference(no: 14, text: "Pennebaker, J. W. (1997). Writing about emotional experiences as a therapeutic process. Psychological Science, 8(3), 162-166."),
    ]
}
