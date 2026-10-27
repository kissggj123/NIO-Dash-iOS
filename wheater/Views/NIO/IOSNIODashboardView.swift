//
//  IOSNIODashboardView.swift
//  wheater
//
//  A native NIO vehicle dashboard. Data semantics mirror NIO-Dash and ha-nio:
//  a single glanceable overview followed by detailed, read-only telemetry.
//

import SwiftUI
import Vision
import CoreImage.CIFilterBuiltins

/// 主页车型图片模式：纯渐变 / 内置车型图 / 外部导入
enum NIOHeroPhotoMode: String, CaseIterable, Codable, Identifiable {
    case gradient  // 纯主题渐变（默认）
    case builtin   // 内置车型图 (ET5_CleanPark)
    case custom    // 外部导入图片

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gradient: return "纯渐变"
        case .builtin:  return "内置车型图"
        case .custom:   return "外部导入"
        }
    }
}

/// 外部导入车型图的本地存取 + Vision 原生抠图（VNGenerateForegroundInstanceMaskRequest）
enum NIOHeroPhotoStore {
    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("nio_hero_photo.jpg")
    }

    /// 抠图结果缓存（透明 PNG）
    static var cutoutURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("nio_hero_cutout.png")
    }

    static func save(data: Data) throws {
        try data.write(to: fileURL, options: .atomic)
    }

    static func load() -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: cutoutURL)
    }

    static var hasCustomPhoto: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Vision 原生抠图

    /// 加载内置车图的抠图结果（透明背景）；无缓存则后台生成
    static func loadBuiltinCutout() -> UIImage? {
        guard let data = try? Data(contentsOf: cutoutURL) else { return nil }
        return UIImage(data: data)
    }

    /// 用 Vision 前景实例分割把图片主体抠成透明背景（iOS 17+）
    static func generateCutout(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else { return nil }

            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)

            // 用蒙版把主体从背景中分离（CIBlendWithMask → 透明底）
            let input = CIImage(cgImage: cgImage)
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            let filter = CIFilter.blendWithMask()
            filter.inputImage = input
            filter.backgroundImage = CIImage(color: .clear).cropped(to: input.extent)
            filter.maskImage = mask

            let context = CIContext(options: [.cacheIntermediates: false])
            guard let output = filter.outputImage,
                  let outCG = context.createCGImage(output, from: output.extent) else { return nil }
            return UIImage(cgImage: outCG)
        } catch {
            return nil
        }
    }

    /// 生成（或复用）内置车图抠图；失败时回退原图
    static func builtinCutoutOrOriginal() async -> UIImage? {
        if let cached = loadBuiltinCutout() { return cached }
        let original = UIImage(named: "ET5_CleanPark")
        guard let original else { return nil }
        if let cutout = await generateCutout(from: original),
           let png = cutout.pngData() {
            try? png.write(to: cutoutURL, options: .atomic)
            return cutout
        }
        return original
    }
}

/// iPad 特斯拉式侧边栏分类（NavigationSplitView）
private enum NIOSidebarSection: String, CaseIterable, Identifiable {
    case overview      // 概览
    case vehicle       // 车辆详情
    case modes         // 模式与外设
    case energy        // 能量与能耗
    case tyres         // 轮胎与位置
    case trends        // 趋势与轨迹
    case records       // 维保与记录
    case diagnostics   // 同步诊断

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .vehicle: return "车辆详情"
        case .modes: return "模式与外设"
        case .energy: return "能量与能耗"
        case .tyres: return "轮胎与位置"
        case .trends: return "趋势与轨迹"
        case .records: return "维保与记录"
        case .diagnostics: return "同步诊断"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .vehicle: return "car.fill"
        case .modes: return "switch.2"
        case .energy: return "bolt.batteryblock.fill"
        case .tyres: return "circle.circle"
        case .trends: return "chart.xyaxis.line"
        case .records: return "wrench.and.screwdriver.fill"
        case .diagnostics: return "stethoscope"
        }
    }
}

/// iPad 侧栏行样式：统一图标宽度与文字间距，避免宽图标（如车形）贴字
private struct NIOSidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon
                .frame(width: 20)
            configuration.title
        }
    }
}

