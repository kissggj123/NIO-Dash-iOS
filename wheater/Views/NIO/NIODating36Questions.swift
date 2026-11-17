import SwiftUI

// MARK: - Aron 36 问 · 渐进式自我表露彩蛋
// 理论依据：Aron, Melinat, Aron, Vallone & Bator (1997)《The Experimental Generation of
// Interpersonal Closeness》—— 两人轮流回答 36 个逐级加深的私人问题（三组 × 12 问），
// 实验室条件下陌生人即可生成显著亲近感；结尾 4 分钟对视是原始协议的收尾环节。
// 畅聊感（flow 维度）聚合分处于「待培育」区时，看板建议卡提供本练习入口。

/// Aron 36 问题库（三组渐进式自我表露，中文通行版）
enum NIODating36Questions {

    struct QuestionSet {
        let title: String
        let subtitle: String
        let questions: [String]
    }

    static let sets: [QuestionSet] = [
        QuestionSet(
            title: "第一组 · 轻度表露",
            subtitle: "兴趣与经历层面 —— 先让话题流动起来",
            questions: [
                "如果可以在世界上任何一个人面前选晚餐对象，你想邀请谁？",
                "你想成名吗？想以什么方式成名？",
                "打电话之前，你会先排练要说的话吗？为什么？",
                "对你来说，「完美的一天」必须包含什么？",
                "你上一次对着自己唱歌是什么时候？上次对别人唱呢？",
                "如果你能活到 90 岁，并把 30 岁之后的心智保持在中年状态，你想要 60 年的躯体还是 60 年的心智？",
                "你有预感过自己会以什么方式离开这个世界吗？",
                "说出三件你和你对面这个人似乎拥有的共同点。",
                "你人生中最感激的是什么？",
                "如果能改变自己成长过程中的任何事情，你想改变什么？",
                "用四分钟的时间，尽量详细地讲述你的故事。",
                "如果明天醒来能拥有一项新品质或能力，你希望是什么？"
            ]
        ),
        QuestionSet(
            title: "第二组 · 中度表露",
            subtitle: "价值观与内心层面 —— 开始交换真实的样子",
            questions: [
                "如果有一个水晶球能告诉你关于自己、人生、未来的任何真相，你想知道什么？",
                "有没有什么是你一直梦想去做、却一直没有做的？为什么没做？",
                "你人生中最大的成就是什么？",
                "一段友谊里，你最珍视什么？",
                "你最珍贵的记忆是什么？",
                "你最糟糕的记忆是什么？",
                "如果知道一年之内会突然离开，你会改变现在的生活方式吗？为什么？",
                "友谊对你来说意味着什么？",
                "爱与情感在你生命中扮演什么角色？",
                "轮流说出对方身上值得称道的地方，每人五条。（试着看着对方的眼睛说）",
                "你的家人亲密温暖吗？你觉得自己的童年比大多数人更快乐吗？",
                "你觉得你和母亲的关系怎么样？"
            ]
        ),
        QuestionSet(
            title: "第三组 · 深度表露",
            subtitle: "关系与脆弱层面 —— 这是最靠近内心的一段",
            questions: [
                "用「我们」造三个句子，比如「我们都在这个房间里，感觉……」",
                "补完这个句子：「我希望我有一个人可以和我分享……」",
                "如果你要和对方成为密友，请说出 TA 最需要知道的事情。",
                "告诉对方你喜欢 TA 的什么——要诚实，说一些通常不会对刚认识的人说的话。",
                "和对方分享你人生中一个尴尬的时刻。",
                "你上一次在别人面前哭是什么时候？独自一人哭呢？",
                "告诉对方你已经喜欢上 TA 的什么，必须诚实。",
                "有没有什么事情是不能拿来开玩笑的？",
                "如果今晚你会毫无预兆地离开，你最后悔没告诉别人的是什么？为什么还没说？",
                "房子着火了，救出家人和宠物后，你还能进去拿一件东西，是什么？为什么？",
                "全家人之中，谁的离开会让你最难受？为什么？",
                "分享一个你的私人问题，请对方给你建议——然后请 TA 告诉你，在 TA 看来你面对这个问题时是什么感受。"
            ]
        )
    ]

