# 🐰 YumikoToysRR for NIO (iOS) · 二次元智能蔚来看板与灵动岛实时监控

<p align="center">
  <img src="wheater/Assets.xcassets/AppIcon.appiconset/1024.png" alt="YumikoToys Logo" width="110" height="110" style="border-radius: 22px;">
</p>

<p align="center">
  <strong>专为蔚来车主打造的二次元萌动艺术风车况看板 · 灵动岛 (Dynamic Island) 与锁屏实时活动 (Live Activity) 智能助理</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2016.1%2B-blue?style=flat-square&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-100%25-green?style=flat-square" alt="SwiftUI">
  <img src="https://img.shields.io/badge/ActivityKit-Live%20Activity-purple?style=flat-square" alt="ActivityKit">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="License">
</p>

---

## ✨ 核心特性

- 🔋 **全维动力电池诊断与估算**：
  - 高压动力电池 SOC 实时精准电量与满电标称容量推算（支持 75kWh / 100kWh / 150kWh 电池包自适应识别）；
  - CLTC 标称工况续航与实际估算（WLTP 风格真实工况，智能推算系数）双模自适应无缝切换；
  - 12V 铅酸 / 磷酸铁锂低压辅助电瓶实时电量百分比与工作电压监控。
- 📈 **能耗达成率与百公里电耗评分**：
  - 达成率实时智能计算，车辆休眠未上报实际估算时由内置引擎智能兜底；
  - 百公里真实电耗评分、满电实际可用续航预测与节能驾驶评级。
- 🏝️ **灵动岛 (Dynamic Island) 与实时活动 (Live Activity)**：
  - 息屏/锁屏即时查看电量、续航、车锁状态、充电功率与充满倒计时；
  - 展开区直观呈现 4 轮胎压数值、车内外温差、车载冰箱、守卫模式告警数与车机固件版本胶囊；
  - 高性能后台节流与去重指纹机制，极低系统功耗。
- 🔧 **维保周期与耗材寿命追踪**：
  - 空调滤芯、制动液（刹车油）、空调干燥剂、齿轮箱油等耗材寿命与维保倒计时。
- 🅿️ **高精停车位置与坐标纠偏**：
  - 高德 GCJ-02 与 WGS-84 地球坐标精准校准转换，一键唤起 Apple 地图 / 高德地图寻车导航。
- ❄️ **座舱舒适与车载电器**：
  - 车载智能冰箱温控、对外放电 (V2L)、守卫模式、宠物模式、露营模式状态全景监控。
- 🎨 **二次元萌动艺术与像素主题**：
  - 内置兔可可专属粉、赛博蓝、暗夜极光等多款艺术主题，支持 120 FPS 丝滑变色与像素开屏动效。

---

## 🌲 项目结构 (Directory Tree)

```text
YumikoToysRR-Weather/
├── WheaterStatus/                      # 灵动岛 (Dynamic Island) 与锁屏实时活动 Widget 扩展
│   ├── WheaterStatus.swift             # 实时活动 UI 渲染（紧凑岛、展开岛、锁屏大卡片）
│   ├── WheaterStatus.intentdefinition  # WidgetKit 意图配置
│   ├── Info.plist                      # Widget 扩展权限配置
│   └── Assets.xcassets                 # 小组件专属素材与颜色令牌
├── wheater/                            # iOS 主应用程序源码
│   ├── Model/                          # 数据模型与核心算法库
│   │   ├── NIO/
│   │   │   ├── NIOModels.swift         # 蔚来 API 数据结构定义 (SOC/车门/空调/胎压/维保等)
│   │   │   ├── NIOVehicleLib.swift     # 电池容量推算、坐标纠偏、达成率算法与主题令牌
│   │   │   ├── NIOOrderLib.swift       # 换电/维保订单账单解析库
│   │   │   └── NIOCheckinLib.swift     # 车主每日签到与积分统计
│   │   └── WheaterAttributes.swift     # 跨进程 Live Activity 数据通信契约与指纹去重
│   ├── ViewModel/                      # 业务逻辑与网络服务
│   │   └── NIOService.swift            # 蔚来开放协议通信、后台轮询、灵动岛生命周期管理
│   ├── Views/                          # SwiftUI 视图组件层
│   │   ├── NIO/
│   │   │   ├── IOSNIODashboardView.swift    # 蔚来全景车况大屏主看板
│   │   │   ├── IOSNIOConfigView.swift       # 车机凭证配置、抓包解析与连通性测试
│   │   │   ├── IOSAboutView.swift           # 关于兔可可、功能矩阵与致谢页面
│   │   │   └── NIOPixelLaunchSplashView.swift # 像素风开屏启动动效
│   │   └── ContentView.swift           # App 根路由与全局主题渲染上下文
│   ├── Resources/                      # 静态资源库
│   │   ├── Brand/                      # 蔚来品牌 Logo 与矢量矢量图
│   │   └── Cars/                       # 10 款全系蔚来车型高清 3D 渲染图与车身色库
│   └── wheaterApp.swift                # iOS 应用程序主入口
└── YumikoToysRR.xcodeproj              # Xcode 完整工程配置与多 Target 架构
```

---

## 📖 快速上手与使用说明 (Getting Started)

### 1. 编译与运行环境
- **开发工具**：Xcode 15.0 或更高版本
- **系统要求**：iOS 16.1+（支持 Live Activity 与灵动岛的设备体验更佳）
- **步骤**：
  1. 克隆代码并在 Xcode 中打开 `YumikoToysRR.xcodeproj`；
  2. 在 `Signing & Capabilities` 中配置您的开发者证书与 Bundle Identifier；
  3. 选择 `YumikoToysRR` Scheme，连接 iPhone 真机并运行安装。

### 2. 获取蔚来车机凭证 (Token)
本应用通过蔚来官方 App 开放车况接口获取数据，可通过以下任意方式获取凭证：
- **抓包提取**：使用手机抓包工具（如 Charles / Thor / mitmproxy）捕获蔚来 App 请求：
  - 域名：`app.nio.com`
  - 路径：包含 `/charge_status`、`/door_status` 等
  - 复制请求头中的 `Authorization: Bearer <Your_Token>` 字符串。
- **配置录入**：
  - 打开 App，点击右上角设置图标进入 **车机连接配置**；
  - 粘贴抓取的完整 cURL 请求或仅填入 Bearer Token，系统会自动解析并校验格式；
  - 点击 **测试连接**，若各项车况正常返回即配置成功。

### 3. 启用灵动岛与锁屏实时活动
1. 进入 iOS **系统设置** -> 找到 **YumikoToysRR**；
2. 确保已开启 **实时活动 (Live Activities)** 权限；
3. 在 App 设置中开启 **驻车/行车自动启动灵动岛** 选项，即可在锁屏与灵动岛全天候常驻监控车况。

---

## 🛠️ 技术架构

- **UI 渲染**：SwiftUI（100% 声明式原生组件，支持 120 FPS 高刷）
- **实时活动**：ActivityKit + WidgetKit
- **架构模式**：MVVM + Clean Architecture 分层架构
- **数据保活**：基于后台推送与自适应节流指纹对比算法

---

## 🙏 致谢与灵感来源 (Acknowledgements)

本项目在接口逆向、数据结构设计与车况监控逻辑上深受以下优秀的开源项目启发，在此致以诚挚的感谢：

- [real3841/NIO-Dash](https://github.com/real3841/NIO-Dash) - 优秀的蔚来车况仪表板与数据可视化方案
- [genelee26/ha-nio](https://github.com/genelee26/ha-nio) - 蔚来车辆 Home Assistant 集成插件与 API 协议参考

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 协议开源。