@MainActor
struct IOSNIODashboardView: View {
    @ObservedObject private var service = NIOService.shared
    @ObservedObject private var themeService = AnimeThemeService.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("nio_home_title") private var homeTitle = "NIO"
    @AppStorage("nio_hero_photo_mode") private var heroPhotoModeRaw = NIOHeroPhotoMode.gradient.rawValue
    @AppStorage("nio_vehicle_selected_model") private var selectedModelSlug = "et5_special"
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var selectedSection: DashboardSection = .overview
    @State private var sidebarSection: NIOSidebarSection? = .overview
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    /// 内置车图抠图结果（Vision 前景分割，透明底，异步生成后替换原图）
    @State private var builtinCutout: UIImage?
    /// 外部导入车图缓存（避免 body 每帧磁盘 IO）
    @State private var customPhoto: UIImage?

    private var heroPhotoMode: NIOHeroPhotoMode {
        NIOHeroPhotoMode(rawValue: heroPhotoModeRaw) ?? .gradient
    }

    // 主题令牌便捷取色（hero 展台辉光用）
    private var accentColor: Color { Color(hex: themeService.currentToken.accentColor) }
    private var glowColor: Color { Color(hex: themeService.currentToken.glowColor) }

    private var status: NIOVehicleStatus? { service.vehicleData?.data?.status }
    private var soc: NIOSocStatus? { status?.socStatus }
    private var isCharging: Bool {
        NIOVehicleLib.isRealCharging(socStatus: soc, offcarStatus: status?.offcarModeStatus)
    }

    var body: some View {
        if sizeClass == .regular && service.isConfigured {
            // iPad / 大屏：特斯拉式侧边栏 + 车辆主区
            splitLayout
        } else {
            navigationStackLayout
        }
    }

