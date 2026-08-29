//
//  IOSAboutView.swift
//  wheater
//
//  关于 YumikoToys（iOS 蔚来萌动智能车况看板 & 灵动岛实时助理 🌸🐰✨）
//

import SwiftUI

@MainActor
struct IOSAboutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeService = AnimeThemeService.shared

    // 主题色系（跟随全局主题实时刷新）
    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }
    private var mintCyan: Color { themeService.glowColor() }
    private var pastelYellow: Color { themeService.warmAccentColor() }

    // 动态读取版本号与构建号
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        ?? "4.8.0"
    }

    private var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        ?? (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
        ?? "2700"
    }

    // 交互状态
    @State private var tapCount = 0
    @State private var easterEggText: String?
    @State private var isIconBouncing = false
    @State private var expandedCredit: String?
    @State private var showReleaseNotesSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景深邃暗夜渐变
                animeBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // 1. App 萌神 Hero 头部
                        heroHeader

                        // 2. 蔚来次元愿景卡片
                        visionQuoteCard

                        // 3. 版本更新日志入口卡片
                        releaseNotesEntryCard

                        // 4. Dramatis Personae 功勋名录
                        dramatisPersonaeCard

                        // 5. 神器核心机能矩阵
                        featuresCard

                        // 6. 运行环境与设备信息
                        deviceInfoCard

                        // 底部署名
                        footerSign
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("关于 YumikoToysRR")
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
            .sheet(isPresented: $showReleaseNotesSheet) {
                IOSReleaseNotesView()
            }
        }
    }

    // MARK: - 1. App 萌神 Hero 头部

    private var heroHeader: some View {
        VStack(spacing: 12) {
            // 可爱兔兔大头像（带点击彩蛋）
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [sakuraPink.opacity(0.4), lavenderDream.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 65
                        )
                    )
                    .frame(width: 130, height: 130)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [sakuraPink, lavenderDream],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: sakuraPink.opacity(0.6), radius: 16)
                    .scaleEffect(isIconBouncing ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isIconBouncing)

                Text("🐰")
                    .font(.system(size: 48))
                    .scaleEffect(isIconBouncing ? 1.2 : 1.0)
            }
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                tapCount += 1
                isIconBouncing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isIconBouncing = false
                }

                if tapCount == 1 {
                    easterEggText = "被你戳到了喵！💖"
                } else if tapCount == 3 {
                    easterEggText = "兔可可为你守护爱车每一公里~ 🌸"
                } else if tapCount == 5 {
                    easterEggText = "✨ 注入超能电量魔晶能量中…"
                } else if tapCount >= 7 {
                    easterEggText = "👑 恭喜解锁隐藏称号：蔚来次元领航员！"
                }
            }

            if let egg = easterEggText {
                Text(egg)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(pastelYellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(NIOThemePaint.stroke)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 4) {
                Text("YumikoToysRR for NIO")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NIOThemePaint.text, sakuraPink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("蔚来萌动智能车况看板 & 灵动岛实时助理")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(lavenderDream)

                HStack(spacing: 6) {
                    Text("Version \(appVersion)")
                    Text("•")
                    Text("Build \(appBuild)")
                    Text("•")
                    Text("Live Activity Ready")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 2. 蔚来次元愿景卡片 (专注文档与看板)

    private var visionQuoteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("🌟")
                    .font(.system(size: 14))
                Text("“星辰为途，以电为引，千里征程风驰电掣！”")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [sakuraPink, lavenderDream],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Spacer()
            }

            Text("YumikoToysRR for NIO 是一个因为蔚来app不好用而重新打造的二次元艺术风智能车况看板与灵动岛实时监控助理。汇聚全维动力电池诊断、低压 12V 蓄电池监控、FOTA 车机固件、车载智能冰箱与空气健康、4 轮胎压温控、停车高精度纠偏寻车导航、座舱高温超强干燥与换电全景财务大屏，让每一次出行与驻车都充满二次元萌动科技之美！")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(NIOThemePaint.text.opacity(0.82))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [sakuraPink.opacity(0.4), lavenderDream.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - 3. 版本更新日志入口卡片

    private var releaseNotesEntryCard: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            showReleaseNotesSheet = true
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(mintCyan.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(mintCyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("版本更新日志")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NIOThemePaint.text)
                        Text("v\(appVersion)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(mintCyan.opacity(0.2))
                            .foregroundStyle(mintCyan)
                            .clipShape(Capsule())
                    }
                    Text("查看全新 FOTA、换电大屏、Widget 签名模式与优化记录")
                        .font(.system(size: 10))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.4))
            }
            .padding(12)
            .background(NIOThemePaint.fill)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(mintCyan.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Dramatis Personae 功勋名录

    private var dramatisPersonaeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎭 Dramatis Personae")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
                Text("功勋名录")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(lavenderDream)
            }

            VStack(spacing: 10) {
                creditRow(
                    roleKey: "artificer",
                    roleName: "The Grand Artificer",
                    roleCn: "伟大之工匠",
                    author: "@🍊蜜柑工具人",
                    tagline: "“以铁血铸就逻辑城邦，夜以继日斩尽千百 Bug，使车况高塔永不倒塌。”",
                    allusion: "《麦克白》第一幕第二场：‘Brave Macbeth — well he deserves that name!’（勇敢的麦克白——他当得起这个称号！）"
                )

                creditRow(
                    roleKey: "limner",
                    roleName: "The Limner of the Sigil",
                    roleCn: "徽记描绘者",
                    author: "@会拧头的ruarua怪",
                    tagline: "“洗不净手中极彩墨迹，以神笔抹去世间平庸，赐予蔚来看板华美绝伦之霓裳。”",
                    allusion: "《麦克白》第五幕第一场：‘Out, damned spot!... All the perfumes of Arabia will not sweeten this little hand.’（洗掉，该死墨迹！阿拉伯所有香料都洗不净这只手。）"
                )

                creditRow(
                    roleKey: "chronomancer",
                    roleName: "The Chronomancer",
                    roleCn: "星象守时者",
                    author: "@🐰兔可可",
                    tagline: "“恪守星辰之轨，使时间与车况分秒必争，灵动岛与锁屏活动永无毫厘差池。”",
                    allusion: "《麦克白》第二幕第一场：‘The moon is down; I have not heard the clock.’（月已下沉，我未闻钟响。）"
                )

                creditRow(
                    roleKey: "cleanpark_leopard",
                    roleName: "The Sovereign of Clean Park",
                    roleCn: "净泊雪原领主",
                    author: "@Clean Park里的雪豹",
                    tagline: "“驾驭 2026款 ET5 自然奇境穿梭于 Clean Park 净界雪原，执掌超能电能与灵动车况，令千里征途风驰电掣、永不止息。”",
                    allusion: "《麦克白》第一幕第二场：‘Like valour\'s minion carved out his passage.’（宛如英勇之化身，斩开前进之路！）"
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NIOThemePaint.stroke, lineWidth: 1)
                )
        )
    }

    private func creditRow(
        roleKey: String,
        roleName: String,
        roleCn: String,
        author: String,
        tagline: String,
        allusion: String
    ) -> some View {
        let isExpanded = expandedCredit == roleKey

        return VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    expandedCredit = isExpanded ? nil : roleKey
                }
            }) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(roleName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(mintCyan)
                            Text("(\(roleCn))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        }
                        Text(author)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(sakuraPink)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(lavenderDream)
                }
            }
            .buttonStyle(.plain)

            Text(tagline)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                .lineSpacing(2)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📖 莎翁典籍溯源：")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(pastelYellow)
                    Text(allusion)
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                        .italic()
                }
                .padding(8)
                .background(NIOThemePaint.well)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 5. 神器核心机能矩阵

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✨ 核心全景机能套件")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                featureBadge(icon: "🏝️", title: "灵动岛 & 实时活动", subtitle: "锁屏与灵动岛实时监控")
                featureBadge(icon: "⚡️", title: "全维电池 & 12V电瓶", subtitle: "功率/达成率/电瓶诊断")
                featureBadge(icon: "🚪", title: "雪豹海獭车门锁闭", subtitle: "7 门全景动态结界")
                featureBadge(icon: "🛞", title: "4 轮萌爪胎压监测", subtitle: "实时胎压与胎温网格")
                featureBadge(icon: "♨️", title: "超强干燥与座舱温控", subtitle: "极速除霜/制冷制热/干燥")
                featureBadge(icon: "📑", title: "换电足迹财务大屏", subtitle: "累计花费与站点排行榜")
                featureBadge(icon: "📍", title: "高精度寻车导航", subtitle: "WGS-84/苹果/高德导航")
                featureBadge(icon: "🔐", title: "Widget 动态签名", subtitle: "动态 MD5 签名长期不失效")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NIOThemePaint.stroke, lineWidth: 1)
                )
        )
    }

    private func featureBadge(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(icon)
                .font(.system(size: 18))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(NIOThemePaint.text.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 6. 运行环境与设备信息

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📱 设备与环境")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text)

            HStack {
                Text("软件版本")
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                Spacer()
                Text("v\(appVersion) (\(appBuild))")
                    .foregroundStyle(mintCyan)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .font(.system(size: 11))

            Divider().background(NIOThemePaint.stroke)

            HStack {
                Text("系统平台")
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                Spacer()
                Text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                    .foregroundStyle(NIOThemePaint.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 11))

            Divider().background(NIOThemePaint.stroke)

            HStack {
                Text("设备型号")
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                Spacer()
                Text(UIDevice.current.model)
                    .foregroundStyle(NIOThemePaint.text)
                    .font(.system(size: 11, weight: .medium))
            }
            .font(.system(size: 11))

            Divider().background(NIOThemePaint.stroke)

            HStack {
                Text("引擎架构")
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
                Spacer()
                Text("SwiftUI 5.0 + ActivityKit")
                    .foregroundStyle(lavenderDream)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 11))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NIOThemePaint.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NIOThemePaint.stroke, lineWidth: 1)
                )
        )
    }

    // MARK: - 底部署名

    private var footerSign: some View {
        VStack(spacing: 4) {
            Text("YumikoToys © 2026")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(NIOThemePaint.text.opacity(0.4))
            Text("Crafted with 💖 and NIO Passion for Owners")
                .font(.system(size: 9))
                .foregroundStyle(NIOThemePaint.text.opacity(0.3))
        }
        .padding(.top, 6)
    }

    // MARK: - 梦幻背景

    private var animeBackground: some View {
        ZStack {
            themeService.backgroundPrimary()

            RadialGradient(
                colors: [sakuraPink.opacity(0.22), Color.clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 280
            )

            RadialGradient(
                colors: [lavenderDream.opacity(0.2), Color.clear],
                center: .bottomTrailing,
                startRadius: 50,
                endRadius: 320
            )
        }
    }
}

