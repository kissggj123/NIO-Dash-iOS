//
//  StargazingTrip.swift
//  wheater
//
//  观星行程数据模型：解析观测计划 JSON（schema_version 2.x 宽容解码）
//  字段语义参考 IMO/AMS 观测数据结构（best_viewing_window / calendar_event /
//  itinerary_segment / atmosphere / radiant / recommended_locations 等）。
//

import Foundation

// MARK: - 顶层行程

struct StargazingTrip: Codable, Identifiable, Equatable, Hashable {
    var eventID: String
    var name: String
    var nameEn: String?
    var constellation: String?
    var type: String?
    var zhr: Int?
    var populationIndexR: Double?
    var velocityKmS: Double?
    var parentBody: String?
    var parentType: String?
    var observationScore: Int?
    var scoreNote: String?
    var reasonSkip: String?
    var scoreBreakdown: ObservationScoreBreakdown?
    var activePeriod: ActivePeriod?
    var bestViewingWindow: BestViewingWindow?
    var calendarEvent: StargazingCalendarEvent?
    var itinerarySegment: ItinerarySegment?
    var radiant: Radiant?
    var moonInterference: MoonInterference?
    var sunTwilight: SunTwilight?
    var atmosphere: Atmosphere?
    var recommendedLocations: [RecommendedLocation]
    var tips: [String]
    var schemaVersion: String?
    var importedAt: Date

    var id: String { eventID.isEmpty ? name : eventID }

    // MARK: 计算属性

    /// 最佳窗口开始（极大夜）
    var startDate: Date? {
        bestViewingWindow?.windowStartDate
            ?? calendarEvent?.startDate
    }

    /// 最佳窗口结束
    var endDate: Date? {
        bestViewingWindow?.windowEndDate
            ?? calendarEvent?.endDate
    }

    /// 是否仍有观测价值（窗口未结束）
    var isUpcoming: Bool {
        guard let end = endDate else { return false }
        return end > Date()
    }

    /// 是否尚未开始
    var isNotStarted: Bool {
        guard let start = startDate else { return false }
        return start > Date()
    }

    /// 默认观测点（第一个推荐地点或日历事件坐标）
    var primaryLocation: RecommendedLocation? {
        recommendedLocations.first
            ?? calendarEvent?.coordinates.map {
                RecommendedLocation(name: calendarEvent?.location ?? "观测点",
                                    city: nil, tag: nil,
                                    lat: $0.lat, lng: $0.lng,
                                    bortleClass: nil, expectedRate: nil)
            }
    }

    /// 观测点列表页标题（如 "上海近郊暗夜追星计划"）
    var routeName: String? { itinerarySegment?.routeName }

