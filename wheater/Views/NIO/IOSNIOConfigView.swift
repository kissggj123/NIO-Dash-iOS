//
//  IOSNIOConfigView.swift
//  wheater
//
//  蔚来看板 iOS 配置与设置界面（二次元萌动科技风 🌸🐰✨）
//

import SwiftUI

@MainActor
struct IOSNIOConfigView: View {
    @ObservedObject var service = NIOService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var smartInput = ""
    @State private var showSuccessBanner = false
    @State private var testStatusText: String?
    @State private var isTesting = false
    @State private var showLogsSheet = false
    @State private var showAboutSheet = false
    @State private var showReleaseNotesSheet = false
    @AppStorage("nio_prefer_actual_range") private var preferActualRange = false
    @ObservedObject private var themeService = AnimeThemeService.shared
    @AppStorage("nio_vehicle_selected_model") private var selectedModelSlug = "et5_special"
    @AppStorage("nio_vehicle_selected_color") private var selectedColorSlug = "nature_wonder"

    // 二次元萌系主题色（跟随全局主题实时刷新）
    private var sakuraPink: Color { themeService.accentColor() }
    private var lavenderDream: Color { Color(hex: themeService.currentToken.gradientEnd) }
    private var mintCyan: Color { themeService.glowColor() }
    private var pastelYellow: Color { themeService.warmAccentColor() }
    // 省电动效（关闭流光 / 浮动等常驻动画）
    @AppStorage("nio_reduced_fx") private var reducedFx = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                animeBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 1. 顶部 Header
                        configHeaderView

                        // 2. 🎨 动漫主题风格与粒子特效
                        themeSelectorCard

                        // 3. 🚘 爱车车型与车漆涂装定制
                        carModelSelectorCard

                        // 4. ⚡️ 智能识别与一键填充
                        smartParseCard

                        // 5. 🚗 核心车辆 API (必填)
                        vehicleApiCard

                        // 6. 📑 扩展服务 (换电 & 签到)
                        extraServicesCard

                        // 7. ⏱️ 调度与连通性测试
                        scheduleAndTestCard

                        // 8. 📱 抓取指引
                        sniffGuideCard

                        // 9. 🌸 软件关于与诊断
                        aboutAndLogsSection

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("蔚来看板设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(sakuraPink)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button(action: { showReleaseNotesSheet = true }) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(pastelYellow)
                        }