// MARK: - 独立更新日志视图 (Release Notes)

struct IOSReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeService = AnimeThemeService.shared

    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }
    private var mintCyan: Color { themeService.glowColor() }
    private var pastelYellow: Color { themeService.warmAccentColor() }

    var body: some View {
        NavigationStack {
            ZStack {
                themeService.backgroundPrimary().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // v4.8.0
                        versionSection(
                            version: "v4.8.0 (Build 2700)",
                            date: "2026-08",
                            isLatest: true,
                            items: [
                                ("🎨 主题系统 v2 · 全新三系七主题", [
                                    "🐰 二次元系：蜜桃兔兔（浅）、樱夜粉兔（深）、抹茶奶盖（浅）",
                                    "◻️ 简洁系：云石膏（浅）、曜石灰（深），单色克制极简",
                                    "⚡️ 酷系：赛博霓虹（深）、暮光星野（深）",
                                    "🌗 全新浅色主题支持：看板 / 设置 / 关于 / 日志全页面墨字白卡自适应",
                                    "🎨 灵动岛与锁屏实时活动同步跟随主题配色"
                                ]),
                                ("🏝️ 灵动岛与实时活动重做", [
                                    "⚡️ 充电时展示实时功率与免刷新充满倒计时",
                                    "🚨 车窗/车门未关好时锁屏卡片顶部告警条提示",
                                    "🛞 胎压四轮同显并新增 12V 电瓶与冰箱 / V2L 放电状态",
                                    "🎯 展开态重排：电量实估 / 续航双数字 + 模式状态 + 电量进度条"
                                ]),
                                ("🚀 性能优化", [
                                    "📉 灵动岛数据无显著变化时跳过更新，降低系统功耗",
                                    "🧵 轨迹历史 JSON 编码与持久化全部移出主线程",
                                    "⏱️ 缓存全局 DateFormatter，消除高频刷新下的重复创建开销",
                                    "🔋 新增省电动效开关，一键关闭流光与浮动等常驻动画"
                                ])
                            ]
                        )

                        // v4.7.0
                        versionSection(
                            version: "v4.7.0 (Build 2620)",
                            date: "2026-08",
                            isLatest: false,
                            items: [
                                ("🚀 NIO-Dash & ha-nio 全面功能大移植", [
                                    "💻 车机系统与固件 FOTA 版本展示（零件号、上一版本与升级状态）",
                                    "🔋 动力电池全维诊断（实时充电功率 kW、达成率、充电上限、锁电量、V2L 对外放电）",
                                    "⚡️ 低压 12V 蓄电池监控（12V 小电瓶 SOC % 与实时电压监测）",
                                    "🧊 车载智能冰箱（开关状态、当前与目标温度）与 PM2.5 空气质量健康",
                                    "💡 车外灯光与照明系统监测（近光灯、远光灯、示宽灯、双闪警报）",
                                    "📍 停车位置高精度纠偏寻车（WGS-84/GCJ-02、苹果地图/高德地图一键导航寻车）",
                                    "♨️ 暖风座舱超强干燥（高温超强干燥模式、极速除霜、极速制冷制热、座舱过热保护）",
                                    "📑 换电站足迹与财务大屏（累计换电次数、总花费、单次均价、Top 换电站打卡排行榜）"
                                ]),
                                ("🔐 动态 Widget 签名与稳定性", [
                                    "⚡️ 新增 Widget 动态签名模式，每次拉取动态生成时间戳与 MD5 校验码，长期运行永不失效",
                                    "🛠️ 彻底修复了 iOS 报文渲染引发的 EXC_BAD_ACCESS (code=2) 闪退问题",
                                    "🪄 全新升级一键抓包嗅探插件，车况、换电、签到全量一次性一键截取导入"
                                ]),
                                ("🎨 视觉与体验全面进阶", [
                                    "🌸 保留 2026款 ET5 自然奇境特别版，并开放全系 9 大车型与全车漆涂装自由选择",
                                    "✨ 5 大动漫主题系统移植（深空霓虹、日系治愈、赛博二次元、软萌可爱、新海诚）",
                                    "🏝️ 灵动岛与锁屏实时活动毫秒级同步联动",
                                    "⏱️ 优化开屏像素绘制动画时序，更方便截屏分享与后台资源初始化"
                                ])
                            ]
                        )

                        // v4.6.5
                        versionSection(
                            version: "v4.6.5 (Build 2612)",
                            date: "2026-08",
                            isLatest: false,
                            items: [
                                ("⚡️ 蔚来核心数据看板", [
                                    "⚡️ 萌动超能双色电量能量流光槽",
                                    "🚪 雪豹与海獭可爱守护结界（7门车锁动态状态）",
                                    "🛞 4 轮萌爪胎压与温度网格矩阵监测",
                                    "📅 蔚来每日签到与连续连击天数统计",
                                    "🏝️ 首次引入 Live Activity 灵动岛与锁屏实时车况监控"
                                ])
                            ]
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("版本更新日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(sakuraPink)
                }
            }
        }
    }

    private func versionSection(
        version: String,
        date: String,
        isLatest: Bool,
        items: [(category: String, points: [String])]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text(version)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(NIOThemePaint.text)

                    if isLatest {
                        Text("当前最新 ✨")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(sakuraPink)
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(date)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(items, id: \.category) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.category)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(mintCyan)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.points, id: \.self) { pt in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundStyle(lavenderDream)
                                Text(pt)
                                    .font(.system(size: 11))
                                    .foregroundStyle(NIOThemePaint.text.opacity(0.85))
                                    .lineSpacing(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(NIOThemePaint.fill)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isLatest ? sakuraPink.opacity(0.4) : NIOThemePaint.fill, lineWidth: 1)
        )
    }
}

