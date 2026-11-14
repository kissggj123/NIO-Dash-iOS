//
//  NIODatingLabView.swift
//  wheater
//
//  恋爱好感度实验室 · 界面层
//  蜜柑 🍊 × 夏老师 🫧 的双人互评系统：
//  各自用 6 位密码解封专属评分台，原始分与留言全程 AES-256-GCM 加密；
//  双方完成首轮评分后解封「综合好感度」，由心理学引擎给出相性判定。
//

import SwiftUI

// MARK: - 主入口

struct NIODatingLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var vault = NIODatingVault.shared
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }
    private var mintCyan: Color { themeService.glowColor() }
    private var pastelYellow: Color { themeService.warmAccentColor() }

    static let mikanAccent = Color(red: 1.0, green: 0.62, blue: 0.26)
    static let xiaAccent = Color(red: 0.35, green: 0.76, blue: 0.97)

    private enum Flow: Equatable {
        case intro
        case setup(NIODatingMember)
        case handoff(NIODatingMember)
        case dashboard
        case passcode(NIODatingMember)
        case rating(NIODatingMember)
    }

    @State private var flow: Flow = .intro
    /// 评分台数据（密码验证成功后填充）
    @State private var ratingScores = NIODatingScores()
    @State private var ratingCode = ""
    /// 存档成功横幅
    @State private var archivedChapter: String?
    @State private var archivedDelta: Double?
    @State private var previousScores: NIODatingScores?
    @State private var archiveWork = NIOScheduledWork()

    var body: some View {
        NavigationStack {
            ZStack {
                labBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        switch flow {
                        case .intro:
                            introSection
                        case .setup(let member):
                            NIODatingPasscodeSetupView(member: member, accent: accent(for: member)) {
                                handleSetupFinished(for: member)
                            }
                        case .handoff(let member):
                            handoffSection(for: member)
                        case .dashboard:
                            dashboardSection
                        case .passcode(let member):
                            NIODatingPasscodeEntryView(member: member, accent: accent(for: member)) { code in
                                handlePasscodeVerified(member: member, code: code)
                            } onCancel: {
                                withAnimation(NIOThemeMotion.layoutSpring) { flow = .dashboard }
                            }
                        case .rating(let member):
                            NIODatingRatingFormView(
                                member: member,
                                scores: $ratingScores,
                                stage: vault.stage,
                                previousScores: previousScores,
                                accent: accent(for: member)
                            ) {
                                handleSubmit(member: member)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("恋爱好感度实验室")
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
            .overlay { privacyShield }
            .overlay(alignment: .top) { archiveBanner }
        }
        .onAppear {
            if flow == .intro, vault.isConfigured {
                flow = .dashboard
            }
        }
        // 重置向导执行销毁后，自动回到引导页重新开始
        .onChange(of: vault.isConfigured) { _, configured in
            if !configured {
                ratingCode = ""
                withAnimation(NIOThemeMotion.themeSpring) { flow = .intro }
            }
        }
    }

    // MARK: 流程控制

    private func accent(for member: NIODatingMember) -> Color {
        member == .mikan ? Self.mikanAccent : Self.xiaAccent
    }

    private func handleSetupFinished(for member: NIODatingMember) {
        // 引导期断点续设：优先设置尚未配置密码的一方
        if !vault.isMemberConfigured(.mikan) {
            withAnimation(NIOThemeMotion.themeSpring) { flow = .handoff(.mikan) }
        } else if !vault.isMemberConfigured(.xia) {
            withAnimation(NIOThemeMotion.themeSpring) { flow = .handoff(.xia) }
        } else {
            withAnimation(NIOThemeMotion.themeSpring) { flow = .dashboard }
        }
    }

    private func handlePasscodeVerified(member: NIODatingMember, code: String) {
        guard vault.lockoutRemaining(for: member) <= 0 else { return }
        guard vault.verifyPassword(code, for: member, registerFailure: true) else { return }

        let previous = vault.loadScores(for: member, code: code)
        var scores = previous ?? NIODatingScores()
        scores.chapter = (previous?.chapter ?? 0) + 1
        previousScores = previous
        ratingScores = scores
        ratingCode = code
        withAnimation(NIOThemeMotion.themeSpring) { flow = .rating(member) }
    }

    private func handleSubmit(member: NIODatingMember) {
        let outcome = vault.submit(scores: ratingScores, for: member, code: ratingCode)
        if case .success(let title, let delta) = outcome {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            withAnimation(NIOThemeMotion.themeSpring) {
                archivedChapter = title
                archivedDelta = delta
            }
            archiveWork.scheduleReplacing(after: 2.4) {
                withAnimation(NIOThemeMotion.themeSpring) {
                    archivedChapter = nil
                    archivedDelta = nil
                    flow = .dashboard
                }
            }
        }
    }

    // MARK: - 引导页

    /// 引导页：三页分步轮播（欢迎 → 玩法规则 → 隐私与理论）
    @State private var introPage = 0

    private var introSection: some View {
        VStack(spacing: 16) {
            TabView(selection: $introPage) {
                introWelcomePage.tag(0)
                introRulesPage.tag(1)
                introPrivacyPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(minHeight: 460)

            // 页点指示器
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == introPage ? sakuraPink : NIOThemePaint.text.opacity(0.18))
                        .frame(width: index == introPage ? 22 : 7, height: 7)
                        .animation(NIOThemeMotion.easeSmooth, value: introPage)
                }
            }

            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                if introPage < 2 {
                    withAnimation(NIOThemeMotion.easeSmooth) { introPage += 1 }
                } else {
                    startSetupFlow()
                }
            } label: {
                Text(introPage < 2 ? "下一步" : "开始设置专属密码")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(NIOPressableButtonStyle())
            .padding(.top, 2)
        }
    }

    /// 跳过引导直接进入设置（断点续设：优先未配置密码的一方）
    private func startSetupFlow() {
        withAnimation(NIOThemeMotion.themeSpring) {
            if !vault.isMemberConfigured(.mikan) {
                flow = .handoff(.mikan)
            } else if !vault.isMemberConfigured(.xia) {
                flow = .handoff(.xia)
            }
        }
    }

    private var introWelcomePage: some View {
        VStack(spacing: 14) {
            Text("💞")
                .font(.system(size: 64))
                .padding(.top, 24)
            Text("恋爱好感度实验室")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
            Text("为你们二人打造的心理测评游戏")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(lavenderDream)
            Text("蜜柑 🍊 与夏老师 🫧 基于专业心理学维度的双向好感度互评，适合从初识心动到稳定交往的每一个阶段。")
                .font(.system(size: 12))
                .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 10)
            HStack(spacing: 8) {
                ForEach(NIODatingStage.allCases) { stage in
                    Text(stage.displayName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(stage == vault.stage ? .white : NIOThemePaint.text.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(stage == vault.stage ? sakuraPink.opacity(0.85) : NIOThemePaint.stroke)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private var introRulesPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Text("🎮 怎么玩")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .padding(.top, 12)

                ruleCard(
                    icon: "🔐", title: "第一步 · 双人密码",
                    text: "各自设置一个 6 位专属密码。轮到你评分时输入自己的密码解锁专属评分台 —— 同一台手机上，谁的分数谁做主。"
                )
                ruleCard(
                    icon: "🖊", title: "第二步 · 盲评对方",
                    text: "对六项心理学维度打分（0-100 滑条），还可以写下仅心理引擎可见的心动留言。支持无限次重写，每次提交即连载新的一章。"
                )
                ruleCard(
                    icon: "✨", title: "第三步 · 解封结论",
                    text: "双方各完成一轮评分后自动解封：综合好感度、心动火花等级（初识）或爱情类型（稳定期）、默契指数与相性评级 —— 只见结论，不见彼此的原始分。"
                )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
    }

    private var introPrivacyPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Text("🛡 隐私与专业性")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .padding(.top, 12)

                ruleCard(
                    icon: "🙈", title: "军事级加密",
                    text: "你对 TA 打的每一项原始分与心动留言，都以 AES-256-GCM 认证加密存储，密钥由你的密码经 2 万轮拉伸派生 —— 没有你的密码，任何人都无法解密（包括 TA）。"
                )
                ruleCard(
                    icon: "🧠", title: "循证心理学引擎",
                    text: "初识心动期采用人际吸引研究维度（Aron 亲近感实验、Byrne 相似-吸引效应）；深度关系期采用 Sternberg 爱情三角 + Gottman 婚姻研究 + 依恋理论。留言情绪由 Apple NaturalLanguage 端内模型实时演算，零上传。"
                )
                ruleCard(
                    icon: "📐", title: "每一项数据都有依据",
                    text: "看板上综合分、评级、默契指数等每一项数据都附带可展开的「📐 依据」，写明计算式与文献出处；多轮评分按指数平滑聚合，越评越准。"
                )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
    }

    private func ruleCard(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 15))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 交接屏

    private func handoffSection(for member: NIODatingMember) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Text(member.emoji)
                .font(.system(size: 64))
            Text("请把手机交给 \(member.fullTitle)")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
            Text("接下来 \(member.displayName) 将设置自己的专属 6 位密码，\n请 \(member.counterpart.displayName) 回避一下哦 🔒")
                .font(.system(size: 12))
                .foregroundStyle(lavenderDream)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(NIOThemeMotion.themeSpring) { flow = .setup(member) }
            } label: {
                Text("我是 \(member.displayName)，准备好了")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accent(for: member))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(NIOPressableButtonStyle())
            Spacer(minLength: 40)
        }
    }

    // MARK: - 综合看板

    private var dashboardSection: some View {
        VStack(spacing: 16) {
            stageSwitchCard

            if let snapshot = vault.snapshot {
                NIODatingCompositeCardView(snapshot: snapshot)
            } else {
                sealedStateCard
            }

            ratingEntryCard

            psychologyTipCard

            privacyFooterCard

            resetCard
        }
    }

    // MARK: 关系阶段切换（初识心动期 / 深度关系期）

    @State private var pendingStage: NIODatingStage?
    @State private var showStageConfirmation = false

    private var stageSwitchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔦 关系阶段")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            Picker("关系阶段", selection: Binding(
                get: { vault.stage },
                set: { newValue in
                    guard newValue != vault.stage else { return }
                    pendingStage = newValue
                    showStageConfirmation = true
                }
            )) {
                ForEach(NIODatingStage.allCases) { stage in
                    Text(stage.displayName).tag(stage)
                }
            }
            .pickerStyle(.segmented)

            Text(vault.stage.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))

            Text("两套阶段采用独立的心理学维度体系与权重（专业性依据见看板各项「📐 依据」）；切换阶段将清空双方评分记录（密码保留）。")
                .font(.system(size: 9))
                .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NIOThemePaint.stroke, lineWidth: 1))
        )
        .confirmationDialog("切换到「\(pendingStage?.displayName ?? "")」？", isPresented: $showStageConfirmation, titleVisibility: .visible) {
            Button("切换并清空评分记录", role: .destructive) {
                if let target = pendingStage {
                    withAnimation(NIOThemeMotion.themeSpring) {
                        vault.applyStage(target)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("两套阶段维度体系不同，评分无法迁移。双方密码将保留。")
        }
    }

    private var sealedStateCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [sakuraPink.opacity(0.35), Color.clear],
                            center: .center, startRadius: 10, endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                Text("🔒")
                    .font(.system(size: 52))
            }
            .padding(.top, 10)

            Text("综合好感度尚未解封")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
            Text("等待你们各自完成首轮评分后自动解封\n在此之前，谁也看不到任何分数")
                .font(.system(size: 11))
                .foregroundStyle(lavenderDream)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 10) {
                sealBadge(member: .mikan)
                sealBadge(member: .xia)
            }
            .padding(.bottom, 12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NIOThemePaint.stroke, lineWidth: 1))
        )
    }

    private func sealBadge(member: NIODatingMember) -> some View {
        let rated = member == .mikan ? vault.hasMikanRated : vault.hasXiaRated
        return HStack(spacing: 6) {
            Text(member.emoji).font(.system(size: 14))
            Text(rated ? "已完成首轮" : "等待首轮")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(rated ? mintCyan : NIOThemePaint.text.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((rated ? mintCyan : NIOThemePaint.text).opacity(0.12))
        .clipShape(Capsule())
    }

    private var ratingEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🖊 专属评分台")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            HStack(spacing: 10) {
                entryButton(member: .mikan)
                entryButton(member: .xia)
            }

            Text("轮到你时输入自己的 6 位密码即可为对方实时修改评分（支持无限次重写，每次提交即连载新的一章）")
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NIOThemePaint.stroke, lineWidth: 1))
        )
    }

    private func entryButton(member: NIODatingMember) -> some View {
        let rated = member == .mikan ? vault.hasMikanRated : vault.hasXiaRated
        let accent = accent(for: member)
        return Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            ratingCode = ""
            withAnimation(NIOThemeMotion.themeSpring) { flow = .passcode(member) }
        } label: {
            VStack(spacing: 6) {
                Text(member.emoji)
                    .font(.system(size: 26))
                Text(member.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Text(rated ? "再评一轮" : "开始首轮")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.85))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accent.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(NIOPressableButtonStyle())
    }

    @State private var tipIndex = Int.random(in: 0..<(NIODatingPsychology.tips.count))

    private var psychologyTipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🎓 心理学小贴士")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(NIOThemeMotion.themeSpring) {
                        tipIndex = (tipIndex + 1 + Int.random(in: 0..<3)) % NIODatingPsychology.tips.count
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mintCyan)
                }
                .buttonStyle(NIOPressableButtonStyle())
            }
            Text(NIODatingPsychology.tips[tipIndex])
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(mintCyan.opacity(0.3), lineWidth: 1))
        )
    }

    private var privacyFooterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🛡 隐私与理论声明")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(pastelYellow)
            Text("· 原始评分与心动留言以 AES-256-GCM 认证加密存储，密钥由各自密码经 2 万轮拉伸派生，全程不出本机")
            Text("· 留言情绪由 Apple NaturalLanguage 端内模型实时演算，零上传零云端")
            Text("· 综合看板仅展示聚合分级，无法反推对方原始分；密码连续输错将触发递增冷却")
            Text("· 维度与判定基于 Sternberg (1986)、Gottman (1999)、Bowlby (1969)、Reis & Shaver (1988) 等公开研究，仅供趣味参考")
        }
        .font(.system(size: 10))
        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
        .lineSpacing(3)
        .padding(12)
        .background(NIOThemePaint.well)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @State private var showResetFlow = false

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚠️ 危险区")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.red.opacity(0.85))
            Text("重置将销毁双方密码、全部评分、留言与综合档案，且无法恢复。进入独立重置向导，需通过密码授权（或忘记密码恢复路径）才能执行。")
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
            Button {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
                showResetFlow = true
            } label: {
                Text("进入重置向导")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(NIOPressableButtonStyle())
            .sheet(isPresented: $showResetFlow) {
                NIODatingResetFlowView()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
        )
    }

    // MARK: - 存档横幅

    @ViewBuilder
    private var archiveBanner: some View {
        if let chapter = archivedChapter {
            VStack(spacing: 6) {
                Text("📖")
                    .font(.system(size: 28))
                Text("\(chapter) · 已存档")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                if let delta = archivedDelta {
                    // EMA 语义透明化：展示有效分较上一轮的变化
                    let arrow = delta >= 0 ? "↑" : "↓"
                    let color: Color = delta >= 0 ? .pink : Color(red: 0.35, green: 0.68, blue: 0.95)
                    Text("有效分较上一轮 \(arrow) \(String(format: "%.1f", abs(delta)))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
                Text("加密封存中，对方无法查看")
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(NIOThemePaint.fillStrong)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
                    )
                    .shadow(color: sakuraPink.opacity(0.4), radius: 18)
            )
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - 隐私遮挡（切后台模糊）

    @ViewBuilder
    private var privacyShield: some View {
        if scenePhase != .active {
            ZStack {
                themeService.backgroundPrimary().ignoresSafeArea()
                VStack(spacing: 10) {
                    Text("🛡")
                        .font(.system(size: 44))
                    Text("亲密数据保护中")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - 背景

    private var labBackground: some View {
        ZStack {
            themeService.backgroundPrimary()

            RadialGradient(
                colors: [sakuraPink.opacity(0.20), Color.clear],
                center: .topLeading, startRadius: 30, endRadius: 300
            )

            RadialGradient(
                colors: [lavenderDream.opacity(0.18), Color.clear],
                center: .bottomTrailing, startRadius: 50, endRadius: 340
            )

            FloatingHeartsOverlay()
        }
    }
}

// MARK: - 漂浮爱心

private struct FloatingHeartsOverlay: View {
    struct HeartSpec {
        let emoji: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let duration: Double
    }

    private let hearts: [HeartSpec] = [
        .init(emoji: "💗", x: 0.08, y: 0.18, size: 14, duration: 3.2),
        .init(emoji: "🩵", x: 0.88, y: 0.10, size: 12, duration: 3.8),
        .init(emoji: "✨", x: 0.16, y: 0.72, size: 11, duration: 4.2),
        .init(emoji: "💖", x: 0.80, y: 0.62, size: 13, duration: 3.5),
        .init(emoji: "🫧", x: 0.50, y: 0.88, size: 12, duration: 4.6)
    ]

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(hearts.enumerated()), id: \.offset) { index, spec in
                Text(spec.emoji)
                    .font(.system(size: spec.size))
                    .opacity(pulse ? 0.55 : 0.18)
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .position(x: geo.size.width * spec.x, y: geo.size.height * spec.y)
                    .animation(
                        .easeInOut(duration: spec.duration).repeatForever(autoreverses: true).delay(Double(index) * 0.4),
                        value: pulse
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { pulse = true }
    }
}

// MARK: - 「📐 依据」可展开说明（看板每项数据附理论依据）

struct NIODatingEvidenceDisclosure: View {
    let text: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(NIOThemeMotion.themeSpring) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.up.circle" : "book.closed.circle")
                        .font(.system(size: 11))
                    Text("📐 依据")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(mintCyan)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.62))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .background(NIOThemePaint.well)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var mintCyan: Color { Color(red: 0.3, green: 0.72, blue: 0.72) }
}

// MARK: - 密码设置（引导期）

struct NIODatingPasscodeSetupView: View {
    let member: NIODatingMember
    let accent: Color
    let onFinished: () -> Void

    private enum SetupPhase {
        case enter    // 首次输入
        case confirm  // 二次确认
    }

    @State private var firstCode = ""
    @State private var confirmCode = ""
    @State private var phase: SetupPhase = .enter
    @State private var isError = false
    @State private var shakeTrigger = 0

    private var isConfirmPhase: Bool { phase == .confirm }

    private var title: String {
        isConfirmPhase ? "请再次输入确认" : "设置你的 6 位专属密码"
    }

    private var hint: String {
        isConfirmPhase ? "再输入一次，确保记牢了哦" : "密码将用于加密你的评分与留言，请勿告诉对方"
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            Text(member.emoji)
                .font(.system(size: 52))

            Text("\(member.displayName) 的专属密码")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))

            NIODatingPasscodeDots(
                filled: (isConfirmPhase ? confirmCode : firstCode).count,
                isError: isError,
                accent: accent
            )
            .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

            Text("🔒 设置过程中请对方回避")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NIOThemePaint.text.opacity(0.4))

            NIODatingKeypad(accent: accent) { digit in
                handleDigit(digit)
            } onDelete: {
                handleDelete()
            }

            Spacer(minLength: 24)
        }
    }

    private func handleDigit(_ digit: String) {
        guard !isError else { return }
        if !isConfirmPhase {
            guard firstCode.count < 6 else { return }
            firstCode += digit
            if firstCode.count == 6 {
                // 首次输入完成，短暂停顿后进入确认阶段
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(NIOThemeMotion.themeSpring) {
                        phase = .confirm
                    }
                }
            }
        } else {
            guard confirmCode.count < 6 else { return }
            confirmCode += digit
            if confirmCode.count == 6 {
                verifyAndFinish()
            }
        }
    }

    private func handleDelete() {
        guard !isError else { return }
        if isConfirmPhase {
            if confirmCode.isEmpty {
                // 确认阶段删空后允许返回修改首次输入
                withAnimation(NIOThemeMotion.themeSpring) { phase = .enter }
            } else {
                confirmCode.removeLast()
            }
        } else {
            firstCode.removeLast()
        }
    }

    private func verifyAndFinish() {
        guard confirmCode == firstCode else {
            isError = true
            shakeTrigger += 1
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                confirmCode = ""
                withAnimation { isError = false }
            }
            return
        }

        if NIODatingVault.shared.configurePassword(for: member, code: confirmCode) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onFinished()
        }
    }
}