    // MARK: - 解码

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case name
        case nameEn = "name_en"
        case constellation
        case type
        case zhr
        case populationIndexR = "population_index_r"
        case velocityKmS = "velocity_km_s"
        case parentBody = "parent_body"
        case parentType = "parent_type"
        case observationScore = "observation_score"
        case scoreNote = "observation_score_note"
        case reasonSkip = "reason_skip"
        case scoreBreakdown = "observation_score_breakdown"
        case activePeriod = "active_period"
        case bestViewingWindow = "best_viewing_window"
        case calendarEvent = "calendar_event"
        case itinerarySegment = "itinerary_segment"
        case radiant
        case moonInterference = "moon_interference"
        case sunTwilight = "sun_twilight_shanghai"
        case atmosphere
        case recommendedLocations = "recommended_locations"
        case tips
        case schemaVersion = "schema_version"
        case importedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try c.decodeIfPresent(String.self, forKey: .eventID) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名观测计划"
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn)
        constellation = try c.decodeIfPresent(String.self, forKey: .constellation)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        zhr = try c.decodeIfPresent(Int.self, forKey: .zhr)
        populationIndexR = try c.decodeIfPresent(Double.self, forKey: .populationIndexR)
        velocityKmS = try c.decodeIfPresent(Double.self, forKey: .velocityKmS)
        parentBody = try c.decodeIfPresent(String.self, forKey: .parentBody)
        parentType = try c.decodeIfPresent(String.self, forKey: .parentType)
        observationScore = try c.decodeIfPresent(Int.self, forKey: .observationScore)
        scoreNote = try? c.decodeIfPresent(String.self, forKey: .scoreNote)
        reasonSkip = try? c.decodeIfPresent(String.self, forKey: .reasonSkip)
        scoreBreakdown = try? c.decodeIfPresent(ObservationScoreBreakdown.self, forKey: .scoreBreakdown)
        activePeriod = try? c.decodeIfPresent(ActivePeriod.self, forKey: .activePeriod)
        bestViewingWindow = try? c.decodeIfPresent(BestViewingWindow.self, forKey: .bestViewingWindow)
        calendarEvent = try? c.decodeIfPresent(StargazingCalendarEvent.self, forKey: .calendarEvent)
        itinerarySegment = try? c.decodeIfPresent(ItinerarySegment.self, forKey: .itinerarySegment)
        radiant = try? c.decodeIfPresent(Radiant.self, forKey: .radiant)
        moonInterference = try? c.decodeIfPresent(MoonInterference.self, forKey: .moonInterference)
        sunTwilight = try? c.decodeIfPresent(SunTwilight.self, forKey: .sunTwilight)
        atmosphere = try? c.decodeIfPresent(Atmosphere.self, forKey: .atmosphere)
        recommendedLocations = (try? c.decodeIfPresent([RecommendedLocation].self, forKey: .recommendedLocations)) ?? []
        tips = (try? c.decodeIfPresent([String].self, forKey: .tips)) ?? []
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion)
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
    }

    /// 供本地存档编码用
    init(eventID: String,
         name: String,
         nameEn: String? = nil,
         constellation: String? = nil,
         type: String? = nil,
         zhr: Int? = nil,
         populationIndexR: Double? = nil,
         velocityKmS: Double? = nil,
         parentBody: String? = nil,
         parentType: String? = nil,
         observationScore: Int? = nil,
         scoreNote: String? = nil,
         reasonSkip: String? = nil,
         scoreBreakdown: ObservationScoreBreakdown? = nil,
         activePeriod: ActivePeriod? = nil,
         bestViewingWindow: BestViewingWindow? = nil,
         calendarEvent: StargazingCalendarEvent? = nil,
         itinerarySegment: ItinerarySegment? = nil,
         radiant: Radiant? = nil,
         moonInterference: MoonInterference? = nil,
         sunTwilight: SunTwilight? = nil,
         atmosphere: Atmosphere? = nil,
         recommendedLocations: [RecommendedLocation] = [],
         tips: [String] = [],
         schemaVersion: String? = nil,
         importedAt: Date = Date()) {
        self.eventID = eventID
        self.name = name
        self.nameEn = nameEn
        self.constellation = constellation
        self.type = type
        self.zhr = zhr
        self.populationIndexR = populationIndexR
        self.velocityKmS = velocityKmS
        self.parentBody = parentBody
        self.parentType = parentType
        self.observationScore = observationScore
        self.scoreNote = scoreNote
        self.reasonSkip = reasonSkip
        self.scoreBreakdown = scoreBreakdown
        self.activePeriod = activePeriod
        self.bestViewingWindow = bestViewingWindow
        self.calendarEvent = calendarEvent
        self.itinerarySegment = itinerarySegment
        self.radiant = radiant
        self.moonInterference = moonInterference
        self.sunTwilight = sunTwilight
        self.atmosphere = atmosphere
        self.recommendedLocations = recommendedLocations
        self.tips = tips
        self.schemaVersion = schemaVersion
        self.importedAt = importedAt
    }
}

// MARK: - 观测评分

struct ObservationScoreBreakdown: Codable, Equatable, Hashable {
    var zhrScore: Int?
    var radiantAltitudeScore: Int?
    var moonScore: Int?
    var durationScore: Int?
    var maxTotal: Int?
    var note: String?

    private enum CodingKeys: String, CodingKey {
        case zhrScore = "zhr_score"
        case radiantAltitudeScore = "radiant_altitude_score"
        case moonScore = "moon_score"
        case durationScore = "duration_score"
        case maxTotal = "max_total"
        case note
    }
}

// MARK: - 活跃期

struct ActivePeriod: Codable, Equatable, Hashable {
    var startDate: String?
    var endDate: String?
    var primarySource: String?

    private enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case primarySource = "primary_source"
    }
}

// MARK: - 最佳观测窗口

struct BestViewingWindow: Codable, Equatable, Hashable {
    var primary: Window?
    var secondary: Window?
    var startDate: Date?
    var endDate: Date?
    var displayRange: String?
    var startUnix: Double?
    var endUnix: Double?
    var note: String?

