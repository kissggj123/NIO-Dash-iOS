//
//  StargazingWeatherService.swift
//  wheater
//
//  观星行程天气服务：
//  · Open-Meteo 16 天逐时预报 → 分层云量/温度/湿度/露点/风/气压
//  · 7Timer! ASTRO 约 3 天预报 → seeing / transparency / 云量档位
//  均为免 key 免费 API；带内存 + 磁盘双层缓存，避免高频请求打满限额。
//

import Foundation
import CoreLocation

struct StargazingWeatherReport: Codable, Equatable {
    var tripID: String
    var lat: Double
    var lng: Double
    // Open-Meteo（行程窗口切片统计）
    var cloudCoverPct: Double?
    var cloudLowPct: Double?
    var cloudMidPct: Double?
    var cloudHighPct: Double?
    var temperatureC: Double?
    var humidityPct: Double?
    var dewPointC: Double?
    var windSpeedKmh: Double?
    var windDirectionDeg: Double?
    var pressureHpa: Double?
    var openMeteoOK: Bool
    var openMeteoError: String?
    // 7Timer ASTRO（窗口内最近时次）
    var seeingArcsec: Double?
    var seeingText: String?
    var transparencyText: String?
    var astroCloudCoverPct: Double?
    var astroInit: String?
    var astroOK: Bool
    var astroError: String?
    // 日月（sunrisesunset.io 主 + USNO 兜底，任意未来日期可用）
    var moonriseText: String?
    var moonsetText: String?
    var moonIllumPct: Double?
    var moonPhaseText: String?
    var sunriseText: String?
    var sunsetText: String?
    var astroTwilightStartText: String?
    var astroTwilightEndText: String?
    var skyOK: Bool
    var skyError: String?
    // AQI（Open-Meteo Air Quality，观测窗口均值）
    var aqiUS: Double?
    var aqiOK: Bool
    var fetchedAt: Date

    /// Open-Meteo 正常返回但行程日期超出 16 天预报窗口（切片为空）
    var isOutOfForecastRange: Bool {
        openMeteoOK && cloudCoverPct == nil && temperatureC == nil
    }

    /// 一行天气简报（实时活动 / 卡片复用）
    var summaryLine: String {
        var parts: [String] = []
        if let cloud = cloudCoverPct ?? astroCloudCoverPct {
            parts.append("☁️ \(Int(cloud.rounded()))%")
        }
        if let t = temperatureC {
            parts.append(String(format: "%.0f℃", t))
        }
        if let s = seeingText { parts.append("视宁 \(s)") }
        if let t = transparencyText { parts.append("透光 \(t)") }
        if parts.isEmpty { parts.append("暂无数据") }
        return parts.joined(separator: " · ")
    }

    /// 天气矩阵所需六格：值 + 副标题（AQI 附等级）
    var aqiLevelText: String? {
        guard let aqi = aqiUS else { return nil }
        switch aqi {
        case ..<51: return "优"
        case 51...100: return "良"
        case 101...150: return "轻度污染"
        case 151...200: return "中度污染"
        default: return "重度污染"
        }
    }

    var isStale: Bool {
        fetchedAt < Date().addingTimeInterval(-30 * 60)
    }
}

@MainActor
final class StargazingWeatherService: ObservableObject {
    static let shared = StargazingWeatherService()

    @Published var reportByTripID: [String: StargazingWeatherReport] = [:]
    @Published var lastErrorByTripID: [String: String] = [:]

    private static let diskCacheKey = "nio_stargazing_weather_cache"
    private let session: URLSession
    private var inflight: Set<String> = []

    private init() {
        // 显式无代理配置：URLSessionConfiguration.default 会自动继承 iOS 系统
        // 全局代理（设置 → 通用 → VPN 与设备管理 → 代理 / 全局 HTTP 代理），
        // 系统开了代理则 App 请求自动走代理，无需（也不应）手动指定 CFProxy。
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
        loadDiskCache()
    }

    // MARK: - 磁盘缓存