// MARK: - 密码输入（评分台解锁）

struct NIODatingPasscodeEntryView: View {
    let member: NIODatingMember
    let accent: Color
    let onVerified: (String) -> Void
    let onCancel: () -> Void

    @State private var code = ""
    @State private var isError = false
    @State private var shakeTrigger = 0
    @State private var failedCount = 0

    private var lockRemaining: TimeInterval {
        NIODatingVault.shared.lockoutRemaining(for: member)
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            Text(member.emoji)
                .font(.system(size: 52))

            Text("\(member.displayName)，欢迎回来")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            Text("输入你的 6 位密码解锁评分台")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            NIODatingPasscodeDots(filled: code.count, isError: isError, accent: accent)
                .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

            if lockRemaining > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = NIODatingVault.shared.lockoutRemaining(for: member)
                    Text(remaining > 0
                         ? "尝试次数过多，请等待 \(Int(remaining) + 1) 秒后重试 🧊"
                         : "冷却结束，可以再次尝试啦")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(remaining > 0 ? .orange : .green)
                }
            } else if failedCount > 0 {
                Text(failedCount >= 3 ? "怎么，想偷偷解开 TA 的分数吗？😏" : "密码不对哦，再想想")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            NIODatingKeypad(accent: accent, enabled: lockRemaining <= 0) { digit in
                handleDigit(digit)
            } onDelete: {
                if !code.isEmpty { code.removeLast() }
            }

            Button {
                onCancel()
            } label: {
                Text("返回")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.5))
            }
            .buttonStyle(NIOPressableButtonStyle())

            Spacer(minLength: 24)
        }
    }

    private func handleDigit(_ digit: String) {
        guard !isError, code.count < 6 else { return }
        code += digit
        if code.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                attemptVerify()
            }
        }
    }

    private func attemptVerify() {
        let candidate = code
        guard NIODatingVault.shared.lockoutRemaining(for: member) <= 0 else {
            code = ""
            return
        }

        if NIODatingVault.shared.verifyPassword(candidate, for: member, registerFailure: true) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onVerified(candidate)
        } else {
            isError = true
            failedCount += 1
            shakeTrigger += 1
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                code = ""
                withAnimation { isError = false }
            }
        }
    }
}