    private enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case startDate = "start_time"
        case endDate = "end_time"
        case displayRange = "display_range"
        case startUnix = "start_unix"
        case endUnix = "end_unix"
        case note
    }

    var windowStartDate: Date? {
        primary?.startDate ?? startUnix.map { Date(timeIntervalSince1970: $0) } ?? startDate
    }

    var windowEndDate: Date? {
        primary?.endDate ?? endUnix.map { Date(timeIntervalSince1970: $0) } ?? endDate
    }

    struct Window: Codable, Equatable, Hashable {
        var label: String?
        var startLocal: String?
        var endLocal: String?
        var startUnix: Double?
        var endUnix: Double?
        var displayRange: String?
        var bestHourLocal: String?

        private enum CodingKeys: String, CodingKey {
            case label
            case startLocal = "start_local"
            case endLocal = "end_local"
            case startUnix = "start_unix"
            case endUnix = "end_unix"
            case displayRange = "display_range"
            case bestHourLocal = "best_hour_local"
        }

        var startDate: Date? {
            startUnix.map { Date(timeIntervalSince1970: $0) }
        }

        var endDate: Date? {
            endUnix.map { Date(timeIntervalSince1970: $0) }
        }
    }
}

// MARK: - 日历事件

struct StargazingCalendarEvent: Codable, Equatable, Hashable {
    var summary: String?
    var description: String?
    var location: String?
    var coordinates: Coordinates?
    var startUnix: Double?
    var endUnix: Double?
    var alarms: [Alarm]

    private enum CodingKeys: String, CodingKey {
        case summary
        case description
        case location
        case coordinates = "location_coordinates"
        case startUnix = "dtstart_unix"
        case endUnix = "dtend_unix"
        case alarms
    }

    struct Coordinates: Codable, Equatable, Hashable {
        var lat: Double
        var lng: Double

        private enum CodingKeys: String, CodingKey {
            case lat
            case lng = "lng"
        }

        init(lat: Double, lng: Double) { self.lat = lat; self.lng = lng }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lat = (try? c.decodeIfPresent(Double.self, forKey: .lat)) ?? 0
            lng = (try? c.decodeIfPresent(Double.self, forKey: .lng)) ?? 0
        }
    }

    struct Alarm: Codable, Equatable, Hashable {
        var trigger: String?          // ISO8601 duration，如 "-PT3H" / "-PT30M"
        var alarmLocal: String?       // 触发时刻（本地）
        var action: String?           // DISPLAY
        var description: String?

        private enum CodingKeys: String, CodingKey {
            case trigger
            case alarmLocal = "alarm_local"
            case action
            case description
        }
    }

    var startDate: Date? { startUnix.map { Date(timeIntervalSince1970: $0) } }
    var endDate: Date? { endUnix.map { Date(timeIntervalSince1970: $0) } }
}

// MARK: - 行程时间轴

struct ItinerarySegment: Codable, Equatable, Hashable {
    var routeName: String?
    var targetLocationID: String?
    var timeline: [TimelineItem]

    private enum CodingKeys: String, CodingKey {
        case routeName = "route_name"
        case targetLocationID = "target_location_id"
        case timeline
    }

    struct TimelineItem: Codable, Equatable, Hashable {
        var action: String?
        var phase: String?
        var timeLocal: String?
        var unix: Double?
        var unixStart: Double?
        var unixEnd: Double?
        var estimatedDurationMin: Int?

        private enum CodingKeys: String, CodingKey {
            case action
            case phase
            case timeLocal = "time_local"
            case unix
            case unixStart = "unix_start"
            case unixEnd = "unix_end"
            case estimatedDurationMin = "estimated_duration_min"
        }

        var startDate: Date? {
            unix.map { Date(timeIntervalSince1970: $0) } ?? unixStart.map { Date(timeIntervalSince1970: $0) }
        }
        var endDate: Date? { unixEnd.map { Date(timeIntervalSince1970: $0) } }
    }
}

// MARK: - 辐射点

struct Radiant: Codable, Equatable, Hashable {
    var horizontal: Horizontal?
    var equatorial: Equatorial?

    private enum CodingKeys: String, CodingKey {
        case horizontal
        case equatorial
    }

    /// 赤经/赤纬（如双子座 112°, +33°），用于本地实时 alt/az 计算
    struct Equatorial: Codable, Equatable, Hashable {
        var raDeg: Double?
        var decDeg: Double?

        private enum CodingKeys: String, CodingKey {
            case raDeg = "ra_deg"
            case decDeg = "dec_deg"
            case ra
            case dec
        }