    private func loadDiskCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.diskCacheKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let dict = try? decoder.decode([String: StargazingWeatherReport].self, from: data) {
            reportByTripID = dict
        }
    }

    private func persistDiskCache() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(reportByTripID) {
            UserDefaults.standard.set(data, forKey: Self.diskCacheKey)
        }
    }

    // MARK: - 主入口

    /// 拉取行程观测窗口的天气（30 分钟内缓存直接命中；forceRefresh 手动更新时绕过全部缓存）
    func fetchWeather(for trip: StargazingTrip, location: RecommendedLocation? = nil, forceRefresh: Bool = false) async -> StargazingWeatherReport? {
        let tripID = trip.id
        if forceRefresh {
            // 手动更新：清空日月缓存（天气/AQI 本身不落缓存，inflight 去重在外层控制）
            skyCache.removeAll()
        } else if let cached = reportByTripID[tripID], !cached.isStale {
            return cached
        }
        guard !inflight.contains(tripID) else { return reportByTripID[tripID] }
        inflight.insert(tripID)
        defer { inflight.remove(tripID) }

        let loc = location ?? trip.primaryLocation
        guard let loc else {
            lastErrorByTripID[tripID] = "行程 JSON 中没有可用坐标"
            return nil
        }

        async let openMeteo = fetchOpenMeteo(tripID: tripID, lat: loc.lat, lng: loc.lng,
                                             start: trip.startDate, end: trip.endDate)
        async let astro = fetchSevenTimer(tripID: tripID, lat: loc.lat, lng: loc.lng,
                                          start: trip.startDate, end: trip.endDate)
        async let sky = fetchSky(tripID: tripID, lat: loc.lat, lng: loc.lng,
                                 date: trip.startDate)
        async let aqi = fetchAQI(tripID: tripID, lat: loc.lat, lng: loc.lng,
                                 start: trip.startDate, end: trip.endDate)
        let (om, astroResult, skyResult, aqiResult) = await (openMeteo, astro, sky, aqi)

        var report = om ?? StargazingWeatherReport(
            tripID: tripID, lat: loc.lat, lng: loc.lng,
            openMeteoOK: false, openMeteoError: "Open-Meteo 无响应",
            astroOK: false, skyOK: false, aqiOK: false, fetchedAt: Date())
        if let astroResult {
            report.seeingArcsec = astroResult.seeingArcsec
            report.seeingText = astroResult.seeingText
            report.transparencyText = astroResult.transparencyText
            report.astroCloudCoverPct = astroResult.cloudPct
            report.astroInit = astroResult.init_
            report.astroOK = true
            report.astroError = astroResult.error
        } else {
            report.astroOK = false
            report.astroError = "7Timer 拉取失败（可能超出 3 天预报窗口）"
        }
        if let skyResult {
            report.moonriseText = skyResult.moonrise
            report.moonsetText = skyResult.moonset
            report.moonIllumPct = skyResult.illumination
            report.moonPhaseText = skyResult.phase
            report.sunriseText = skyResult.sunrise
            report.sunsetText = skyResult.sunset
            report.astroTwilightStartText = skyResult.astroStart
            report.astroTwilightEndText = skyResult.astroEnd
            report.skyOK = true
            report.skyError = skyResult.error
        } else {
            report.skyOK = false
            report.skyError = "日月数据拉取失败"
        }
        if let aqiResult {
            report.aqiUS = aqiResult
            report.aqiOK = true
        }
        report.fetchedAt = Date()
        reportByTripID[tripID] = report
        persistDiskCache()
        lastErrorByTripID.removeValue(forKey: tripID)
        return report
    }

    // MARK: - Open-Meteo

    private struct OpenMeteoResponse: Decodable {
        struct Hourly: Decodable {
            var time: [String]
            var temperature_2m: [Double?]?
            var relative_humidity_2m: [Double?]?
            var dew_point_2m: [Double?]?
            var cloud_cover: [Double?]?
            var cloud_cover_low: [Double?]?
            var cloud_cover_mid: [Double?]?
            var cloud_cover_high: [Double?]?
            var wind_speed_10m: [Double?]?
            var wind_direction_10m: [Double?]?
            var surface_pressure: [Double?]?
        }
        var hourly: Hourly?
        var error: Bool?
        var reason: String?
    }

    private func fetchOpenMeteo(tripID: String, lat: Double, lng: Double,
                                start: Date?, end: Date?) async -> StargazingWeatherReport? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", lat)),
            .init(name: "longitude", value: String(format: "%.4f", lng)),
            .init(name: "hourly", value: "temperature_2m,relative_humidity_2m,dew_point_2m,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,wind_speed_10m,wind_direction_10m,surface_pressure"),
            .init(name: "timezone", value: "Asia/Shanghai"),
            .init(name: "forecast_days", value: "16"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw StargazingWeatherError.httpStatus(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            if decoded.error == true {
                throw StargazingWeatherError.apiReason(decoded.reason ?? "unknown")
            }
            guard let hourly = decoded.hourly else { return nil }
            return aggregate(hourly: hourly, start: start, end: end,
                             tripID: tripID, lat: lat, lng: lng)
        } catch let error as StargazingWeatherError {
            lastErrorByTripID[tripID] = error.errorDescription
            return nil
        } catch {
            lastErrorByTripID[tripID] = "Open-Meteo 请求失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 将逐时数组按行程窗口切片求均值
    private func aggregate(hourly: OpenMeteoResponse.Hourly, start: Date?, end: Date?,
                           tripID: String, lat: Double, lng: Double) -> StargazingWeatherReport {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var indices = Array(hourly.time.indices)
        if let start, let end {
            indices = hourly.time.indices.filter { idx in
                guard let t = formatter.date(from: hourly.time[idx]) else { return false }
                return t >= start.addingTimeInterval(-3600) && t <= end.addingTimeInterval(3600)
            }
        }
        func mean(_ values: [Double?]?) -> Double? {
            guard let values else { return nil }
            let picked = indices.compactMap { values[$0] }.filter { $0.isFinite }
            guard !picked.isEmpty else { return nil }
            return picked.reduce(0, +) / Double(picked.count)
        }

        return StargazingWeatherReport(
            tripID: tripID, lat: lat, lng: lng,
            cloudCoverPct: mean(hourly.cloud_cover),
            cloudLowPct: mean(hourly.cloud_cover_low),
            cloudMidPct: mean(hourly.cloud_cover_mid),
            cloudHighPct: mean(hourly.cloud_cover_high),
            temperatureC: mean(hourly.temperature_2m),
            humidityPct: mean(hourly.relative_humidity_2m),
            dewPointC: mean(hourly.dew_point_2m),
            windSpeedKmh: mean(hourly.wind_speed_10m),
            windDirectionDeg: mean(hourly.wind_direction_10m),
            pressureHpa: mean(hourly.surface_pressure),
            openMeteoOK: true,
            astroOK: false,
            skyOK: false,
            aqiOK: false,
            fetchedAt: Date())
    }

    // MARK: - 7Timer! ASTRO

    private struct SevenTimerResponse: Decodable {
        struct DataSeries: Decodable {
            var timepoint: Int
            var cloudcover: Int?
            var seeing: Int?
            var transparency: Int?
            var rh2m: Int?
            var temp2m: Double?
            var prec_type: String?
        }
        var init_: String?
        var dataseries: [DataSeries]?

        private enum CodingKeys: String, CodingKey {
            case init_ = "init"
            case dataseries
        }
    }

    private func fetchSevenTimer(tripID: String, lat: Double, lng: Double,
                                 start: Date?, end: Date?) async -> (seeingArcsec: Double?, seeingText: String?, transparencyText: String?, cloudPct: Double?, init_: String?, error: String?)? {
        var components = URLComponents(string: "https://www.7timer.info/bin/api.pl")!
        components.queryItems = [
            .init(name: "lon", value: String(format: "%.3f", lng)),
            .init(name: "lat", value: String(format: "%.3f", lat)),
            .init(name: "product", value: "astro"),
            .init(name: "output", value: "json"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw StargazingWeatherError.httpStatus(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(SevenTimerResponse.self, from: data)
            guard let series = decoded.dataseries, !series.isEmpty, let init_ = decoded.init_ else { return nil }

            // init 为 UTC yyyymmddHH；timepoint 为起报后的小时数（3h 步进）
            let initFormatter = DateFormatter()
            initFormatter.dateFormat = "yyyyMMddHH"
            initFormatter.timeZone = TimeZone(identifier: "UTC")
            initFormatter.locale = Locale(identifier: "en_US_POSIX")
            let initDate = initFormatter.date(from: init_)

            // 优先取行程窗口内时次；窗口未在预报范围内时取最近时次
            var best: SevenTimerResponse.DataSeries?
            if let initDate, let start, let end {
                best = series
                    .filter { entry in
                        let t = initDate.addingTimeInterval(TimeInterval(entry.timepoint) * 3600)
                        return t >= start && t <= end
                    }
                    .min { abs($0.timepoint) < abs($1.timepoint) }
            }
            if best == nil {
                best = series.min { $0.timepoint < $1.timepoint }
            }
            guard let entry = best else { return nil }

            return (
                seeingArcsec: entry.seeing.flatMap { Self.seeingArcsec(for: $0) },
                seeingText: entry.seeing.flatMap { Self.seeingText(for: $0) },
                transparencyText: entry.transparency.flatMap { Self.transparencyText(for: $0) },
                cloudPct: entry.cloudcover.map { Self.cloudCoverPct(for: $0) },
                init_: init_,
                error: nil
            )
        } catch let error as StargazingWeatherError {
            lastErrorByTripID[tripID] = (lastErrorByTripID[tripID] ?? "") + (error.errorDescription ?? "")
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - 日月 / 晨昏（多源整合：sunrisesunset.io → sunrise-sunset.org + USNO/CycleCalcs → 本地引擎）

    private struct SkyResult {
        var moonrise: String?
        var moonset: String?
        var illumination: Double?
        var phase: String?
        var sunrise: String?
        var sunset: String?
        var astroStart: String?
        var astroEnd: String?
        var error: String?
    }

    /// 日月数据 24 小时缓存（key: date|lat|lng）——日月数据当日不变，无需频繁拉取
    private var skyCache: [String: (result: SkyResult, cachedAt: Date)] = [:]

    private struct SunriseSunsetIOResponse: Decodable {
        struct Results: Decodable {
            var sunrise: String?
            var sunset: String?
            var first_light: String?
            var last_light: String?
            var moonrise: String?
            var moonset: String?
            var moon_phase: String?
            var moon_illumination: Double?
        }
        var status: String?
        var results: Results?
    }

    private struct SunriseSunsetOrgResponse: Decodable {
        var sunrise: String?
        var sunset: String?
        var astronomical_twilight_begin: String?
        var astronomical_twilight_end: String?
    }

    private struct USNOResponse: Decodable {
        struct Properties: Decodable {
            struct Data: Decodable {
                struct Phenomenon: Decodable {
                    var phen: String?
                    var time: String?
                }
                var curphase: String?
                var fracillum: String?
                var moondata: [Phenomenon]?
                var sundata: [Phenomenon]?
            }
            var data: Data?
        }
        var properties: Properties?
    }

    private struct CycleCalcsResponse: Decodable {
        struct Data: Decodable {
            struct Phase: Decodable {
                var name: String?
                var code: String?
                var illumination: Double?
                var illumination_fraction: Double?
            }
            struct RiseSet: Decodable {
                struct Event: Decodable {
                    var kind: String?
                    var instant: String?
                }
                var rise: [String]?
                var set: [String]?
            }
            var phase: Phase?
            var rise_set: RiseSet?
        }
        var data: Data?
    }

    private func fetchSky(tripID: String, lat: Double, lng: Double, date: Date?) async -> SkyResult? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dateText = dateFormatter.string(from: date ?? Date())
        let cacheKey = "\(dateText)|\(String(format: "%.4f", lat))|\(String(format: "%.4f", lng))"

        // 24h 缓存命中
        if let cached = skyCache[cacheKey], Date().timeIntervalSince(cached.cachedAt) < 86400 {
            return cached.result
        }

        var sky = SkyResult()
        var sources: [String] = []

        // ① sunrisesunset.io：日月同源一次拿全
        if let a = await fetchSunriseSunsetIO(lat: lat, lng: lng, dateText: dateText) {
            sky = a
            sources.append("sunrisesunset.io")
        } else {
            // ② sun：sunrise-sunset.org v2（含天文晨昏）；moon：USNO → CycleCalcs
            let sunPart = await fetchSunriseSunsetOrg(lat: lat, lng: lng, dateText: dateText)
            sky.sunrise = sunPart?.sunrise
            sky.sunset = sunPart?.sunset
            sky.astroStart = sunPart?.astroStart
            sky.astroEnd = sunPart?.astroEnd
            if sunPart != nil { sources.append("sunrise-sunset.org") }

            if let moonUSNO = await fetchUSNO(lat: lat, lng: lng, dateText: dateText) {
                sky.moonrise = moonUSNO.moonrise
                sky.moonset = moonUSNO.moonset
                sky.illumination = moonUSNO.illumination
                sky.phase = moonUSNO.phase
                sources.append("USNO")
            } else if let moonCycle = await fetchCycleCalcs(lat: lat, lng: lng, dateText: dateText) {
                sky.moonrise = moonCycle.moonrise
                sky.moonset = moonCycle.moonset
                sky.illumination = moonCycle.illumination
                sky.phase = moonCycle.phase
                sources.append("CycleCalcs")
            }
        }

        // ③ 本地天文引擎兜底补缺（SunCalc 算法，免网络）
        fillFromLocalEngine(&sky, date: date ?? Date(), lat: lat, lng: lng)
        if sky.sunrise != nil || sky.moonrise != nil || sky.astroStart != nil {
            sky.error = sources.isEmpty ? "本地天文引擎（SunCalc 算法近似）" : "来源 \(sources.joined(separator: " + "))"
        } else {
            sky.error = "日月数据不可用"
            return nil
        }
        skyCache[cacheKey] = (sky, Date())
        return sky
    }

    /// 本地引擎补齐 SkyResult 缺失字段
    private func fillFromLocalEngine(_ sky: inout SkyResult, date: Date, lat: Double, lng: Double) {
        let engine = StargazingLocalAstronomy.self
        let sun = engine.sunTimes(date: date, lat: lat, lng: lng)
        let phase = engine.moonPhase(date: date)
        let moon = engine.moonTimes(date: date, lat: lat, lng: lng)

        if sky.sunrise == nil { sky.sunrise = sun.sunrise.map { clockFromDate($0) } }
        if sky.sunset == nil { sky.sunset = sun.sunset.map { clockFromDate($0) } }
        if sky.astroStart == nil { sky.astroStart = sun.astroStart.map { clockFromDate($0) } }
        if sky.astroEnd == nil { sky.astroEnd = sun.astroEnd.map { clockFromDate($0) } }
        if sky.moonrise == nil { sky.moonrise = moon.moonrise.map { clockFromDate($0) } }
        if sky.moonset == nil { sky.moonset = moon.moonset.map { clockFromDate($0) } }
        if sky.illumination == nil { sky.illumination = phase.illuminationFraction * 100 }
        if sky.phase == nil { sky.phase = phase.phaseName }
    }

    /// Date → "HH:mm"（上海时区）
    private func clockFromDate(_ date: Date) -> String {
        let output = DateFormatter()
        output.dateFormat = "HH:mm"
        output.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return output.string(from: date)
    }

    private func fetchSunriseSunsetIO(lat: Double, lng: Double, dateText: String) async -> SkyResult? {
        var components = URLComponents(string: "https://api.sunrisesunset.io/json")!
        components.queryItems = [
            .init(name: "lat", value: String(format: "%.4f", lat)),
            .init(name: "lng", value: String(format: "%.4f", lng)),
            .init(name: "date", value: dateText),
            .init(name: "timezone", value: "Asia/Shanghai"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(SunriseSunsetIOResponse.self, from: data)
            guard let r = decoded.results, decoded.status == "OK" else { return nil }
            return SkyResult(
                moonrise: r.moonrise.map { clockText($0) },
                moonset: r.moonset.map { clockText($0) },
                illumination: r.moon_illumination,
                phase: r.moon_phase,
                sunrise: r.sunrise.map { clockText($0) },
                sunset: r.sunset.map { clockText($0) },
                astroStart: r.first_light.map { clockText($0) },
                astroEnd: r.last_light.map { clockText($0) },
                error: nil)
        } catch {
            return nil
        }
    }

    /// sunrise-sunset.org v2：日出日落 + 天文晨昏（ISO 带时区，取 HH:mm），需署名
    private func fetchSunriseSunsetOrg(lat: Double, lng: Double, dateText: String) async -> (sunrise: String, sunset: String, astroStart: String, astroEnd: String)? {
        var components = URLComponents(string: "https://api.sunrise-sunset.org/v2")!
        components.queryItems = [
            .init(name: "lat", value: String(format: "%.4f", lat)),
            .init(name: "lng", value: String(format: "%.4f", lng)),
            .init(name: "date", value: dateText),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(SunriseSunsetOrgResponse.self, from: data)
            guard let sunrise = decoded.sunrise, let sunset = decoded.sunset,
                  let astroStart = decoded.astronomical_twilight_begin,
                  let astroEnd = decoded.astronomical_twilight_end else { return nil }
            return (clockTextISO(sunrise), clockTextISO(sunset), clockTextISO(astroStart), clockTextISO(astroEnd))
        } catch {
            return nil
        }
    }

    private func fetchUSNO(lat: Double, lng: Double, dateText: String) async -> SkyResult? {
        var components = URLComponents(string: "https://aa.usno.navy.mil/api/rstt/oneday")!
        components.queryItems = [
            .init(name: "date", value: dateText),
            .init(name: "coords", value: String(format: "%.3f,%.3f", lat, lng)),
            .init(name: "tz", value: "8"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(USNOResponse.self, from: data)
            guard let d = decoded.properties?.data else { return nil }
            func phen(_ list: [USNOResponse.Properties.Data.Phenomenon]?, _ name: String) -> String? {
                list?.first { $0.phen == name }?.time
            }
            return SkyResult(
                moonrise: phen(d.moondata, "Rise"),
                moonset: phen(d.moondata, "Set"),
                illumination: d.fracillum.flatMap { Double($0.replacingOccurrences(of: "%", with: "")) },
                phase: d.curphase,
                sunrise: phen(d.sundata, "Rise"),
                sunset: phen(d.sundata, "Set"),
                astroStart: nil,
                astroEnd: nil,
                error: nil)
        } catch {
            return nil
        }
    }

    private func fetchCycleCalcs(lat: Double, lng: Double, dateText: String) async -> SkyResult? {
        var components = URLComponents(string: "https://www.cyclecalcs.com/v2/moon")!
        components.queryItems = [
            .init(name: "lat", value: String(format: "%.4f", lat)),
            .init(name: "lon", value: String(format: "%.4f", lng)),
            .init(name: "date", value: dateText),
            .init(name: "tz", value: "Asia/Shanghai"),
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(CycleCalcsResponse.self, from: data)
            guard let d = decoded.data else { return nil }
            let rise = d.rise_set?.rise?.first.flatMap { clockTextISO($0) }
            let set = d.rise_set?.set?.first.flatMap { clockTextISO($0) }
            let illum = d.phase?.illumination.map { $0 <= 1 ? $0 * 100 : $0 }
                ?? d.phase?.illumination_fraction.map { $0 * 100 }
            return SkyResult(
                moonrise: rise, moonset: set,
                illumination: illum,
                phase: d.phase?.name,
                sunrise: nil, sunset: nil, astroStart: nil, astroEnd: nil,
                error: nil)
        } catch {
            return nil
        }
    }

    /// "6:43:06 AM" → "06:43"
    private func clockText(_ text: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "h:mm:ss a"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: text) else { return text }
        let output = DateFormatter()
        output.dateFormat = "HH:mm"
        output.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return output.string(from: date)
    }

    /// ISO8601 "2026-12-14T06:43:06+08:00" → "06:43"
    private func clockTextISO(_ text: String) -> String {
        if text.count >= 16 {
            let start = text.index(text.startIndex, offsetBy: 11)
            let end = text.index(text.startIndex, offsetBy: 16)
            return String(text[start..<end])
        }
        return text
    }

    // MARK: - AQI（Open-Meteo Air Quality）

    private func fetchAQI(tripID: String, lat: Double, lng: Double, start: Date?, end: Date?) async -> Double? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", lat)),
            .init(name: "longitude", value: String(format: "%.4f", lng)),
            .init(name: "hourly", value: "pm2_5,us_aqi"),
            .init(name: "timezone", value: "Asia/Shanghai"),
        ]
        guard let url = components.url else { return nil }
        struct AQIResponse: Decodable {
            struct Hourly: Decodable {
                var time: [String]
                var us_aqi: [Double?]?
            }
            var hourly: Hourly?
        }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(AQIResponse.self, from: data)
            guard let hourly = decoded.hourly else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.locale = Locale(identifier: "en_US_POSIX")
            var indices = Array(hourly.time.indices)
            if let start, let end {
                indices = hourly.time.indices.filter { idx in
                    guard let t = formatter.date(from: hourly.time[idx]) else { return false }
                    return t >= start.addingTimeInterval(-3600) && t <= end.addingTimeInterval(3600)
                }
                if indices.isEmpty { indices = [Int](hourly.time.indices.prefix(24)) }
            }
            let values = indices.compactMap { hourly.us_aqi?[$0] ?? nil }.filter { $0.isFinite }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        } catch {
            return nil
        }
    }

    // MARK: - 7Timer 档位换算（1 = 最好）

    /// 云量档 1-9 → 百分比区间中值
    static func cloudCoverPct(for level: Int) -> Double {
        let midpoints = [3, 12, 25, 38, 50, 63, 75, 88, 97]
        let idx = max(1, min(9, level)) - 1
        return Double(midpoints[idx])
    }

    /// seeing 档 1-8 → 视宁角秒（越小越好）
    static func seeingArcsec(for level: Int) -> Double? {
        let arcsec = [0.4, 0.65, 0.9, 1.1, 1.4, 1.75, 2.25, 2.8]
        guard (1...8).contains(level) else { return nil }
        return arcsec[level - 1]
    }

    static func seeingText(for level: Int) -> String? {
        guard (1...8).contains(level) else { return nil }
        switch level {
        case 1...2: return "极佳(\(level))"
        case 3...4: return "良好(\(level))"
        case 5...6: return "一般(\(level))"
        default:    return "较差(\(level))"
        }
    }

    static func transparencyText(for level: Int) -> String? {
        guard (1...8).contains(level) else { return nil }
        switch level {
        case 1...2: return "极佳(\(level))"
        case 3...4: return "良好(\(level))"
        case 5...6: return "一般(\(level))"
        default:    return "较差(\(level))"
        }
    }
}

enum StargazingWeatherError: LocalizedError {
    case httpStatus(Int)
    case apiReason(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "天气接口返回 \(code)"
        case .apiReason(let reason):
            if reason.lowercased().contains("limit") {
                return "天气 API 今日限额已满，请稍后重试或改用直连网络"
            }
            return "天气接口错误：\(reason)"
        }
    }
}