// MARK: - 密码圆点与键盘

struct NIODatingPasscodeDots: View {
    let filled: Int
    var isError = false
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .strokeBorder(index < filled ? accent : NIOThemePaint.text.opacity(0.3), lineWidth: 1.5)
                    .background(
                        Circle().fill(index < filled ? accent : Color.clear)
                    )
                    .frame(width: 14, height: 14)
                    .scaleEffect(index < filled ? 1.0 : 0.85)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: filled)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NIODatingKeypad: View {
    let accent: Color
    var enabled = true
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "del"]
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 68, height: 68)
                        } else if key == "del" {
                            keypadButton(systemImage: "delete.left") { onDelete() }
                        } else {
                            keypadDigit(key)
                        }
                    }
                }
            }
        }
    }

    private func keypadDigit(_ digit: String) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onDigit(digit)
        } label: {
            Text(digit)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
                .frame(width: 68, height: 68)
                .background(
                    Circle()
                        .fill(NIOThemePaint.fill)
                        .overlay(Circle().stroke(NIOThemePaint.stroke, lineWidth: 1))
                )
        }
        .buttonStyle(NIOPressableButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
    }

    private func keypadButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                .frame(width: 68, height: 68)
                .background(Circle().fill(Color.clear))
        }
        .buttonStyle(NIOPressableButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
    }
}

