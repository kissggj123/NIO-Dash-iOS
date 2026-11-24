//
//  StargazingLocalAstronomy.swift
//  wheater
//
//  本地天文引擎（SunCalc 算法移植，BSD 授权算法，免 API 兜底）：
//  · 太阳升落 + 民用/航海/天文晨昏（NOAA 近似）
//  · 月出月落（逐 10 分钟高度扫描）、月相/照度
//  · 辐射点 alt/az（配合 RadiantAstrometry）
//  另含 IMO 流星雨静态年历（ZHR/极大/辐射点赤经赤纬）
//  与 Bortle 光污染静态地图值兜底。
//  iOS 开启全局代理时 URLSession 默认配置自动走系统代理，无需额外处理。
//

import Foundation

enum StargazingLocalAstronomy {

    // MARK: - 基础

    private static let rad = Double.pi / 180
    private static let dayMs = 86400000.0
    private static let j1970 = 2440588.0
    private static let j2000 = 2451545.0
    private static let e = rad * 23.4397   // 黄赤交角

    private static func toJulian(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1000 / dayMs - 0.5 + j1970
    }
    private static func toDays(_ date: Date) -> Double {
        toJulian(date) - j2000
    }

    private static func rightAscension(_ l: Double, _ b: Double) -> Double {
        atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
    }
    private static func declination(_ l: Double, _ b: Double) -> Double {
        asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
    }

    // MARK: 太阳

    private static func solarMeanAnomaly(_ d: Double) -> Double {
        rad * (357.5291 + 0.98560028 * d)
    }
    private static func eclipticLongitude(_ M: Double) -> Double {
        let C = rad * (1.9148 * sin(M) + 0.02 * sin(2 * M) + 0.0003 * sin(3 * M))
        let P = rad * 102.9372
        return M + C + P + rad * 180
    }
    private static func sunCoords(_ d: Double) -> (dec: Double, ra: Double) {
        let M = solarMeanAnomaly(d)
        let L = eclipticLongitude(M)
        // 黄道经度 L → 赤经赤纬：sinδ = sinε·sinλ
        return (declination(L, 0), rightAscension(L, 0))
    }

    // MARK: 月亮

    private static func moonCoords(_ d: Double) -> (dec: Double, ra: Double, dist: Double) {
        let L = rad * (218.316 + 13.176396 * d)
        let M = rad * (134.963 + 13.064993 * d)
        let F = rad * (93.272 + 13.229350 * d)
        let l = L + rad * 6.289 * sin(M)
        let b = rad * 5.128 * sin(F)
        let dt = 385001 - 20905 * cos(M)
        return (declination(l, b), rightAscension(l, b), dt)
    }