        init(raDeg: Double?, decDeg: Double?) {
            self.raDeg = raDeg
            self.decDeg = decDeg
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 兼容 ra/dec 以小时(如 7.47h)或度表示
            if let hours = try? c.decodeIfPresent(Double.self, forKey: .ra) {
                raDeg = hours <= 24.1 ? hours * 15 : hours
            } else {
                raDeg = try? c.decodeIfPresent(Double.self, forKey: .raDeg)
            }
            decDeg = (try? c.decodeIfPresent(Double.self, forKey: .dec)) ?? (try? c.decodeIfPresent(Double.self, forKey: .decDeg))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try? c.encodeIfPresent(raDeg, forKey: .raDeg)
            try? c.encodeIfPresent(decDeg, forKey: .decDeg)
        }
    }

    struct Horizontal: Codable, Equatable, Hashable {
        var altazTimeline: [AltAzEntry]
        var riseTimeLocal: String?
        var setTimeLocal: String?
        var culminationTimeLocal: String?
        var culminationAltDeg: Double?
        var maxAltitudeDeg: Double?
        var azimuthDesc: String?

        private enum CodingKeys: String, CodingKey {
            case altazTimeline = "altaz_timeline"
            case riseTimeLocal = "rise_time_local"
            case setTimeLocal = "set_time_local"
            case culminationTimeLocal = "culmination_time_local"
            case culminationAltDeg = "culmination_alt_deg"
            case maxAltitudeDeg = "max_altitude_deg"
            case azimuthDesc = "azimuth_desc"
        }

        struct AltAzEntry: Codable, Equatable, Hashable, Identifiable {
            var timeLocal: String?
            var unix: Double?
            var altDeg: Double?
            var azDeg: Double?
            var azCompass: String?
            var note: String?

            private enum CodingKeys: String, CodingKey {
                case timeLocal = "time_local"
                case unix
                case altDeg = "alt_deg"
                case azDeg = "az_deg"
                case azCompass = "az_compass"
                case note
            }

            var id: String { "\(unix ?? 0)-\(altDeg ?? 0)" }
            var date: Date? { unix.map { Date(timeIntervalSince1970: $0) } }
        }
    }
}

// MARK: - 月光干扰

struct MoonInterference: Codable, Equatable, Hashable {
    var phase: String?
    var phaseDesc: String?
    var illuminationPctAtPeak: Double?
    var illuminationAtPeakCalc: Double? { illuminationPctAtPeak }
    var moonriseLocal: String?
    var moonsetDec14Local: String?
    var moonsetDec14Unix: Double?
    var impactLevel: String?
    var note: String?

    private enum CodingKeys: String, CodingKey {
        case phase
        case phaseDesc = "phase_desc"
        case illuminationPctAtPeak = "illumination_pct_at_peak"
        case illuminationPct = "illumination_pct"
        case moonriseLocal = "moonrise_local"
        case moonsetDec14Local = "moonset_dec14_local"
        case moonsetLocal = "moonset_local"
        case moonsetDec14Unix = "moonset_dec14_unix"
        case impactLevel = "impact_level"
        case note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try? c.decodeIfPresent(String.self, forKey: .phase)
        phaseDesc = try? c.decodeIfPresent(String.self, forKey: .phaseDesc)
        illuminationPctAtPeak = (try? c.decodeIfPresent(Double.self, forKey: .illuminationPctAtPeak))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .illuminationPct))
        moonriseLocal = try? c.decodeIfPresent(String.self, forKey: .moonriseLocal)
        moonsetDec14Local = (try? c.decodeIfPresent(String.self, forKey: .moonsetDec14Local))
            ?? (try? c.decodeIfPresent(String.self, forKey: .moonsetLocal))
        moonsetDec14Unix = try? c.decodeIfPresent(Double.self, forKey: .moonsetDec14Unix)
        impactLevel = try? c.decodeIfPresent(String.self, forKey: .impactLevel)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    /// 供本地存档编码用
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try? c.encodeIfPresent(phase, forKey: .phase)
        try? c.encodeIfPresent(phaseDesc, forKey: .phaseDesc)
        try? c.encodeIfPresent(illuminationPctAtPeak, forKey: .illuminationPctAtPeak)
        try? c.encodeIfPresent(moonriseLocal, forKey: .moonriseLocal)
        try? c.encodeIfPresent(moonsetDec14Local, forKey: .moonsetDec14Local)
        try? c.encodeIfPresent(moonsetDec14Unix, forKey: .moonsetDec14Unix)
        try? c.encodeIfPresent(impactLevel, forKey: .impactLevel)
        try? c.encodeIfPresent(note, forKey: .note)
    }

    /// 供本地存档编码用
    init(phase: String? = nil, phaseDesc: String? = nil, illuminationPctAtPeak: Double? = nil,
         moonriseLocal: String? = nil, moonsetDec14Local: String? = nil,
         moonsetDec14Unix: Double? = nil, impactLevel: String? = nil, note: String? = nil) {
        self.phase = phase
        self.phaseDesc = phaseDesc
        self.illuminationPctAtPeak = illuminationPctAtPeak
        self.moonriseLocal = moonriseLocal
        self.moonsetDec14Local = moonsetDec14Local
        self.moonsetDec14Unix = moonsetDec14Unix
        self.impactLevel = impactLevel
        self.note = note
    }

    /// 月相 emoji（兼容 "full_moon" 枚举与 "Full Moon" 英文文本）
    var phaseEmoji: String {
        let normalized = (phase ?? "").lowercased().replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "new_moon": return "🌑"
        case "waxing_crescent": return "🌒"
        case "first_quarter": return "🌓"
        case "waxing_gibbous": return "🌔"
        case "full_moon": return "🌕"
        case "waning_gibbous": return "🌖"
        case "last_quarter": return "🌗"
        case "waning_crescent": return "🌘"
        default: return "🌙"
        }
    }
}