// MARK: - 评分表

struct NIODatingRatingFormView: View {
    let member: NIODatingMember
    @Binding var scores: NIODatingScores
    let stage: NIODatingStage
    /// 本人上一轮的原始评分（仅本人可见，供重写时对照）
    let previousScores: NIODatingScores?
    let accent: Color
    let onSubmit: () -> Void

    @ObservedObject private var themeService = AnimeThemeService.shared
    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }

    @State private var expandedDimensionKey: String?
    @State private var liveSentiment: Double?
    @State private var sentimentTask: Task<Void, Never>?
    @State private var isSubmitting = false

    private var stageDimensions: [NIODatingDimension] {
        NIODatingPsychology.dimensions(for: stage)
    }

    /// 实时演算的本次心动指数（仅本人可见）
    private var liveScore: Double {
        NIODatingEngine.effectiveScore(of: scores, sentiment: liveSentiment, stage: stage)
    }

    var body: some View {
        VStack(spacing: 16) {
            headerCard

            // 实时心动指数预览
            liveScoreCard

            ForEach(stageDimensions) { dim in
                dimensionCard(dim)
            }

            noteCard

            submitButton

            Text("提交后：本轮原始分加密存入个人密封区；聚合结果按指数移动平均（EMA α=0.6）与历史平滑 —— 本轮占 60%、历史占 40%，单次情绪波动不会颠覆长期轨迹（纵向追踪优于单次横断）。")
                .font(.system(size: 9))
                .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(member.emoji).font(.system(size: 34))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(member.displayName) 的评分台")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                    Text("第 \(scores.chapter) 章 · \(NIODatingChapters.title(forChapter: scores.chapter))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text("🔒 已解封")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(mintGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(mintGreen.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text("你正在给 \(member.counterpart.fullTitle) 打分。你的每一项原始分与留言都将以 AES-256-GCM 加密，\(member.counterpart.displayName) 永远看不到。")
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // 当前维度体系提示（阶段自适应）
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                Text("当前体系 · \(stage.displayName)：\(stage.subtitle)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.35), lineWidth: 1))
        )
    }

    private var mintGreen: Color { Color(red: 0.3, green: 0.8, blue: 0.55) }

    private var liveScoreCard: some View {
        HStack(spacing: 16) {
            NIODatingScoreRingView(value: liveScore, accent: accent)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 5) {
                Text("本次心动指数")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Text("加权均分 + 留言情绪加成，实时演算")
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                let reading = NIODatingSentiment.readingDescription(for: liveSentiment)
                HStack(spacing: 4) {
                    Text(reading.icon).font(.system(size: 12))
                    Text(reading.text)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(NIOThemePaint.stroke, lineWidth: 1))
        )
    }

    private func dimensionCard(_ dim: NIODatingDimension) -> some View {
        let value = Binding<Double>(
            get: { scores.value(forKey: dim.key) },
            set: { newValue in
                assign(newValue, forKey: dim.key)
            }
        )
        let isExpanded = expandedDimensionKey == dim.key

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(NIOThemeMotion.themeSpring) {
                    expandedDimensionKey = isExpanded ? nil : dim.key
                }
            } label: {
                HStack(spacing: 6) {
                    Text(dim.icon).font(.system(size: 14))
                    Text(dim.nameCN)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                    Text(dim.nameEN)
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                    Image(systemName: "book.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(accent.opacity(0.7))
                    Spacer()
                    Text("\(Int(value.wrappedValue))")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    Text("/100")
                        .font(.system(size: 10))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            Text(dim.question)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.7))

            Slider(value: value, in: 0...100, step: 1) {
                Text(dim.nameCN)
            }
            .tint(accent)

            // 实时分段解读：滑条拖动即时反馈该分数所处水平（心理测量分区）
            let interp = NIODatingEngine.scoreBandInterpretation(for: value.wrappedValue)
            HStack(spacing: 6) {
                Text(interp.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(bandInterpColor(interp.label))
                    .clipShape(Capsule())
                Text(interp.description)
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                Spacer()
                if let last = previousScores?.values[dim.key] {
                    Text("上次 · \(Int(last))")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NIOThemePaint.stroke.opacity(0.5))
                        .clipShape(Capsule())
                }
                Text("权重 \(String(format: "%.2f", dim.weight))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.4))
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("📖 \(dim.citation)")
                    Text("⚖️ 权重依据：\(dim.weightRationale)")
                }
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(NIOThemePaint.well)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(NIOThemePaint.stroke, lineWidth: 1))
        )
    }

    /// 分段解读标签配色
    private func bandInterpColor(_ label: String) -> Color {
        switch label {
        case "优秀区": return Color(red: 1.0, green: 0.45, blue: 0.55)
        case "良好区": return sakuraPink
        case "稳定区": return Color(red: 0.3, green: 0.72, blue: 0.72)
        case "待培育区": return Color(red: 0.85, green: 0.65, blue: 0.30)
        default: return Color(red: 0.88, green: 0.5, blue: 0.28)
        }
    }

    private func assign(_ value: Double, forKey key: String) {
        scores.setValue(value, forKey: key)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("💌 心动留言（可选）")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Text("仅你与心理引擎可见")
                    .font(.system(size: 9))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.4))
            }

            TextField("写下此刻想对 \(member.counterpart.displayName) 说的心里话…", text: $scores.note, axis: .vertical)
                .font(.system(size: 12))
                .lineLimit(2...5)
                .padding(10)
                .background(NIOThemePaint.well)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: scores.note) { _, newText in
                    scheduleSentimentAnalysis(for: newText)
                }

            HStack(spacing: 6) {
                Text("🛰").font(.system(size: 11))
                Text("Apple 神经引擎本地演算中…")
                    .font(.system(size: 9))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.45))
                Spacer()
                Text("\(scores.note.count) 字")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.4))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(lavenderDream.opacity(0.3), lineWidth: 1))
        )
        .onAppear {
            scheduleSentimentAnalysis(for: scores.note)
        }
        .onDisappear {
            sentimentTask?.cancel()
        }
    }

    /// 防抖 280ms 后调用 NaturalLanguage 端内模型实时演算留言情绪
    private func scheduleSentimentAnalysis(for text: String) {
        sentimentTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            liveSentiment = nil
            return
        }
        sentimentTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            liveSentiment = NIODatingSentiment.score(of: trimmed)
        }
    }

    private var submitButton: some View {
        Button {
            guard !isSubmitting else { return }
            isSubmitting = true
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            onSubmit()
            isSubmitting = false
        } label: {
            HStack(spacing: 8) {
                Text("🔒")
                Text("加密提交 · 封存本章")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [accent, sakuraPink], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NIOPressableButtonStyle())
    }
}