    /// iPhone / compact 单列布局（分段器切换）
    private var navigationStackLayout: some View {
        NavigationStack {
            ZStack {
                NIOAppBackground()
                    .ignoresSafeArea()

                if service.isConfigured {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            vehicleHero
                            sectionPicker
                            selectedContent
                            if let error = service.lastError, !error.isEmpty {
                                NIOAlertCard(message: error, action: { showSettings = true })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { await refresh() }
                    .task(id: heroPhotoModeRaw) {
                        switch heroPhotoMode {
                        case .gradient:
                            break
                        case .builtin:
                            builtinCutout = await NIOHeroPhotoStore.builtinCutoutOrOriginal()
                        case .custom:
                            customPhoto = NIOHeroPhotoStore.load()
                        }
                    }
                } else {
                    NIOEmptyState(onConfigure: { showSettings = true })
                        .padding(24)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(homeTitle.isEmpty ? "NIO" : homeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { service.refreshAll(force: true) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isLoadingVehicle)
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                // 设置页可能重新导入/清除了车型图，回来刷新缓存
                if heroPhotoMode == .custom { customPhoto = NIOHeroPhotoStore.load() }
            }) { IOSNIOConfigView() }
            .sheet(isPresented: $showLogs) { IOSNIOFetchLogView() }
        }
    }

    // MARK: - iPad 特斯拉式 Split 布局

    /// 侧边栏（功能分类）+ 详情主区（淡色标题头 + hero 车图 + 上下文卡片）
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List(selection: $sidebarSection) {
                ForEach(NIOSidebarSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .symbolRenderingMode(.monochrome) // 统一 sidebar 图标为主题色（car 图标默认 multicolor，破坏配色）
            .labelStyle(NIOSidebarLabelStyle()) // 图标与文字间距（默认太窄，宽车形图标几乎贴字）
            .toolbar(removing: .sidebarToggle) // 移除侧栏右上角系统玻璃钮，折叠走 detailHeader 自定义钮
            .background(
                // 侧栏淡色染底：与详情主题背景呼应
                Color(hex: themeService.currentToken.backgroundSecondary).opacity(0.55)
                    .ignoresSafeArea()
            )
            .navigationTitle(homeTitle.isEmpty ? "NIO" : homeTitle)
            .safeAreaInset(edge: .bottom) {
                // 侧栏底部连接状态
                HStack(spacing: 6) {
                    Circle()
                        .fill(service.is403Detected ? .red : (service.isLoadingVehicle ? .orange : .green))
                        .frame(width: 7, height: 7)
                    Text(service.is403Detected ? "凭证失效" : (service.isLoadingVehicle ? "同步中…" : "已连接"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        } detail: {
            GeometryReader { geo in
                // Duo 展开态 / iPad 宽屏：卡片双列铺满；侧栏展开或折叠窄屏：单列
                let twoColumns = geo.size.width >= 780

                ZStack {
                    NIOAppBackground()
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            detailHeader
                            vehicleHero
                            sidebarDetailContent(twoColumns: twoColumns)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .frame(maxWidth: twoColumns ? 1040 : 860)
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { await refresh() }
                    .task(id: heroPhotoModeRaw) {
                        switch heroPhotoMode {
                        case .gradient:
                            break
                        case .builtin:
                            builtinCutout = await NIOHeroPhotoStore.builtinCutoutOrOriginal()
                        case .custom:
                            customPhoto = NIOHeroPhotoStore.load()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .sidebarToggle) // 移除系统玻璃折叠按钮，改用自定义标题头
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { service.refreshAll(force: true) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isLoadingVehicle)
                }
            }
            // 大屏：设置全屏呈现（page sheet 宽度固定 ~640，双列布局永远触发不了）
            .fullScreenCover(isPresented: $showSettings, onDismiss: {
                if heroPhotoMode == .custom { customPhoto = NIOHeroPhotoStore.load() }
            }) { IOSNIOConfigView() }
            .sheet(isPresented: $showLogs) { IOSNIOFetchLogView() }
        }
    }

    /// 详情顶部淡色标题条：分类图标+名称，右侧自定义折叠按钮
    private var detailHeader: some View {
        let section = sidebarSection ?? .overview
        return HStack(spacing: 10) {
            // 自定义折叠按钮（替代系统大玻璃钮）
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    splitVisibility = (splitVisibility == .all) ? .detailOnly : .all
                }
            } label: {
                Image(systemName: splitVisibility == .all ? "sidebar.leading" : "sidebar.squares.leading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: themeService.currentToken.accentColor))
                    .frame(width: 30, height: 30)
                    .background(NIOThemePaint.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(NIOThemePaint.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Image(systemName: section.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: themeService.currentToken.accentColor))
            Text(section.title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: themeService.currentToken.textPrimary))
            Spacer()
            Text("\(NIOSidebarSection.allCases.firstIndex(of: section)! + 1)/\(NIOSidebarSection.allCases.count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: themeService.currentToken.textSecondary).opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: themeService.currentToken.gradientStart).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NIOThemePaint.stroke, lineWidth: 1)
        )
    }

    /// 详情主区：按侧栏选择渲染对应卡片组；宽屏拆左右双列
    @ViewBuilder
    private func sidebarDetailContent(twoColumns: Bool) -> some View {
        switch sidebarSection ?? .overview {
        case .overview:
            cardColumns(twoColumns,
                left: { statusCard; energyCard },
                right: { driveCard })
        case .vehicle:
            cardColumns(twoColumns,
                left: { protectionCard },
                right: { cabinCard })
        case .modes:
            cardColumns(twoColumns,
                left: { NIOModesCard(offcar: status?.offcarModeStatus, v2lStatus: soc?.v2lStatus) },
                right: { NIOAccessoriesCard(lvBatt: status?.lvBattStatus, frdg: status?.frdgStatus, heating: status?.heatingStatus, light: status?.lightStatus) })
        case .energy:
            cardColumns(twoColumns,
                left: { energyCard },
                right: { NIOEfficiencyCard(soc: soc, batteryCapacityKwh: service.estimateBatteryCapacityKwh(socStatus: soc)) })
        case .tyres:
            cardColumns(twoColumns,
                left: { tyreCard },
                right: { locationCard })
        case .trends:
            cardColumns(twoColumns,
                left: { NIOHistoryTrendCard(snapshots: service.history, deltas: service.dailyMileageDeltas) },
                right: { NIOTodayTrackCard(path: service.dailyPaths.last) })
        case .records:
            recordsCards
        case .diagnostics:
            diagnosticsCards
        }
    }

    /// 双列包装：宽屏左右两列顶部对齐，窄屏合成单列
    @ViewBuilder
    private func cardColumns<L: View, R: View>(_ enabled: Bool, @ViewBuilder left: () -> L, @ViewBuilder right: () -> R) -> some View {
        if enabled {
            HStack(alignment: .top, spacing: 16) {
                left()
                    .frame(maxWidth: .infinity, alignment: .top)
                right()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            VStack(spacing: 14) {
                left()
                right()
            }
        }
    }

    private var vehicleHero: some View {
        ZStack(alignment: .bottomLeading) {
            // 车型图层（依设置：内置图 / 外部导入 / 纯渐变）
            heroPhotoLayer

            // 渐变遮罩：纯渐变模式满铺；图片模式垂直渐变（顶部浓保文字、底部透出车形）
            heroOverlay

            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 260, height: 260)
                .offset(x: 130, y: -95)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(vehicleName)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 5) {
                            Image(systemName: isCharging ? "bolt.fill" : vehicleStateIcon)
                            Text(vehicleStateLabel)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isCharging ? .green : .white.opacity(0.68))
                    }
                    Spacer()
                    if service.isLoadingVehicle {
                        ProgressView().tint(.white)
                    } else {
                        // 连接状态点 + 更新时间（原导航栏徽章迁入，避免 toolbar 挤压截断）
                        HStack(spacing: 5) {
                            Circle()
                                .fill(service.is403Detected ? .red : .green)
                                .frame(width: 6, height: 6)
                            Text(lastUpdatedLabel)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        .lineLimit(1)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(soc.map { String(format: "%.0f", $0.soc ?? 0) } ?? "--")
                        .font(.system(size: 68, weight: .thin, design: .rounded))
                    Text("%")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(rangeText(soc?.remainingRange))
                            .font(.title3.weight(.semibold))
                        Text("CLTC 续航")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(isCharging ? Color.green : themeService.accentColor())
                            .frame(width: max(6, proxy.size.width * CGFloat(min(1, max(0, (soc?.soc ?? 0) / 100)))))
                    }
                }
                .frame(height: 6)

                HStack(spacing: 0) {
                    HeroMetric(title: "实估续航", value: rangeText(soc?.remainingActualRange))
                    HeroMetric(title: "总里程", value: mileageText)
                    HeroMetric(title: isCharging ? "充电功率" : "车辆状态", value: isCharging ? powerText : vehicleStateLabel, trailing: true)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
    }

    /// 车型图片层：内置资产 / 外部导入照片 / 无（纯渐变兜底）
    @ViewBuilder
    private var heroPhotoLayer: some View {
        switch heroPhotoMode {
        case .gradient:
            Color(hex: themeService.currentToken.gradientEnd)
        case .builtin:
            // Vision 抠图就绪前显示纯渐变（避免黑底原图压在渐变上生硬突兀）
            if let cutout = builtinCutout {
                // 透明车形 + 底部展台辉光：像展厅灯箱一样托住车身
                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [accentColor.opacity(0.42), glowColor.opacity(0.16), Color.clear],
                                center: .center,
                                startRadius: 8,
                                endRadius: 170
                            )
                        )
                        .frame(width: 330, height: 92)
                        .blur(radius: 14)
                        .offset(y: 6)

                    Image(uiImage: cutout)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .offset(x: -4, y: 10)
                        .shadow(color: accentColor.opacity(0.35), radius: 18, y: 6)
                }
            } else {
                Color(hex: themeService.currentToken.gradientEnd)
            }
        case .custom:
            if let image = customPhoto {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 未导入图片时兜底为渐变
                LinearGradient(
                    colors: [Color(hex: themeService.currentToken.gradientStart), Color(hex: themeService.currentToken.gradientEnd)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    /// 遮罩层：纯渐变模式满铺对角渐变；图片模式顶部浓、底部淡，文字清晰且车形透出
    @ViewBuilder
    private var heroOverlay: some View {
        if heroPhotoMode == .gradient {
            LinearGradient(
                colors: [Color(hex: themeService.currentToken.gradientStart), Color(hex: themeService.currentToken.gradientEnd)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: themeService.currentToken.gradientStart).opacity(0.9), location: 0),
                    .init(color: Color(hex: themeService.currentToken.gradientStart).opacity(0.4), location: 0.48),
                    .init(color: Color(hex: themeService.currentToken.gradientEnd).opacity(0.34), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var sectionPicker: some View {
        Picker("看板", selection: $selectedSection) {
            ForEach(DashboardSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .overview: overview
        case .vehicle: vehicleDetail
        case .insights: insights
        }
    }

    // MARK: - 可复用卡片（iPhone 分段与 iPad 侧栏共用）

    private var statusCard: some View {
        NIOSectionCard(title: "当前状态", subtitle: "来自车辆实时遥测") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatusTile(icon: "lock.fill", title: "车锁", value: isLocked ? "已上锁" : "未上锁", tint: isLocked ? .green : .orange)
                StatusTile(icon: "door.left.hand.open", title: "车门", value: allDoorsClosed ? "已关好" : "请检查", tint: allDoorsClosed ? .green : .orange)
                StatusTile(icon: "window.vertical.open", title: "车窗", value: windowsClosed ? "已关闭" : "有开启", tint: windowsClosed ? .green : .orange)
                StatusTile(icon: "thermometer.medium", title: "座舱温度", value: temperatureText, tint: .cyan)
            }
        }
    }

    private var energyCard: some View {
        NIOSectionCard(title: "能量", subtitle: isCharging ? "正在充电" : "电池与续航") {
            VStack(spacing: 0) {
                KeyValueRow(label: "充电状态", value: NIOVehicleLib.smartChargeStateDescription(socStatus: soc, offcarStatus: status?.offcarModeStatus))
                Divider()
                KeyValueRow(label: "目标电量", value: soc?.targetSocPercentage.map { String(format: "%.0f%%", $0) } ?? "--")
                Divider()
                KeyValueRow(label: "电池锁定下限", value: soc?.lockSoc.map { String(format: "%.0f%%", $0) } ?? "--")
            }
        }
    }

    private var driveCard: some View {
        NIOSectionCard(title: "行驶", subtitle: "来自 RVS exterior status") {
            VStack(spacing: 0) {
                KeyValueRow(label: "当前车速", value: status?.exteriorStatus?.speed.map { String(format: "%.0f km/h", $0) } ?? "--")
                Divider()
                KeyValueRow(label: "行驶状态", value: vehicleStateLabel)
                Divider()
                KeyValueRow(label: "数据采样", value: sampleTimeLabel)
            }
        }
    }

    private var vehicleProtectionCards: some View {
        VStack(spacing: 14) {
            protectionCard
            cabinCard
        }
    }

    private var protectionCard: some View {
        NIOSectionCard(title: "车辆防护", subtitle: "门、窗与连接状态") {
                let entries = NIOVehicleLib.parseAvailableDoors(doorStatus: status?.doorStatus, windowStatus: status?.windowStatus)
                VStack(spacing: 0) {
                    ForEach(entries) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .frame(width: 22)
                                .foregroundStyle(item.isClosed ? .green : .orange)
                            Text(item.title)
                            Spacer()
                            Text(item.isClosed ? "正常" : "注意")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(item.isClosed ? .green : .orange)
                        }
                        .padding(.vertical, 10)
                        if item.id != entries.last?.id { Divider() }
                    }
                }
            }
    }

    private var cabinCard: some View {
        NIOSectionCard(title: "座舱与系统", subtitle: "空调、车机与低压电瓶") {
            VStack(spacing: 0) {
                KeyValueRow(label: "空调", value: status?.hvacStatus?.airConditionerOn == true ? "已开启" : "已关闭")
                Divider()
                KeyValueRow(label: "车外温度", value: degreeText(status?.hvacStatus?.outsideTemperature))
                Divider()
                KeyValueRow(label: "车机版本", value: fotaDisplay)
                Divider()
                KeyValueRow(label: "云端连接", value: status?.connectionStatus?.connected == true ? "在线" : "状态未知")
            }
        }
    }

    private var recordsCards: some View {
        VStack(spacing: 14) {
            NIOSectionCard(title: "行驶记录", subtitle: "基于本地历史采样") {
                HStack {
                    InsightMetric(value: "\(service.history.count)", label: "历史采样")
                    Divider().frame(height: 38)
                    InsightMetric(value: "\(service.dailyPaths.count)", label: "行驶日期")
                    Divider().frame(height: 38)
                    InsightMetric(value: "\(service.dailyMileageDeltas.count)", label: "里程记录")
                }
            }
            NIOSectionCard(title: "服务与换电", subtitle: "订单同步数据") {
                HStack {
                    InsightMetric(value: "\(service.serviceSummary?.swapCompleted ?? 0)", label: "已完成换电")
                    Divider().frame(height: 38)
                    InsightMetric(value: "\(service.serviceSummary?.total ?? 0)", label: "服务订单")
                    Divider().frame(height: 38)
                    InsightMetric(value: checkinValue, label: "连续签到")
                }
            }

            NIOMaintenanceCard(mileageKm: status?.exteriorStatus?.mileage, orders: service.recentOrders)
        }
    }

    private var diagnosticsCards: some View {
        VStack(spacing: 14) {
            if let error = service.lastError, !error.isEmpty {
                NIOAlertCard(message: error, action: { showSettings = true })
            }
            if telemetryWarning != nil {
                NIOSectionCard(title: "遥测诊断", subtitle: "RVS 状态请求字段检查") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(telemetryWarning!, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("请在 NIO App 的爱车页下拉刷新后，重新抓取完整的 /rvs/vehicle/.../status 请求；不要修改 URL 的 field、参数顺序或 sign。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("打开配置") { showSettings = true }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            NIOSectionCard(title: "同步诊断", subtitle: "最近请求与响应记录") {
                Button { showLogs = true } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("查看同步日志")
                        Spacer()
                        Text("\(service.fetchLogs.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var overview: some View {
        VStack(spacing: 14) {
            statusCard
            energyCard
            NIOEfficiencyCard(soc: soc, batteryCapacityKwh: service.estimateBatteryCapacityKwh(socStatus: soc))
            NIOModesCard(offcar: status?.offcarModeStatus, v2lStatus: soc?.v2lStatus)
            NIOAccessoriesCard(
                lvBatt: status?.lvBattStatus,
                frdg: status?.frdgStatus,
                heating: status?.heatingStatus,
                light: status?.lightStatus
            )
            tyreCard
            locationCard
        }
    }

    private var tyreCard: some View {
        // Do not use NIOVehicleLib.extractTyreInfo(from:) here: its deliberate
        // 2.5 bar preview fallback is useful for a widget layout, but would make
        // a missing RVS `tyre` block look like live vehicle data in the app.
        let tyres = NIOVehicleLib.extractTyreInfo(status?.tyreStatus)
        return NIOSectionCard(title: "轮胎", subtitle: "胎压与胎温") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                TyreTile(position: "左前", item: tyres.fl)
                TyreTile(position: "右前", item: tyres.fr)
                TyreTile(position: "左后", item: tyres.rl)
                TyreTile(position: "右后", item: tyres.rr)
            }
        }
    }

    @ViewBuilder
    private var locationCard: some View {
        if let position = status?.positionStatus,
           let latitude = position.latitude,
           let longitude = position.longitude,
           NIOVehicleLib.isValidGPS(lat: latitude, lng: longitude) {
            NIOSectionCard(title: "车辆位置", subtitle: "定位数据可能存在延迟") {
                Link(destination: URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("在地图中查看位置")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(String(format: "%.5f, %.5f", latitude, longitude))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain) // 避免默认 tint 样式压缩/叠印 label
            }
        }
    }

    private var vehicleDetail: some View {
        VStack(spacing: 14) {
            vehicleProtectionCards
            driveCard
        }
    }

    private var insights: some View {
        VStack(spacing: 14) {
            NIOHistoryTrendCard(snapshots: service.history, deltas: service.dailyMileageDeltas)

            NIOTodayTrackCard(path: service.dailyPaths.last)

            recordsCards
            diagnosticsCards
        }
    }

    private func refresh() async {
        await service.fetchVehicle(force: true)
        await service.fetchChange(force: true)
        await service.fetchCheckin(force: true)
        service.updateLiveActivity()
    }

    private var vehicleName: String {
        // 跟随设置页选择的车型名称；特别版单独映射，其余走官方车型库
        if selectedModelSlug == "et5_special" { return "ET5 · 自然奇境版" }
        if let model = NIOVehicleModelLib.findModel(by: selectedModelSlug) {
            return model.name
        }
        return status?.vehicleId.map { "NIO \($0.suffix(6))" } ?? "我的 NIO"
    }
    private var isLocked: Bool { (status?.doorStatus?["vehicle_lock_status"]?.intValue ?? 1) == 1 }
    private var allDoorsClosed: Bool { NIOVehicleLib.parseAvailableDoors(doorStatus: status?.doorStatus, windowStatus: nil).filter { $0.id != "vehicle_lock" }.allSatisfy(\.isClosed) }
    private var windowsClosed: Bool { NIOVehicleLib.parseAvailableDoors(doorStatus: nil, windowStatus: status?.windowStatus).first { $0.id == "windows" }?.isClosed ?? true }
    private var mileageText: String { status?.exteriorStatus?.mileage.map { String(format: "%.0f km", $0) } ?? "--" }
    private var powerText: String { soc?.chargingPower.map { String(format: "%.1f kW", $0 / ($0 > 100 ? 1000 : 1)) } ?? "--" }
    private var temperatureText: String { degreeText(status?.hvacStatus?.temperature) }
    private var checkinValue: String { service.checkinData.map { "\($0.continuousDays) 天" } ?? "--" }
    private var fotaDisplay: String {
        let fota = status?.fotaStatus
        let raw = [fota?.currentVersion, fota?.lastVersion, fota?.currentPartNo]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let raw else { return "未返回" }
        return NIOVehicleLib.parseFotaInfo(version: raw).fullDisplay
    }
    private var telemetryWarning: String? {
        let tyreMissing = !NIOVehicleLib.extractTyreInfo(status?.tyreStatus).hasData
        let fotaMissing = status?.fotaStatus?.currentVersion?.isEmpty != false
            && status?.fotaStatus?.lastVersion?.isEmpty != false
        switch (tyreMissing, fotaMissing) {
        case (true, true): return "当前请求未返回胎压和车机版本"
        case (true, false): return "当前请求未返回胎压数据"
        case (false, true): return "当前请求未返回车机版本"
        case (false, false): return nil
        }
    }
    private var sampleTimeLabel: String { dateLabel(status?.socStatus?.sampleTime ?? status?.exteriorStatus?.sampleTime) }
    private var lastUpdatedLabel: String { service.lastVehicleFetch.map { $0.formatted(date: .omitted, time: .shortened) } ?? "未同步" }
    private var vehicleStateIcon: String { status?.exteriorStatus?.vehicleState == 1 ? "steeringwheel" : "parkingsign" }
    private var vehicleStateLabel: String { status?.exteriorStatus?.vehicleState == 1 ? "行驶中" : "已驻车" }
    private func rangeText(_ value: Double?) -> String { value.map { String(format: "%.0f km", $0) } ?? "--" }
    private func degreeText(_ value: Double?) -> String { value.map { String(format: "%.0f℃", $0) } ?? "--" }
    private func dateLabel(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, vehicle, insights
    var id: String { rawValue }
    var title: String { switch self { case .overview: "概览"; case .vehicle: "车辆"; case .insights: "记录" } }
}

private struct NIOAppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [AnimeThemeService.shared.backgroundPrimary(), AnimeThemeService.shared.backgroundSecondary()],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct NIOEmptyState: View {
    let onConfigure: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "car.2.fill").font(.system(size: 44)).foregroundStyle(Color(red: 0.11, green: 0.54, blue: 0.48))
            Text("连接你的 NIO").font(.title2.weight(.semibold))
            Text("粘贴从 NIO App 获取的车辆状态 URL 和 Access Token，即可在这里查看实时车况。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("开始配置", action: onConfigure).buttonStyle(.borderedProminent).tint(Color(red: 0.10, green: 0.48, blue: 0.42))
        }
    }
}

private struct NIOAlertCard: View {
    let message: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Image(systemName: "exclamationmark.triangle.fill"); Text(message).lineLimit(2); Spacer(); Image(systemName: "chevron.right") }
                .font(.subheadline).foregroundStyle(.orange).padding(14).background(.orange.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct NIOSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            content
        }
        .padding(16).background(NIOThemePaint.fill).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct HeroMetric: View {
    let title: String; let value: String; var trailing = false
    var body: some View { VStack(alignment: trailing ? .trailing : .leading, spacing: 2) { Text(value).font(.subheadline.weight(.semibold)); Text(title).font(.caption2).foregroundStyle(.white.opacity(0.52)) }.frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading) }
}

private struct StatusTile: View {
    let icon: String; let title: String; let value: String; let tint: Color
    var body: some View { HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(tint).frame(width: 20); VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.medium)) }; Spacer() }.padding(12).background(tint.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14)) }
}

private struct KeyValueRow: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing).font(.subheadline.weight(.medium)) }.padding(.vertical, 10) }
}

private struct TyreTile: View {
    let position: String; let item: NIOVehicleLib.TyreWheelInfo
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(position).font(.caption).foregroundStyle(.secondary); Text(item.press.map { String(format: "%.1f bar", $0) } ?? "--").font(.subheadline.weight(.semibold)); Text(item.temp.map { "\($0)℃" } ?? "温度 --").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14)) }
}

private struct InsightMetric: View {
    let value: String; let label: String
    var body: some View { VStack(spacing: 3) { Text(value).font(.title3.weight(.semibold)); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}