    private static func siderealTime(_ d: Double, _ lngWest: Double) -> Double {
        rad * (280.16 + 360.9856235 * d) - lngWest
    }
    private static func altitude(_ H: Double, _ phi: Double, _ dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))
    }
    private static func azimuth(_ H: Double, _ phi: Double, _ dec: Double) -> Double {
        atan2(sin(H), cos(H) * sin(phi) - tan(dec) * cos(phi))
    }

    // MARK: - 公开：天体地平坐标

    struct SkyPosition {
        var altDeg: Double
        var azDeg: Double   // 北=0，顺时针
    }

    /// 月亮地平坐标
    static func moonPosition(date: Date, lat: Double, lng: Double) -> SkyPosition {
        let lw = rad * -lng
        let phi = rad * lat
        let d = toDays(date)
        let c = moonCoords(d)
        let H = siderealTime(d, lw) - c.ra
        let alt = altitude(H, phi, c.dec)
        // 视差修正（SunCalc 公式；分母趋零时 tan 会产生发散值，需保护并限幅 ±2°）
        let pa = atan2(cos(H) * sin(phi) - tan(c.dec) * cos(phi), sin(H))
        let denom = pa + rad * 5.10
        var correction = 0.0
        if abs(denom) > 0.2 {
            correction = rad * 0.017 / tan(pa + rad * 10.26 / denom)
            correction = max(-rad * 2, min(rad * 2, correction))
        }
        let h = alt + correction
        return SkyPosition(altDeg: h / rad, azDeg: (azimuth(H, phi, c.dec) / rad + 180).normalized0to360)
    }

    /// 太阳地平坐标
    static func sunPosition(date: Date, lat: Double, lng: Double) -> SkyPosition {
        let lw = rad * -lng
        let phi = rad * lat
        let d = toDays(date)
        let c = sunCoords(d)
        let H = siderealTime(d, lw) - c.ra
        return SkyPosition(altDeg: altitude(H, phi, c.dec) / rad,
                           azDeg: (azimuth(H, phi, c.dec) / rad + 180).normalized0to360)
    }

    // MARK: - 公开：月相 / 照度

    struct MoonPhaseInfo {
        var illuminationFraction: Double   // 0-1
        var phaseAngleDeg: Double          // 0=新月 180=满月
        var phaseName: String              // 英文，如 "Waxing Crescent"
        var phaseEmoji: String
    }

    static func moonPhase(date: Date) -> MoonPhaseInfo {
        let d = toDays(date)
        // 用黄道经度差（距角）定相位：0°=新月，90°=上弦，180°=满月，270°=下弦
        let M = solarMeanAnomaly(d)
        let sunLon = eclipticLongitude(M)
        let mL = rad * (218.316 + 13.176396 * d)
        let mM = rad * (134.963 + 13.064993 * d)
        let moonLon = mL + rad * 6.289 * sin(mM)
        let elongation = ((moonLon - sunLon) / rad).normalized0to360   // 0-360
        let fraction = (1 - cos(elongation * rad)) / 2

        var name: String
        var emoji: String
        switch elongation {
        case ..<22.5: name = "New Moon"; emoji = "🌑"
        case ..<67.5: name = "Waxing Crescent"; emoji = "🌒"
        case ..<112.5: name = "First Quarter"; emoji = "🌓"
        case ..<157.5: name = "Waxing Gibbous"; emoji = "🌔"
        case ..<202.5: name = "Full Moon"; emoji = "🌕"
        case ..<247.5: name = "Waning Gibbous"; emoji = "🌖"
        case ..<292.5: name = "Last Quarter"; emoji = "🌗"
        case ..<337.5: name = "Waning Crescent"; emoji = "🌘"
        default: name = "New Moon"; emoji = "🌑"
        }
        return MoonPhaseInfo(illuminationFraction: fraction,
                             phaseAngleDeg: elongation,
                             phaseName: name,
                             phaseEmoji: emoji)
    }

    // MARK: - 公开：太阳升落 / 晨昏

    struct SunTimes {
        var sunrise: Date?
        var sunset: Date?
        var civilStart: Date?
        var civilEnd: Date?
        var nauticalStart: Date?
        var nauticalEnd: Date?
        var astroStart: Date?
        var astroEnd: Date?
    }

    /// 太阳升落 + 三级晨昏（SunCalc getTimes 算法）
    static func sunTimes(date: Date, lat: Double, lng: Double) -> SunTimes {
        let lw = rad * -lng
        let phi = rad * lat
        // 取当地正午作为日锚
        let dayStart = Calendar(identifier: .gregorian)
            .startOfDay(for: date).addingTimeInterval(12 * 3600)
        let d = toDays(dayStart)
        let n = (d - 0.0009 - lw / (2 * .pi)).rounded()
        let ds = approxTransit(0, lw, n)
        let M = solarMeanAnomaly(ds)
        let L = eclipticLongitude(M)
        let dec = declination(L, 0)
        let Jnoon = solarTransitJ(ds, M, L)

        func timesFor(_ angleDeg: Double) -> (rise: Date?, set: Date?) {
            let h = angleDeg * rad
            let Jset = getSetJ(h, lw, phi, dec, M, n)
            let Jrise = Jnoon - (Jset - Jnoon)
            return (fromJulian(Jrise), fromJulian(Jset))
        }

        let riseSet = timesFor(-0.833)
        let civil = timesFor(-6)
        let nautical = timesFor(-12)
        let astro = timesFor(-18)

        return SunTimes(
            sunrise: riseSet.rise, sunset: riseSet.set,
            civilStart: civil.rise, civilEnd: civil.set,
            nauticalStart: nautical.rise, nauticalEnd: nautical.set,
            astroStart: astro.rise, astroEnd: astro.set)
    }

    private static func julianCycle(_ d: Double, _ lw: Double) -> Double {
        (d - 0.0009 - lw / (2 * .pi)).rounded()
    }
    private static func approxTransit(_ Ht: Double, _ lw: Double, _ n: Double) -> Double {
        0.0009 + (Ht + lw) / (2 * .pi) + n
    }
    private static func solarTransitJ(_ ds: Double, _ M: Double, _ L: Double) -> Double {
        j2000 + ds + 0.0053 * sin(M) - 0.0069 * sin(2 * L)
    }
    private static func hourAngle(_ h: Double, _ phi: Double, _ dec: Double) -> Double {
        acos((sin(h) - sin(phi) * sin(dec)) / (cos(phi) * cos(dec)))
    }
    private static func getSetJ(_ h: Double, _ lw: Double, _ phi: Double, _ dec: Double, _ M: Double, _ n: Double) -> Double {
        let w = hourAngle(h, phi, dec)
        let a = approxTransit(w, lw, n)
        return solarTransitJ(a, M, eclipticLongitude(M))
    }
    private static func fromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: (j + 0.5 - j1970) * dayMs / 1000)
    }

    // MARK: - 公开：月出月落（高度扫描法，±10 分钟）

    struct MoonTimes {
        var moonrise: Date?
        var moonset: Date?
        var alwaysUp: Bool
        var alwaysDown: Bool
    }

    static func moonTimes(date: Date, lat: Double, lng: Double) -> MoonTimes {
        let dayStart = Calendar(identifier: .gregorian).startOfDay(for: date)
        var rise: Date?
        var set: Date?
        var prev = moonPosition(date: dayStart, lat: lat, lng: lng).altDeg
        var wasUp = prev > 0

        for minute in stride(from: 10, through: 1440, by: 10) {
            let t = dayStart.addingTimeInterval(Double(minute) * 60)
            let alt = moonPosition(date: t, lat: lat, lng: lng).altDeg
            let nowUp = alt > 0
            if nowUp != wasUp {
                if nowUp && rise == nil { rise = t }
                if !nowUp && set == nil { set = t }
                wasUp = nowUp
            }
            prev = alt
        }
        let startUp = moonPosition(date: dayStart, lat: lat, lng: lng).altDeg > 0
        let endUp = moonPosition(date: dayStart.addingTimeInterval(1439 * 60), lat: lat, lng: lng).altDeg > 0
        if startUp { rise = dayStart }   // 开天即挂
        if endUp && set == nil { set = nil }
        return MoonTimes(moonrise: rise, moonset: set,
                         alwaysUp: startUp && endUp && set == nil,
                         alwaysDown: !startUp && !endUp && rise == nil)
    }

    // MARK: - IMO 流星雨静态年历（无实时 API，硬编码 + 按星座匹配）

    struct IMOShower {
        var name: String
        var constellation: String
        var zhr: Int
        var raDeg: Double
        var decDeg: Double
        var peakMonth: Int      // 极大月份（北半球常规年历）
        var peakDay: Int
        var parent: String
    }

    /// IMO 年历主力流星雨（年度近似值，ZHR/极大日取典型值）
    static let imoCalendar: [IMOShower] = [
        IMOShower(name: "象限仪座流星雨", constellation: "Boötes", zhr: 110, raDeg: 230, decDeg: 49, peakMonth: 1, peakDay: 3, parent: "96P/Machholz 复合体"),
        IMOShower(name: "天琴座流星雨", constellation: "Lyra", zhr: 18, raDeg: 271, decDeg: 34, peakMonth: 4, peakDay: 22, parent: "C/1861 G1 Thatcher"),
        IMOShower(name: "宝瓶座 η 流星雨", constellation: "Aquarius", zhr: 50, raDeg: 338, decDeg: -1, peakMonth: 5, peakDay: 6, parent: "1P/Halley"),
        IMOShower(name: "英仙座流星雨", constellation: "Perseus", zhr: 100, raDeg: 48, decDeg: 58, peakMonth: 8, peakDay: 13, parent: "109P/Swift-Tuttle"),
        IMOShower(name: "猎户座流星雨", constellation: "Orion", zhr: 20, raDeg: 95, decDeg: 16, peakMonth: 10, peakDay: 21, parent: "1P/Halley"),
        IMOShower(name: "狮子座流星雨", constellation: "Leo", zhr: 10, raDeg: 152, decDeg: 22, peakMonth: 11, peakDay: 17, parent: "55P/Tempel-Tuttle"),
        IMOShower(name: "双子座流星雨", constellation: "Gemini", zhr: 150, raDeg: 112, decDeg: 33, peakMonth: 12, peakDay: 14, parent: "3200 Phaethon"),
        IMOShower(name: "小熊座流星雨", constellation: "Ursa Minor", zhr: 10, raDeg: 217, decDeg: 76, peakMonth: 12, peakDay: 22, parent: "8P/Tuttle"),
    ]

    /// 按星座/名称匹配 IMO 年历（JSON 缺失静态字段时补齐）
    static func imoMatch(constellation: String?, name: String?) -> IMOShower? {
        let candidates = [constellation, name].compactMap { $0?.lowercased() }
        guard !candidates.isEmpty else { return nil }
        return imoCalendar.first { shower in
            candidates.contains { text in
                text.contains(shower.constellation.lowercased())
                    || shower.name.lowercased().contains(text)
                    || text.contains(shower.name.lowercased().replacingOccurrences(of: "流星雨", with: ""))
            }
        }
    }

    // MARK: - Bortle 光污染静态地图值（无免费实时 API）

    /// 按观测点名匹配常用静态值（安吉 3 / 崇明 4 / 南汇嘴 6）
    static func bortleFallback(locationName: String) -> Int? {
        let text = locationName.lowercased()
        if text.contains("安吉") || text.contains("天池") { return 3 }
        if text.contains("崇明") || text.contains("东滩") { return 4 }
        if text.contains("南汇") || text.contains("嘴") { return 6 }
        if text.contains("佘山") || text.contains("滨海") { return 7 }
        return nil
    }
}

private extension Double {
    var normalized0to360: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