// MARK: - 综合看板卡

struct NIODatingCompositeCardView: View {
    let snapshot: NIODatingCompositeSnapshot

    @ObservedObject private var themeService = AnimeThemeService.shared
    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }
    private var mintCyan: Color { themeService.glowColor() }

    @State private var animatedOverall: Double = 0
    @State private var isTypeExpanded = false

    var body: some View {
        VStack(spacing: 14) {
            // 综合分环
            VStack(spacing: 6) {
                NIODatingScoreRingView(value: animatedOverall, accent: sakuraPink)
                    .frame(width: 140, height: 140)
                    .padding(.top, 8)

                Text("综合好感度")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))

                rankBadge

                stabilityBadge

                Text("你们的恋爱物语已连载 \(snapshot.combinedChapters) 章")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(lavenderDream)

                NIODatingEvidenceDisclosure(text: NIODatingEvidence.overall)
            }

            Divider().background(NIOThemePaint.stroke)

            // 爱情类型
            loveTypeSection

            Divider().background(NIOThemePaint.stroke)

            // 默契指数
            harmonySection

            Divider().background(NIOThemePaint.stroke)

            // 六维均衡度
            balanceSection

            Divider().background(NIOThemePaint.stroke)

            // 维度聚合分级
            dimensionBandsSection

            Divider().background(NIOThemePaint.stroke)

            // 建议
            adviceSection

            // 更新时间
            updateTimeFooter

            // 分享结论卡（仅聚合信息）
            Button {
                renderShareImage()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .bold))
                    Text("分享结论卡")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(sakuraPink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(sakuraPink.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(NIOPressableButtonStyle())
            .sheet(isPresented: $showShareSheet) {
                if let image = renderedShareImage {
                    VStack(spacing: 16) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.15), radius: 12)
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("恋爱好感度实验室 · 结论卡", image: Image(uiImage: image))
                        ) {
                            Label("保存 / 分享", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(sakuraPink)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding(20)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(colors: [sakuraPink.opacity(0.45), lavenderDream.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.15)) {
                animatedOverall = snapshot.overall
            }
        }
    }

    /// 稳定度徽章：轮次越多，EMA 平滑后的结论越可信
    private var stabilityBadge: some View {
        let stability = NIODatingEngine.stabilityLevel(combinedRounds: snapshot.combinedRounds)
        return VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .bold))
                Text(stability.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(mintCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(mintCyan.opacity(0.12))
            .clipShape(Capsule())

            Text(stability.description)
                .font(.system(size: 9))
                .foregroundStyle(NIOThemePaint.text.opacity(0.45))

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.stability)
        }
    }

    private var rankBadge: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(snapshot.rank.emoji).font(.system(size: 14))
                Text(snapshot.rank.title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
            .shadow(color: sakuraPink.opacity(0.4), radius: 8)

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.rank)
        }
    }

    /// 爱情类型（深度关系期）/ 心动火花等级（初识心动期）
    @ViewBuilder
    private var loveTypeSection: some View {
        if let spark = snapshot.sparkLevel {
            sparkSection(spark)
        } else {
            loveTypeDeepSection
        }
    }

    /// 初识心动期：心动火花等级
    private func sparkSection(_ spark: NIODatingSparkLevel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(spark.emoji).font(.system(size: 15))
                Text("心动火花 · \(spark.title)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Image(systemName: isTypeExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(lavenderDream)
            }

            Text(spark.summary)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if isTypeExpanded {
                Text("📖 \(spark.citation)")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                    .italic()
                    .padding(8)
                    .background(NIOThemePaint.well)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.firstSpark)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(NIOThemeMotion.themeSpring) { isTypeExpanded.toggle() }
        }
    }

    /// 深度关系期：Sternberg 爱情类型
    private var loveTypeDeepSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(snapshot.loveType.emoji).font(.system(size: 15))
                Text("爱情类型 · \(snapshot.loveType.title)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Image(systemName: isTypeExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(lavenderDream)
            }

            Text(snapshot.loveType.summary)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if isTypeExpanded {
                Text("📖 \(snapshot.loveType.citation)")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                    .italic()
                    .padding(8)
                    .background(NIOThemePaint.well)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.loveType)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(NIOThemeMotion.themeSpring) { isTypeExpanded.toggle() }
        }
    }

    private var harmonySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("💫 默契指数")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Text("\(Int(snapshot.harmony))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(mintCyan)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NIOThemePaint.well)
                    Capsule()
                        .fill(LinearGradient(colors: [mintCyan.opacity(0.7), mintCyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * snapshot.harmony / 100)
                }
            }
            .frame(height: 8)
            Text(harmonyCaption)
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.harmony)
        }
    }

    private var harmonyCaption: String {
        if snapshot.stage == .firstSpark {
            // 初识心动期：双方对同一次相处的感知一致性
            switch snapshot.harmony {
            case 85...: return "心有灵犀 —— 你们对这次相处的感受高度一致"
            case 70..<85: return "感知接近 —— 大部分时刻你们想到一块去了"
            case 50..<70: return "存在温差 —— 初识期很正常，多一次相处就能校准"
            default: return "感知差异明显 —— 别急着下结论，再相处观察几次"
            }
        }
        switch snapshot.harmony {
        case 85...: return "心有灵犀 —— 你们对这段关系的感知高度同频"
        case 70..<85: return "默契良好 —— 大多数时刻你们想到一块去了"
        case 50..<70: return "存在温差 —— 多聊聊彼此的感受，校准爱的频率"
        default: return "感知错位 —— 建议来一次温柔的深度对话（试试爱情地图练习）"
        }
    }

    /// 六维均衡度：100 − 2.2 × 聚合维度标准差（旧快照无数据时隐藏）
    @ViewBuilder
    private var balanceSection: some View {
        if let balance = snapshot.balance {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("⚖️ 六维均衡度")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                    Spacer()
                    Text("\(Int(balance))")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(sakuraPink)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NIOThemePaint.well)
                        Capsule()
                            .fill(LinearGradient(colors: [sakuraPink.opacity(0.7), sakuraPink], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * balance / 100)
                    }
                }
                .frame(height: 8)
                Text(balanceCaption(for: balance))
                    .font(.system(size: 10))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))

                NIODatingEvidenceDisclosure(text: NIODatingEvidence.balance)
            }
        }
    }

    private func balanceCaption(for balance: Double) -> String {
        switch balance {
        case 80...: return "齐头并进 —— 六维没有明显瘸腿，这比单项突出更难得"
        case 62..<80: return "基本均衡 —— 个别维度稍弱，补短板收益最大"
        default: return "出现失衡 —— 某一项显著拖后腿，优先照顾最弱维度"
        }
    }

    private var dimensionBandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🌈 六维聚合评级")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
                .padding(.bottom, 2)

            ForEach(NIODatingPsychology.dimensions(for: snapshot.stage)) { dim in
                HStack(spacing: 8) {
                    Text(dim.icon).font(.system(size: 12))
                    Text(dim.nameCN)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NIOThemePaint.text)
                        .frame(width: 38, alignment: .leading)

                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { seg in
                            let band = snapshot.dimensionBands[dim.key] ?? 0
                            Capsule()
                                .fill(seg <= band ? bandColor(band) : NIOThemePaint.well)
                                .frame(height: 6)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Text("\(NIODatingEngine.bandIcons[snapshot.dimensionBands[dim.key] ?? 0]) \(NIODatingEngine.bandLabels[snapshot.dimensionBands[dim.key] ?? 0])")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        .frame(width: 46, alignment: .trailing)
                }
            }

            Text("分级聚合展示：即使知道自己的分数，也只能把对方的分数反推到一个区间")
                .font(.system(size: 9))
                .foregroundStyle(NIOThemePaint.text.opacity(0.4))

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.dimensionBands)
        }
    }

    private func bandColor(_ band: Int) -> Color {
        switch band {
        case 0: return Color(red: 0.85, green: 0.65, blue: 0.30).opacity(0.8)
        case 1: return mintCyan.opacity(0.85)
        case 2: return sakuraPink.opacity(0.9)
        default: return Color(red: 1.0, green: 0.45, blue: 0.55)
        }
    }

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🏷 本期经营建议")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
            Text(snapshot.advice)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            NIODatingEvidenceDisclosure(text: NIODatingEvidence.advice)
        }
        .padding(10)
        .background(NIOThemePaint.well)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var updateTimeFooter: some View {
        HStack(spacing: 8) {
            if let mikanDate = snapshot.mikanLastUpdate {
                Text("🍊 \(mikanDate.relativeShortDescription)")
            }
            if snapshot.mikanLastUpdate != nil && snapshot.xiaLastUpdate != nil {
                Text("·")
            }
            if let xiaDate = snapshot.xiaLastUpdate {
                Text("🫧 \(xiaDate.relativeShortDescription)")
            }
            Spacer()
            Text(snapshot.rank.verdict)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(sakuraPink)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 10))
        .foregroundStyle(NIOThemePaint.text.opacity(0.5))
    }

    // MARK: 分享结论卡

    @State private var renderedShareImage: UIImage?
    @State private var showShareSheet = false

    /// 将看板结论渲染为可分享的图片卡（仅聚合信息，不含个人原始分）
    private func renderShareImage() {
        let renderer = ImageRenderer(content: NIODatingShareCardView(snapshot: snapshot))
        renderer.scale = 3
        renderedShareImage = renderer.uiImage
        if renderedShareImage != nil {
            showShareSheet = true
        }
    }
}