    /// 原始协议收尾：4 分钟对视（Aron 1997 实验最后一环）
    static let eyeGazeSeconds: Int = 240
}

/// Aron 36 问翻卡页（sheet 呈现，禁下滑误关）
struct NIODating36QuestionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }

    /// 全局题号（0…35），36 表示已完成进入对视彩蛋
    @State private var index: Int = 0
    /// 上一题号（翻卡方向感知用）
    @State private var previousShownIndex: Int = 0
    @State private var finished: Bool = false
    /// 对视倒计时（秒）
    @State private var gazeRemaining: Int?
    @State private var gazeTimer: Timer?
    /// 进度记忆：上次练到的题号（0-35），翻题自动保存，完成对视后清零
    @AppStorage("nio_dating_36q_progress") private var savedProgress: Int = 0
    @State private var showResumeBanner = false

    private var setIndex: Int { min(index / 12, 2) }
    private var set: NIODating36Questions.QuestionSet { NIODating36Questions.sets[setIndex] }
    private var questionInSet: Int { index % 12 }

    var body: some View {
        NavigationStack {
            ZStack {
                themeService.backgroundPrimary().ignoresSafeArea()

                if finished {
                    eyeGazeSection
                        .transition(.opacity)
                } else {
                    questionSection
                        .transition(.opacity)
                }
            }
            .navigationTitle("Aron 36 问")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        gazeTimer?.invalidate()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(sakuraPink)
                }
            }
            // 兜底：sheet 被编程式关闭时停掉倒计时，防止 Timer 空转持有视图状态
            .onDisappear { gazeTimer?.invalidate() }
            // 进度记忆：进入时检测上次练到的题号，翻题时自动保存
            .onAppear {
                if savedProgress > 0, savedProgress < 36 {
                    showResumeBanner = true
                }
            }
            .onChange(of: index) { _, newIndex in
                savedProgress = newIndex
            }
        }
    }

    // MARK: 翻题区

    private var questionSection: some View {
        VStack(spacing: 16) {
            // 组徽章 + 全局进度
            HStack {
                Text(set.title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)))
                Spacer()
                Text("\(index + 1) / 36")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                    .monospacedDigit()
            }

            Text(set.subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NIOThemePaint.well)
                    Capsule()
                        .fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(index + 1) / 36)
                        .animation(NIOThemeMotion.easeSmooth, value: index)
                }
            }
            .frame(height: 6)

            // 接续提示：36 问可分多次完成，重开时从上次题号继续
            if showResumeBanner {
                resumeBanner
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 理论依据（默认折叠，与看板/理论页同源）
            NIODatingEvidenceDisclosure(text: NIODatingEvidence.aron36)

            Spacer(minLength: 4)

            // 题卡
            VStack(spacing: 14) {
                Text("第 \(index + 1) 问")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(lavenderDream)

                Text(set.questions[questionInSet])
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .id(index) // 切题时重建并播放翻卡过渡
                    .transition(
                        index > previousShownIndex
                            ? .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.94))
                            )
                            : .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.94))
                            )
                    )

                Label("两人都回答 —— 轮流作答比抢答更能生成亲近感", systemImage: "person.2")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.55))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(NIOThemePaint.fill)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(sakuraPink.opacity(0.25), lineWidth: 1))
            )
            .shadow(color: sakuraPink.opacity(0.10), radius: 14, y: 6)
            .animation(NIOThemeMotion.themeSpring, value: index)

            Spacer(minLength: 4)

            // 翻题按钮
            HStack(spacing: 10) {
                if index > 0 {
                    Button {
                        withAnimation(NIOThemeMotion.layoutSpring) {
                            previousShownIndex = index
                            index -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(NIOThemePaint.fill))
                    }
                    .buttonStyle(NIOPressableButtonStyle())
                }

                Button {
                    if index >= 35 {
                        gazeTimer?.invalidate()
                        gazeRemaining = NIODating36Questions.eyeGazeSeconds
                        savedProgress = 0 // 完成全部 36 问，进度记忆清零
                        withAnimation(NIOThemeMotion.themeSpring) { finished = true }
                    } else {
                        withAnimation(NIOThemeMotion.layoutSpring) {
                            previousShownIndex = index
                            index += 1
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(index >= 35 ? "完成 36 问 ✨" : "下一问")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if index < 35 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                    )
                }
                .buttonStyle(NIOPressableButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
    }

    // MARK: 进度接续横幅

    private var resumeBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("🔖").font(.system(size: 13))
                Text("上次练到第 \(savedProgress + 1) 问")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Text("渐近式练习可分次完成")
                    .font(.system(size: 9))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.4))
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(NIOThemeMotion.layoutSpring) {
                        previousShownIndex = savedProgress
                        index = savedProgress
                        showResumeBanner = false
                    }
                } label: {
                    Text("接续上次")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(NIOPressableButtonStyle())

                Button {
                    savedProgress = 0
                    withAnimation(NIOThemeMotion.layoutSpring) { showResumeBanner = false }
                } label: {
                    Text("从头开始")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(NIOThemePaint.well))
                }
                .buttonStyle(NIOPressableButtonStyle())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(NIOThemePaint.fill)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(sakuraPink.opacity(0.25), lineWidth: 1))
        )
    }

    // MARK: 对视彩蛋（第 36 题后）

    private var eyeGazeSection: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("😮‍💨 → 👀")
                .font(.system(size: 40))
                .padding(.bottom, 4)

            Text("最后一环 · 四分钟对视")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing)
                )

            Text("原始实验的收尾：两个人安静地对视四分钟——可以聊天，也可以什么都不说。研究表明，这是整个流程里最容易被记住的时刻。")
                .font(.system(size: 12))
                .foregroundStyle(NIOThemePaint.text.opacity(0.65))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .fixedSize(horizontal: false, vertical: true)

            if let remaining = gazeRemaining, remaining > 0 {
                ZStack {
                    Circle()
                        .stroke(NIOThemePaint.stroke, lineWidth: 10)
                        .frame(width: 150, height: 150)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(NIODating36Questions.eyeGazeSeconds))
                        .stroke(
                            LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(NIOThemePaint.text)
                        .monospacedDigit()
                }
                .onAppear { startGazeTimer() }

                Button("跳过对视") {
                    gazeTimer?.invalidate()
                    gazeRemaining = nil
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NIOThemePaint.text.opacity(0.5))
            } else if gazeRemaining == 0 {
                // 对视完成状态（修复：原实现停在 0:00 空圆环，无完成反馈）
                VStack(spacing: 10) {
                    Text("🎉")
                        .font(.system(size: 44))
                    Text("四分钟到了")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)
                    Text("如果此刻你们还在聊个不停——这正是这份练习想要的结局")
                        .font(.system(size: 11))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("回到题目") {
                        gazeRemaining = nil
                        index = 35
                        withAnimation(NIOThemeMotion.themeSpring) { finished = false }
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(sakuraPink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(sakuraPink.opacity(0.12)))
                    .padding(.top, 4)
                }
            } else {
                Button {
                    gazeRemaining = NIODating36Questions.eyeGazeSeconds
                    startGazeTimer()
                } label: {
                    Text("开始四分钟 ⏳")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 220)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(NIOPressableButtonStyle())

                Button("回到题目") {
                    index = 35
                    withAnimation(NIOThemeMotion.themeSpring) { finished = false }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NIOThemePaint.text.opacity(0.5))
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
    }

    private func startGazeTimer() {
        gazeTimer?.invalidate()
        gazeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard let remaining = gazeRemaining else {
                timer.invalidate()
                return
            }
            if remaining <= 1 {
                timer.invalidate()
                gazeRemaining = 0
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                gazeRemaining = remaining - 1
            }
        }
    }
}