// MARK: - 晨昏线

struct SunTwilight: Codable, Equatable, Hashable {
    var darkWindowPeakNight: DarkWindow?
    var daily: [String: DayInfo]

    private enum CodingKeys: String, CodingKey {
        case darkWindowPeakNight = "dark_window_peak_night"
        case daily
    }

    /// 通用宽容解码：dark_window 与按日期的 dict 混存
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        darkWindowPeakNight = try? c.decodeIfPresent(DarkWindow.self, forKey: .darkWindowPeakNight)
        if let dict = try? c.decodeIfPresent([String: DayInfo].self, forKey: .daily) {
            daily = dict.filter { $0.key != CodingKeys.darkWindowPeakNight.rawValue }
        } else {
            daily = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try? c.encodeIfPresent(darkWindowPeakNight, forKey: .darkWindowPeakNight)
        try? c.encodeIfPresent(daily, forKey: .daily)
    }

    struct DarkWindow: Codable, Equatable, Hashable {
        var startLocal: String?
        var endLocal: String?
        var startUnix: Double?
        var endUnix: Double?

        private enum CodingKeys: String, CodingKey {
            case startLocal = "start_local"
            case endLocal = "end_local"
            case startUnix = "start_unix"
            case endUnix = "end_unix"
        }
    }

    struct DayInfo: Codable, Equatable, Hashable {
        var sunrise: String?
        var sunset: String?
        var astroTwilightStart: String?
        var astroTwilightEnd: String?

        private enum CodingKeys: String, CodingKey {
            case sunrise
            case sunset
            case astroTwilightStart = "astro_twilight_start"
            case astroTwilightEnd = "astro_twilight_end"
        }
    }
}

// MARK: - 大气与天气（JSON 内占位结构 / API 模板）

struct Atmosphere: Codable, Equatable, Hashable {
    var status: String?
    var statusNote: String?
    var validForLocal: String?
    var seeing: Seeing?
    var transparency: Transparency?
    var weather: WeatherPlaceholder?

    private enum CodingKeys: String, CodingKey {
        case status
        case statusNote = "status_note"
        case validForLocal = "valid_for_local"
        case seeing
        case transparency
        case weather
    }

    struct Seeing: Codable, Equatable, Hashable {
        var seeingArcsec: Double?
        var seeingLevel: String?
        var jetStreamWindMs: Double?

        private enum CodingKeys: String, CodingKey {
            case seeingArcsec = "seeing_arcsec"
            case seeingLevel = "seeing_level"
            case jetStreamWindMs = "jet_stream_wind_ms"
        }
    }

    struct Transparency: Codable, Equatable, Hashable {
        var transparencyLevel: String?
        var transparencyScore: Double?
        var limitingMagnitude: Double?
        var precipitableWaterMm: Double?

        private enum CodingKeys: String, CodingKey {
            case transparencyLevel = "transparency_level"
            case transparencyScore = "transparency_score_1_5"
            case limitingMagnitude = "limiting_magnitude"
            case precipitableWaterMm = "precipitable_water_mm"
        }
    }