                        Button(action: { showLogsSheet = true }) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(mintCyan)
                        }

                        Button(action: { showAboutSheet = true }) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(lavenderDream)
                        }
                    }
                }
            }
            .sheet(isPresented: $showLogsSheet) {
                IOSNIOFetchLogView()
            }
            .sheet(isPresented: $showAboutSheet) {
                IOSAboutView()
            }
            .sheet(isPresented: $showReleaseNotesSheet) {
                IOSReleaseNotesView()
            }
        }
    }

    // MARK: - 1. 顶部 Header

    private var configHeaderView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [sakuraPink, lavenderDream], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: sakuraPink.opacity(0.4), radius: 8)

                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(NIOThemePaint.text)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("参数与同步配置")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Text("配置蔚来 API Token 与灵动岛实时监控调度")
                    .font(.system(size: 11))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))
            }
            Spacer()
        }
        .padding(12)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 2. 🎨 主题风格卡片（三系七主题 · 分类分组 + 色板预览）

    private var themeSelectorCard: some View {
        cardContainer(title: "🎨 主题外观风格", icon: "paintpalette.fill", accentColor: sakuraPink) {
            VStack(alignment: .leading, spacing: 12) {
                Text("七大主题 · 二次元 / 简洁 / 酷，浅色深色全适配，灵动岛同步换装：")
                    .font(.system(size: 11))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.7))

                ForEach(AnimeThemeCategory.allCases) { category in
                    let styles = AnimeThemeStyle.allCases.filter { $0.category == category }

                    VStack(alignment: .leading, spacing: 8) {
                        // 分类标题
                        HStack(spacing: 5) {
                            Image(systemName: category.categoryIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(sakuraPink)
                            Text(category.displayName)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                            Rectangle()
                                .fill(NIOThemePaint.stroke)
                                .frame(height: 0.8)
                        }

                        // 主题色板网格
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(styles) { style in
                                themeSwatchButton(style)
                            }
                        }
                    }
                }

                // 省电动效开关
                Toggle(isOn: $reducedFx) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🔋 省电动效模式")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NIOThemePaint.text)
                        Text("关闭流光能量槽、车辆浮动等常驻动画，降低耗电与 GPU 占用")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                    }
                }
                .tint(sakuraPink)
            }
        }
    }

    /// 单个主题色板选择按钮（渐变预览球 + 名称 + 浅/深标记）
    private func themeSwatchButton(_ style: AnimeThemeStyle) -> some View {
        let isSelected = (themeService.currentStyle == style)
        let token = AnimeThemeToken.preset(named: style.rawValue)

        return Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                themeService.setStyle(style)
            }
        }) {
            VStack(spacing: 5) {
                // 渐变色板预览球
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: token.gradientStart), Color(hex: token.gradientEnd)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: Color(hex: token.accentColor).opacity(isSelected ? 0.55 : 0.25), radius: isSelected ? 7 : 4)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 2)

                // 名称
                Text(style.displayName)
                    .font(.system(size: 10, weight: isSelected ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? sakuraPink : NIOThemePaint.text.opacity(0.8))
                    .lineLimit(1)

                // 浅 / 深标记
                Text(token.isDark ? "深色" : "浅色")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(token.isDark ? Color.black.opacity(0.35) : sakuraPink.opacity(0.14))
                    .foregroundStyle(token.isDark ? NIOThemePaint.text.opacity(0.65) : sakuraPink)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 4)
            .background(isSelected ? sakuraPink.opacity(0.12) : NIOThemePaint.fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? sakuraPink.opacity(0.7) : NIOThemePaint.stroke, lineWidth: isSelected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.category.displayName)主题 \(style.displayName)")
    }

    // MARK: - 3. 🚘 爱车车型与涂装配置卡片

    private var carModelSelectorCard: some View {
        cardContainer(title: "🚘 爱车车型与涂装车漆", icon: "car.side.fill", accentColor: pastelYellow) {
            VStack(alignment: .leading, spacing: 12) {
                // 特别版切换开关 / 默认
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    selectedModelSlug = "et5_special"
                    selectedColorSlug = "nature_wonder"
                }) {
                    HStack {
                        Image("NIO_brand")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                        Text("2026款 ET5 · 自然奇境版 (特别版)")
                            .font(.system(size: 12, weight: selectedModelSlug == "et5_special" ? .bold : .medium))
                            .foregroundStyle(selectedModelSlug == "et5_special" ? pastelYellow : NIOThemePaint.text.opacity(0.85))
                        Spacer()
                        if selectedModelSlug == "et5_special" {
                            Text("当前激活 ✨")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(pastelYellow)
                        }
                    }
                    .padding(10)
                    .background(selectedModelSlug == "et5_special" ? pastelYellow.opacity(0.15) : NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedModelSlug == "et5_special" ? pastelYellow.opacity(0.6) : NIOThemePaint.stroke, lineWidth: 1))
                }

                Divider().background(NIOThemePaint.stroke)

                Text("或从蔚来全系官方车系中选择：")
                    .font(.system(size: 11))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.6))

                // 车型选择 Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NIOVehicleModelLib.models) { model in
                            let isModelSelected = (selectedModelSlug == model.slug)
                            Button(action: {
                                selectedModelSlug = model.slug
                                if let firstColor = model.colors.first {
                                    selectedColorSlug = firstColor.slug
                                }
                            }) {
                                Text(model.name)
                                    .font(.system(size: 11, weight: isModelSelected ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isModelSelected ? mintCyan.opacity(0.3) : NIOThemePaint.fill)
                                    .foregroundStyle(isModelSelected ? mintCyan : NIOThemePaint.text.opacity(0.8))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(isModelSelected ? mintCyan : NIOThemePaint.stroke, lineWidth: 1))
                            }
                        }
                    }
                }

                // 选中车型的颜色选择
                if let currentModel = NIOVehicleModelLib.findModel(by: selectedModelSlug) {
                    Text("选择【\(currentModel.name)】官方车漆颜色：")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mintCyan)
                        .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(currentModel.colors) { color in
                            let isColorSelected = (selectedColorSlug == color.slug)
                            Button(action: {
                                selectedColorSlug = color.slug
                            }) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(LinearGradient(colors: [sakuraPink, mintCyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 8, height: 8)
                                    Text(color.name)
                                        .font(.system(size: 10, weight: isColorSelected ? .bold : .regular))
                                        .foregroundStyle(isColorSelected ? .white : NIOThemePaint.text.opacity(0.75))
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(isColorSelected ? sakuraPink.opacity(0.3) : NIOThemePaint.fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isColorSelected ? sakuraPink : NIOThemePaint.stroke, lineWidth: 1))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 4. 智能识别与一键填充

    private var smartParseCard: some View {
        cardContainer(title: "⚡️ 智能识别与一键填充", icon: "wand.and.stars", accentColor: mintCyan) {
            VStack(alignment: .leading, spacing: 10) {
                Text("将抓包 URL、cURL、或嗅探脚本输出的文本直接粘贴到下方：")
                    .font(.system(size: 11))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.7))

                ZStack(alignment: .topLeading) {
                    if smartInput.isEmpty {
                        Text("在此粘贴抓包链接或 cURL 命令…")
                            .font(.system(size: 12))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.25))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $smartInput)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(NIOThemePaint.text)
                        .tint(NIOThemePaint.text)
                        .padding(6)
                        .frame(height: 65)
                        .background(NIOThemePaint.well)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 10) {
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        if let clip = UIPasteboard.general.string {
                            smartInput = clip
                            applySmartParse()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.system(size: 12))
                            Text("剪贴板读取并识别")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [mintCyan.opacity(0.8), mintCyan], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundStyle(Color.black)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        applySmartParse()
                    }) {
                        Text("开始解析")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(NIOThemePaint.stroke)
                            .foregroundStyle(NIOThemePaint.text)
                            .clipShape(Capsule())
                    }
                    .disabled(smartInput.isEmpty)
                }

                if showSuccessBanner {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("参数解析成功，已自动填充并启动调度！🌸")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - 3. 车辆 API 必填 (支持 URL 模式 & Widget 动态签名模式)

    private var vehicleApiCard: some View {
        cardContainer(title: "1. 车辆状态 API (必填)", icon: "car.side.fill", accentColor: sakuraPink) {
            VStack(alignment: .leading, spacing: 10) {
                // 模式切换
                VStack(alignment: .leading, spacing: 4) {
                    Text("接口调用模式")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(sakuraPink)

                    HStack(spacing: 8) {
                        Button(action: { service.nioVehicleApiMode = "url" }) {
                            HStack(spacing: 4) {
                                Image(systemName: service.nioVehicleApiMode != "widget" ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 10))
                                Text("🔗 完整 URL 模式")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(service.nioVehicleApiMode != "widget" ? sakuraPink.opacity(0.25) : NIOThemePaint.fill)
                            .foregroundStyle(service.nioVehicleApiMode != "widget" ? sakuraPink : NIOThemePaint.text.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(service.nioVehicleApiMode != "widget" ? sakuraPink : NIOThemePaint.stroke, lineWidth: 1))
                        }

                        Button(action: { service.nioVehicleApiMode = "widget" }) {
                            HStack(spacing: 4) {
                                Image(systemName: service.nioVehicleApiMode == "widget" ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 10))
                                Text("⚡️ Widget 签名模式")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(service.nioVehicleApiMode == "widget" ? mintCyan.opacity(0.25) : NIOThemePaint.fill)
                            .foregroundStyle(service.nioVehicleApiMode == "widget" ? mintCyan : NIOThemePaint.text.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(service.nioVehicleApiMode == "widget" ? mintCyan : NIOThemePaint.stroke, lineWidth: 1))
                        }
                    }
                }

                if service.nioVehicleApiMode == "widget" {
                    // Widget 动态签名模式参数
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vehicle ID (车辆 ID)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(mintCyan)

                        TextField("如 17位VIN 或 9位车辆ID", text: $service.nioVehicleId)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .background(NIOThemePaint.well)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device ID (设备 ID)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(mintCyan)

                        TextField("抓包中的 device_id", text: $service.nioDeviceId)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .background(NIOThemePaint.well)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sign Secret (签名密钥)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(mintCyan)

                        SecureField("动态签名密钥，填入后每次自动生成有效签名", text: $service.nioVehicleSignSecret)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .background(NIOThemePaint.well)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("签名算法")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(mintCyan)
                            Spacer()
                        }

                        Menu {
                            Button("MD5 (Query + Secret) [推荐]") {
                                service.nioVehicleSignAlgo = "md5_append"
                            }
                            Button("MD5 (Secret + Query)") {
                                service.nioVehicleSignAlgo = "md5_prepend"
                            }
                            Button("MD5 (Query + &key=Secret)") {
                                service.nioVehicleSignAlgo = "md5_append_key"
                            }
                        } label: {
                            HStack {
                                Text(algoDisplayName(service.nioVehicleSignAlgo))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(NIOThemePaint.text)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(mintCyan)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(NIOThemePaint.well)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                        }
                    }

                    Text("💡 提示：普通抓包只能截获每次请求已生成的 sign，无法直接抓到 App 内置的 sign_secret。常规使用推荐切回【🔗 完整 URL 模式】直接一键粘贴即可；若已获取动态密钥则填入本模式享受永久签名。")
                        .font(.system(size: 9))
                        .foregroundStyle(pastelYellow.opacity(0.85))
                        .lineSpacing(2)
                } else {
                    // 直连抓包 URL 模式
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API URL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(sakuraPink)

                        TextField("https://icar.nio.com/api/2/rvs/vehicle/.../status", text: $service.nioVehicleApiURL)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .background(NIOThemePaint.well)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token (Bearer)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(sakuraPink)

                    SecureField("Bearer 2.0.xxxx...", text: $service.nioVehicleAccessToken)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(NIOThemePaint.well)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Text(service.nioVehicleApiMode == "widget" ? "⚡️ 动态 Widget 签名模式每次拉取自动生成当前时间戳与 MD5 校验码，长期运行永不失效。" : "💡 包含车辆电量、续航、7门车锁、4轮胎压、座舱温度及实时 GPS。")
                    .font(.system(size: 9))
                    .foregroundStyle(NIOThemePaint.text.opacity(0.5))
            }
        }
    }

    // MARK: - 4. 扩展服务 (换电 & 签到)

    private var extraServicesCard: some View {
        cardContainer(title: "2. 换电与签到 API (可选)", icon: "bolt.badge.clock.fill", accentColor: lavenderDream) {
            VStack(alignment: .leading, spacing: 12) {
                // 换电
                VStack(alignment: .leading, spacing: 4) {
                    Text("换电记录 API URL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(lavenderDream)

                    TextField("https://app.nio.com/app/api/charge/power_swap/order/list", text: $service.nioChangeApiURL)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(NIOThemePaint.well)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("换电 Token (留空则复用车辆 Token)", text: $service.nioChangeAccessToken)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(NIOThemePaint.well)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Divider().background(NIOThemePaint.stroke)

                // 签到
                VStack(alignment: .leading, spacing: 4) {
                    Text("每日签到 API URL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(lavenderDream)

                    TextField("https://app.nio.com/app/api/checkin/today", text: $service.nioCheckinApiURL)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(NIOThemePaint.well)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("签到 Token (留空则复用车辆 Token)", text: $service.nioCheckinAccessToken)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(NIOThemePaint.well)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(NIOThemePaint.stroke, lineWidth: 0.8))
                            .foregroundStyle(NIOThemePaint.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        }
    }

    // MARK: - 5. 调度与连通性测试

    private var scheduleAndTestCard: some View {
        cardContainer(title: "⏱️ 定时调度与连通测试", icon: "arrow.triangle.2.circlepath", accentColor: pastelYellow) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $service.nioIsAutoPollEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开启后台定时自动拉取")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NIOThemePaint.text)
                        Text("在后台定时更新车况与灵动岛实时数据")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                    }
                }
                .tint(sakuraPink)

                if service.nioIsAutoPollEnabled {
                    HStack {
                        Text("刷新频率")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NIOThemePaint.text)
                        Spacer()
                        Menu {
                            Button("1 分钟") { service.nioVehiclePollIntervalSeconds = 60 }
                            Button("3 分钟") { service.nioVehiclePollIntervalSeconds = 180 }
                            Button("5 分钟 (推荐)") { service.nioVehiclePollIntervalSeconds = 300 }
                            Button("10 分钟") { service.nioVehiclePollIntervalSeconds = 600 }
                        } label: {
                            HStack(spacing: 4) {
                                Text(pollIntervalDisplayName(service.nioVehiclePollIntervalSeconds))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(mintCyan)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(mintCyan.opacity(0.7))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NIOThemePaint.fill)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(8)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider().background(NIOThemePaint.stroke)

                // 电量里程首选实估
                Toggle(isOn: $preferActualRange) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🎯 电量里程默认首选实估")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NIOThemePaint.text)
                        Text("主看板与灵动岛/锁屏将默认优先展示实际估算续航，标准续航作为副标展示")
                            .font(.system(size: 9))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.55))
                    }
                }
                .tint(sakuraPink)
                .onChange(of: preferActualRange) { _ in
                    service.updateLiveActivity()
                }

                Button(action: testConnection) {
                    HStack {
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .tint(.black)
                                .padding(.trailing, 6)
                        }
                        Text(isTesting ? "正在拉取车况…" : "⚡️ 立即测试 API 连通性")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [pastelYellow, sakuraPink], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isTesting || !service.isConfigured)

                if let res = testStatusText {
                    HStack(spacing: 6) {
                        Image(systemName: res.contains("成功") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        Text(res)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(res.contains("成功") ? Color.green : Color.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(res.contains("成功") ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - 6. 抓取指引

    private var sniffGuideCard: some View {
        cardContainer(title: "📱 手机端与局域网抓取指引", icon: "questionmark.circle.fill", accentColor: .cyan) {
            VStack(alignment: .leading, spacing: 8) {
                guideStepRow(num: "1", text: "在同一局域网运行 Mac 端 `sniff.sh` 抓包脚本或手机抓包工具（Stream / Surge / QX）。")
                guideStepRow(num: "2", text: "打开手机【蔚来 App -> 爱车】下拉刷新车况。")
                guideStepRow(num: "3", text: "筛选域名 `icar.nio.com`，找到包含 `/status` 的请求。")
                guideStepRow(num: "4", text: "复制 cURL 或输出并点击上方【从剪贴板读取并识别】，一秒完成！")

                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    NIOVehicleLib.openNIOApp()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("一键打开手机蔚来 App 🚀")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(NIOThemePaint.fill)
                    .foregroundStyle(mintCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(mintCyan.opacity(0.3), lineWidth: 0.8))
                }
                .padding(.top, 4)
            }
        }
    }

    private func guideStepRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(NIOThemePaint.stroke)
                    .frame(width: 18, height: 18)
                Text(num)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(mintCyan)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(NIOThemePaint.text.opacity(0.75))
                .lineSpacing(2)
        }
    }

    // MARK: - 7. 软件关于与诊断入口

    private var aboutAndLogsSection: some View {
        VStack(spacing: 10) {
            Button(action: { showReleaseNotesSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .foregroundStyle(pastelYellow)
                    Text("版本更新日志 (Release Notes)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.8.0")")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(mintCyan)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(NIOThemePaint.fill)
                .foregroundStyle(NIOThemePaint.text)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(pastelYellow.opacity(0.3), lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button(action: { showAboutSheet = true }) {
                    HStack(spacing: 6) {
                        Text("🌸")
                        Text("关于 YumikoToys")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(NIOThemePaint.fill)
                    .foregroundStyle(NIOThemePaint.text)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(sakuraPink.opacity(0.3), lineWidth: 1))
                }

                Button(action: { showLogsSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("运行诊断日志")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(NIOThemePaint.fill)
                    .foregroundStyle(mintCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(mintCyan.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - 通用卡片容器

    private func cardContainer<Content: View>(
        title: String,
        icon: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NIOThemePaint.text)
                Spacer()
            }

            content()
        }
        .padding(14)
        .background(NIOThemePaint.fill)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NIOThemePaint.fill, lineWidth: 1))
    }

    // MARK: - 逻辑操作

    private func applySmartParse() {
        if service.smartParseInput(smartInput) {
            withAnimation { showSuccessBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { showSuccessBanner = false }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testStatusText = nil
        Task {
            await service.fetchVehicle()
            isTesting = false
            if let err = service.lastError {
                testStatusText = "连通失败：\(err)"
            } else {
                testStatusText = "连通成功！已同步最新车况数据 🌸"
            }
        }
    }

    private func algoDisplayName(_ algo: String) -> String {
        switch algo {
        case "md5_append": return "MD5 (Query + Secret) [推荐]"
        case "md5_prepend": return "MD5 (Secret + Query)"
        case "md5_append_key": return "MD5 (Query + &key=Secret)"
        default: return algo
        }
    }

    private func pollIntervalDisplayName(_ sec: Int) -> String {
        switch sec {
        case 60: return "1 分钟"
        case 180: return "3 分钟"
        case 300: return "5 分钟 (推荐)"
        case 600: return "10 分钟"
        default: return "\(sec / 60) 分钟"
        }
    }

    // MARK: - 背景

    private var animeBackground: some View {
        ZStack {
            themeService.backgroundPrimary()

            RadialGradient(
                colors: [sakuraPink.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 280
            )

            RadialGradient(
                colors: [lavenderDream.opacity(0.16), Color.clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 300
            )
        }
    }
}

// MARK: - 诊断日志视图 (美化版)

struct IOSNIOFetchLogView: View {
    @ObservedObject var service = NIOService.shared
    @ObservedObject private var themeService = AnimeThemeService.shared
    @Environment(\.dismiss) private var dismiss

    private var sakuraPink: Color { themeService.accentColor() }
    private var mintCyan: Color { themeService.glowColor() }

    var body: some View {
        NavigationStack {
            ZStack {
                themeService.backgroundPrimary().ignoresSafeArea()

                if service.fetchLogs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 36))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.3))
                        Text("暂无运行日志")
                            .font(.system(size: 13))
                            .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(service.fetchLogs) { log in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Label(log.category.uppercased(), systemImage: log.level == "error" ? "xmark.circle.fill" : "checkmark.circle.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(log.level == "error" ? Color.red : mintCyan)
                                        Spacer()
                                        Text(NIOVehicleLib.fmtTime(Int(log.timestamp.timeIntervalSince1970 * 1000)))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(NIOThemePaint.text.opacity(0.4))
                                    }
                                    Text(log.message)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(NIOThemePaint.text.opacity(0.9))

                                    if let url = log.requestURL {
                                        Text(url)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(NIOThemePaint.text.opacity(0.5))
                                            .lineLimit(2)
                                    }

                                    if let preview = log.responsePreview {
                                        Text(preview)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(NIOThemePaint.text.opacity(0.7))
                                            .lineLimit(3)
                                            .padding(6)
                                            .background(NIOThemePaint.well)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                .padding(10)
                                .background(NIOThemePaint.fill)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("运行诊断日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(themeService.backgroundPrimary(), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(sakuraPink)
                }
            }
        }
    }
}