// MARK: - 可分享结论卡（固定浅色设计，渲染为图片）

struct NIODatingShareCardView: View {
    let snapshot: NIODatingCompositeSnapshot

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("💞 恋爱好感度实验室")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(snapshot.stage.displayName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                Spacer()
                Text(snapshot.generatedAt.formatted(.dateTime.year().month().day()))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("\(Int(snapshot.overall))")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("综合好感度")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)

                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.35))
                    .frame(width: 1, height: 54)

                VStack(spacing: 4) {
                    if let spark = snapshot.sparkLevel {
                        Text("\(spark.emoji) \(spark.title)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text("心动火花")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .opacity(0.85)
                    } else {
                        Text("\(snapshot.loveType.emoji) \(snapshot.loveType.title)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("Sternberg 爱情类型")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                shareBadge(text: "🤝 默契 \(Int(snapshot.harmony))")
                shareBadge(text: "\(snapshot.rank.emoji) \(snapshot.rank.title)")
            }

            Text("蜜柑 🍊 × 夏老师 🫧 · 循证心理学引擎 · 只见结论不见原始分")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(22)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.64),
                    Color(red: 0.64, green: 0.5, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func shareBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18))
            .clipShape(Capsule())
    }
}

// MARK: - 分数环

struct NIODatingScoreRingView: View {
    let value: Double
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(NIOThemePaint.well, lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(0.001, value / 100))
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.5), accent],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(NIOThemeMotion.easeSmooth, value: value)

            VStack(spacing: 0) {
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(NIOThemeMotion.easeSmooth, value: value)
                Text("/ 100")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.45))
            }
        }
    }
}