    struct WeatherPlaceholder: Codable, Equatable, Hashable {
        var cloudCoverPct: Double?
        var temperatureC: Double?
        var humidityPct: Double?
        var dewPointC: Double?
        var pressureHpa: Double?
        var windSpeedKmh: Double?
        var windDirectionDeg: Double?
        var aqi: Double?
        var precipitationProbPct: Double?

        private enum CodingKeys: String, CodingKey {
            case cloudCoverPct = "cloud_cover_pct"
            case temperatureC = "temperature_c"
            case humidityPct = "humidity_pct"
            case dewPointC = "dew_point_c"
            case pressureHpa = "pressure_hpa"
            case windSpeedKmh = "wind_speed_kmh"
            case windDirectionDeg = "wind_direction_deg"
            case aqi
            case precipitationProbPct = "precipitation_prob_pct"
        }
    }
}

// MARK: - 辐射点本地天文计算（RA/Dec → Alt/Az，免 API）

enum RadiantAstrometry {
    /// 地平坐标结果
    struct HorizontalPosition {
        var altDeg: Double
        var azDeg: Double
    }

    /// 给定时刻/经纬度计算天体高度角与方位角（方位北=0°，顺时针）
    /// - 参数 raDeg/decDeg 为赤经（度）/赤纬（度）
    static func altAz(raDeg: Double, decDeg: Double, lat: Double, lng: Double, date: Date) -> HorizontalPosition {
        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        // 格林尼治平恒星时（度），IAU 简化式，精度 ~0.1°，足够 UI 使用
        let t = julianDay - 2451545.0
        var gmst = 280.46061837 + 360.98564736629 * t
        gmst = gmst.truncatingRemainder(dividingBy: 360)
        let lst = (gmst + lng).normalizedDegrees0to360()   // 东经为正
        let hourAngle = (lst - raDeg).normalizedDegrees0to360()
        let ha = hourAngle * .pi / 180
        let dec = decDeg * .pi / 180
        let latRad = lat * .pi / 180

        let sinAlt = sin(dec) * sin(latRad) + cos(dec) * cos(latRad) * cos(ha)
        let alt = asin(max(-1, min(1, sinAlt)))

        // 方位角（北起顺时针）
        let az = atan2(sin(ha), cos(ha) * sin(latRad) - tan(dec) * cos(latRad))
        let azDeg = az * 180 / .pi + 180

        return HorizontalPosition(altDeg: alt * 180 / .pi, azDeg: azDeg.normalizedDegrees0to360())
    }

    /// 生成观测窗口逐时 alt/az 时间轴（JSON 缺失 altaz_timeline 时的兜底）
    static func timeline(raDeg: Double, decDeg: Double, lat: Double, lng: Double,
                         start: Date, end: Date) -> [Radiant.Horizontal.AltAzEntry] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M-d HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        var entries: [Radiant.Horizontal.AltAzEntry] = []
        var cursor = start
        while cursor <= end {
            let pos = altAz(raDeg: raDeg, decDeg: decDeg, lat: lat, lng: lng, date: cursor)
            entries.append(Radiant.Horizontal.AltAzEntry(
                timeLocal: formatter.string(from: cursor),
                unix: cursor.timeIntervalSince1970,
                altDeg: pos.altDeg,
                azDeg: pos.azDeg,
                azCompass: compass(for: pos.azDeg),
                note: nil))
            cursor = cursor.addingTimeInterval(3600)
        }
        return entries
    }

    static func compass(for azDeg: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((azDeg + 11.25) / 22.5) % 16
        return names[max(0, index)]
    }
}

private extension Double {
    /// 归一化到 [0, 360)
    func normalizedDegrees0to360() -> Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

// MARK: - 推荐观测点

struct RecommendedLocation: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var city: String?
    var tag: String?
    var lat: Double
    var lng: Double
    var bortleClass: Int?
    var expectedRate: String?
    var culminationAltDeg: Double?

    var id: String { "\(name)-\(lat)-\(lng)" }

    private enum CodingKeys: String, CodingKey {
        case name
        case city
        case tag
        case lat
        case lng
        case bortleClass = "bortle_class"
        case expectedRate = "expected_meteors_per_hour_dark"
        case culminationAltDeg = "culmination_alt_deg"
    }

    init(name: String, city: String?, tag: String?, lat: Double, lng: Double,
         bortleClass: Int?, expectedRate: String?, culminationAltDeg: Double? = nil) {
        self.name = name
        self.city = city
        self.tag = tag
        self.lat = lat
        self.lng = lng
        self.bortleClass = bortleClass
        self.expectedRate = expectedRate
        self.culminationAltDeg = culminationAltDeg
    }
}