// MARK: - 重置向导（三步：警示 → 授权 → 执行）

/// 独立重置流程：防止任何人随手销毁实验室数据。
/// 授权路径二选一：① 任一方输入自己的密码验证；② 双方都忘记密码时，输入确认短语并等待 10 秒冷静期。
struct NIODatingResetFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vault = NIODatingVault.shared
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var sakuraPink: Color { themeService.accentColor() }

    private enum Step {
        case warning       // 数据清单警示
        case authPassword  // 密码授权
        case authRecovery  // 忘记密码恢复路径
        case execute       // 最终执行
    }

    /// 忘记密码路径的确认短语
    static let recoveryPhrase = "销毁实验室"
    private static let recoveryCooldown: Int = 10

    @State private var step: Step = .warning
    @State private var selectedMember: NIODatingMember = .mikan
    @State private var code = ""
    @State private var phrase = ""
    @State private var countdown = NIODatingResetFlowView.recoveryCooldown
    @State private var isError = false
    @State private var shakeTrigger = 0
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                themeService.backgroundPrimary().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        switch step {
                        case .warning: warningStep
                        case .authPassword: authPasswordStep
                        case .authRecovery: authRecoveryStep
                        case .execute: executeStep
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("重置实验室")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sakuraPink)
                }
            }
        }
        .onDisappear {
            cooldownTask?.cancel()
        }
    }

    // MARK: Step 1 · 数据清单警示

    private var warningStep: some View {
        VStack(spacing: 16) {
            Text("⚠️")
                .font(.system(size: 52))
                .padding(.top, 16)

            Text("重置将销毁以下全部数据")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            VStack(alignment: .leading, spacing: 8) {
                destroyItem(icon: "🔐", text: "双方的密码验证器（设置后需重新引导）")
                destroyItem(icon: "📝", text: "全部评分记录与心动留言（加密数据不可恢复）")
                destroyItem(icon: "💞", text: "综合档案、聚合摘要与相性判定历史")
                destroyItem(icon: "🔦", text: "关系阶段设置（重置后回到默认初识心动期）")
            }
            .padding(14)
            .background(NIOThemePaint.fill)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.35), lineWidth: 1))

            Text("此操作无法撤销。为防止误触，需要通过授权验证才能执行。")
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                .multilineTextAlignment(.center)

            Button {
                withAnimation(NIOThemeMotion.themeSpring) { step = .authPassword }
            } label: {
                Text("我记得我们的密码")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(sakuraPink)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(NIOPressableButtonStyle())

            Button {
                startRecoveryCooldown()
                withAnimation(NIOThemeMotion.themeSpring) { step = .authRecovery }
            } label: {
                Text("我们都忘记密码了")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(NIOThemePaint.stroke, lineWidth: 1))
            }
            .buttonStyle(NIOPressableButtonStyle())
        }
    }

    private func destroyItem(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(NIOThemePaint.text.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 2a · 密码授权

    private var authPasswordStep: some View {
        VStack(spacing: 20) {
            Text(selectedMember.emoji)
                .font(.system(size: 48))
                .padding(.top, 12)

            Text("输入 \(selectedMember.displayName) 的密码授权重置")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
                .multilineTextAlignment(.center)

            Picker("成员", selection: $selectedMember) {
                ForEach(NIODatingMember.allCases) { member in
                    Text(member.fullTitle).tag(member)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 30)

            NIODatingPasscodeDots(filled: code.count, isError: isError, accent: sakuraPink)
                .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

            Text("任一方密码验证通过即可重置 · 连续输错会触发冷却")
                .font(.system(size: 10))
                .foregroundStyle(NIOThemePaint.text.opacity(0.5))

            NIODatingKeypad(accent: sakuraPink) { digit in
                handleAuthDigit(digit)
            } onDelete: {
                if !code.isEmpty { code.removeLast() }
            }
        }
    }

    private func handleAuthDigit(_ digit: String) {
        guard !isError, code.count < 6 else { return }
        code += digit
        if code.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                verifyAuthCode()
            }
        }
    }

    private func verifyAuthCode() {
        let candidate = code
        guard vault.lockoutRemaining(for: selectedMember) <= 0 else {
            code = ""
            return
        }
        if vault.verifyPassword(candidate, for: selectedMember, registerFailure: true) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            withAnimation(NIOThemeMotion.themeSpring) { step = .execute }
        } else {
            isError = true
            shakeTrigger += 1
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                code = ""
                withAnimation { isError = false }
            }
        }
    }

    // MARK: Step 2b · 忘记密码恢复路径

    private var authRecoveryStep: some View {
        VStack(spacing: 18) {
            Text("🧯")
                .font(.system(size: 48))
                .padding(.top, 12)

            Text("忘记密码恢复路径")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            Text("输入确认短语「\(NIODatingResetFlowView.recoveryPhrase)」，并等待 \(NIODatingResetFlowView.recoveryCooldown) 秒冷静期。冷静期是给「突然想起来密码」留的最后机会。")
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            TextField("输入确认短语", text: $phrase)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(12)
                .background(NIOThemePaint.well)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 30)

            Button {
                guard phrase.trimmingCharacters(in: .whitespaces) == NIODatingResetFlowView.recoveryPhrase, countdown <= 0 else { return }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                withAnimation(NIOThemeMotion.themeSpring) { step = .execute }
            } label: {
                Text(countdown > 0
                     ? "请等待冷静期 \(countdown) 秒"
                     : (phrase.trimmingCharacters(in: .whitespaces) == NIODatingResetFlowView.recoveryPhrase
                        ? "短语正确，继续"
                        : "请输入确认短语"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(countdown <= 0 && phrase.trimmingCharacters(in: .whitespaces) == NIODatingResetFlowView.recoveryPhrase ? .white : NIOThemePaint.text.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(countdown <= 0 && phrase.trimmingCharacters(in: .whitespaces) == NIODatingResetFlowView.recoveryPhrase ? Color.red.opacity(0.8) : NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(NIOPressableButtonStyle())
            .disabled(countdown > 0)
            .padding(.horizontal, 30)
        }
    }

    /// 启动 10 秒冷静期倒计时
    private func startRecoveryCooldown() {
        countdown = NIODatingResetFlowView.recoveryCooldown
        cooldownTask?.cancel()
        cooldownTask = Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
        }
    }

    // MARK: Step 3 · 最终执行

    private var executeStep: some View {
        VStack(spacing: 18) {
            Text("🔥")
                .font(.system(size: 52))
                .padding(.top, 16)

            Text("授权通过")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            Text("最后一步：点击下方按钮将立即销毁实验室全部数据，且无法恢复。")
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                .multilineTextAlignment(.center)

            Button {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                vault.resetAll()
                dismiss()
            } label: {
                Text("永久销毁全部数据")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(NIOPressableButtonStyle())

            Button {
                dismiss()
            } label: {
                Text("我反悔了，保留数据")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
            }
            .buttonStyle(NIOPressableButtonStyle())
        }
    }
}

// MARK: - 抖动效果

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2), y: 0)
        )
    }
}

// MARK: - 日期描述

private extension Date {
    var relativeShortDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
