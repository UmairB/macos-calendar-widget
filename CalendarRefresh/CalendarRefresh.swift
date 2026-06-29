// CalendarRefresh
//
// Reads today's and tomorrow's events from EventKit and current/today's
// weather from Open-Meteo, then writes both to JSON consumed by the saver.
//
// Runs as the user (NOT inside the screensaver sandbox). Invoked every
// 60 seconds by a LaunchAgent. Weather is cached for 15 minutes to avoid
// hammering the API.

import Foundation
import EventKit

// MARK: - Location (edit to change weather location)

let WEATHER_LAT: Double   = 51.473185     // SW11 3ET (Battersea, London)
let WEATHER_LON: Double   = -0.167173
let WEATHER_LABEL: String = "London"
let WEATHER_CACHE_SECONDS: TimeInterval = 15 * 60

// MARK: - JSON model

struct CalendarEvent: Codable {
    let title: String
    let start: String        // ISO8601
    let end: String          // ISO8601
    let allDay: Bool
    let location: String?
    let calendar: String
}

struct WeatherSnapshot: Codable {
    let fetchedAt: String       // ISO8601, used for cache freshness
    let temperatureC: Double
    let highC: Double
    let lowC: Double
    let weatherCode: Int        // WMO code
    let conditionText: String
    let conditionIcon: String   // unicode glyph
    let label: String           // human-readable location label
}

struct EventsPayload: Codable {
    let generatedAt: String
    let status: String          // "ok" | "no_access" | "error"
    let errorMessage: String?
    let today: [CalendarEvent]
    let tomorrow: [CalendarEvent]
    let weather: WeatherSnapshot?
}

// MARK: - Helpers

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

func fetchEvents(_ store: EKEventStore, from: Date, to: Date) -> [CalendarEvent] {
    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
    return store.events(matching: predicate)
        .sorted { $0.startDate < $1.startDate }
        .map { e in
            CalendarEvent(
                title: e.title ?? "(Untitled)",
                start: iso(e.startDate),
                end: iso(e.endDate),
                allDay: e.isAllDay,
                location: (e.location?.isEmpty == false) ? e.location : nil,
                calendar: e.calendar.title
            )
        }
}

// MARK: - Weather

/// WMO weather code → (icon, human text). Curated from open-meteo.com docs.
func describe(weatherCode code: Int) -> (icon: String, text: String) {
    switch code {
    case 0:           return ("☀", "Clear")
    case 1:           return ("🌤", "Mainly clear")
    case 2:           return ("⛅", "Partly cloudy")
    case 3:           return ("☁", "Overcast")
    case 45, 48:      return ("🌫", "Fog")
    case 51, 53, 55:  return ("🌦", "Drizzle")
    case 56, 57:      return ("🌧", "Freezing drizzle")
    case 61, 63, 65:  return ("🌧", "Rain")
    case 66, 67:      return ("🌧", "Freezing rain")
    case 71, 73, 75:  return ("🌨", "Snow")
    case 77:          return ("❄", "Snow grains")
    case 80, 81, 82:  return ("🌦", "Rain showers")
    case 85, 86:      return ("🌨", "Snow showers")
    case 95:          return ("⛈", "Thunderstorm")
    case 96, 99:      return ("⛈", "Thunderstorm w/ hail")
    default:          return ("·", "Unknown")
    }
}

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }
    let current: Current
    let daily: Daily
}

func fetchWeather() -> WeatherSnapshot? {
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
        URLQueryItem(name: "latitude",  value: String(WEATHER_LAT)),
        URLQueryItem(name: "longitude", value: String(WEATHER_LON)),
        URLQueryItem(name: "current",   value: "temperature_2m,weather_code"),
        URLQueryItem(name: "daily",     value: "temperature_2m_max,temperature_2m_min"),
        URLQueryItem(name: "timezone",  value: "auto"),
        URLQueryItem(name: "forecast_days", value: "1"),
    ]
    guard let url = components.url else { return nil }

    var result: WeatherSnapshot?
    let sem = DispatchSemaphore(value: 0)

    let task = URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 10)) { data, response, error in
        defer { sem.signal() }
        if let error = error {
            FileHandle.standardError.write(Data("weather fetch failed: \(error.localizedDescription)\n".utf8))
            return
        }
        guard let data = data else { return }
        do {
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let desc = describe(weatherCode: decoded.current.weather_code)
            result = WeatherSnapshot(
                fetchedAt:     iso(Date()),
                temperatureC:  decoded.current.temperature_2m,
                highC:         decoded.daily.temperature_2m_max.first ?? decoded.current.temperature_2m,
                lowC:          decoded.daily.temperature_2m_min.first ?? decoded.current.temperature_2m,
                weatherCode:   decoded.current.weather_code,
                conditionText: desc.text,
                conditionIcon: desc.icon,
                label:         WEATHER_LABEL
            )
        } catch {
            FileHandle.standardError.write(Data("weather decode failed: \(error.localizedDescription)\n".utf8))
        }
    }
    task.resume()
    _ = sem.wait(timeout: .now() + 12)
    return result
}

/// Returns the cached weather if it is still fresh, otherwise nil.
func cachedFreshWeather() -> WeatherSnapshot? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let cached = home.appendingPathComponent("Library/Application Support/CalendarSaver/events.json")
    guard
        let data = try? Data(contentsOf: cached),
        let prev = try? JSONDecoder().decode(EventsPayload.self, from: data),
        let weather = prev.weather,
        let fetched = isoFormatter.date(from: weather.fetchedAt)
    else { return nil }
    return Date().timeIntervalSince(fetched) < WEATHER_CACHE_SECONDS ? weather : nil
}

// MARK: - Write

func write(_ payload: EventsPayload) {
    let home = FileManager.default.homeDirectoryForCurrentUser

    let supportDir = home.appendingPathComponent("Library/Application Support/CalendarSaver")
    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    let appSupportOut = supportDir.appendingPathComponent("events.json")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data: Data
    do {
        data = try encoder.encode(payload)
    } catch {
        FileHandle.standardError.write(Data("encode error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

    func atomicWrite(_ target: URL) {
        let tmp = target.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: target)
            }
            FileHandle.standardOutput.write(Data("wrote \(target.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("write \(target.path) skipped: \(error.localizedDescription)\n".utf8))
        }
    }

    atomicWrite(appSupportOut)

    // Write into every installed CalendarSaver*.saver bundle's Resources dir
    // and re-sign — Tahoe hides invalid-signature bundles from the picker.
    let saversDir = home.appendingPathComponent("Library/Screen Savers")
    if let entries = try? FileManager.default.contentsOfDirectory(atPath: saversDir.path) {
        for entry in entries where entry.hasPrefix("CalendarSaver") && entry.hasSuffix(".saver") {
            let bundleURL = saversDir.appendingPathComponent(entry)
            let resources = bundleURL.appendingPathComponent("Contents/Resources")
            guard FileManager.default.fileExists(atPath: resources.path) else { continue }

            atomicWrite(resources.appendingPathComponent("events.json"))

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            task.arguments = ["--force", "--sign", "-", "--timestamp=none", bundleURL.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    FileHandle.standardError.write(Data("codesign \(entry) exited \(task.terminationStatus)\n".utf8))
                }
            } catch {
                FileHandle.standardError.write(Data("codesign \(entry) failed to launch: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    let wx = payload.weather.map { "\($0.temperatureC)°C \($0.conditionText)" } ?? "no weather"
    FileHandle.standardOutput.write(Data("status=\(payload.status) today=\(payload.today.count) tomorrow=\(payload.tomorrow.count) weather=\(wx)\n".utf8))
}

// MARK: - Main

// Weather: use cache if fresh, otherwise refetch.
let weather = cachedFreshWeather() ?? fetchWeather()

let store = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)
var grantedFlag = false
var errorMsg: String? = nil

store.requestFullAccessToEvents { granted, error in
    grantedFlag = granted
    if let error = error { errorMsg = error.localizedDescription }
    semaphore.signal()
}
semaphore.wait()

if !grantedFlag {
    let payload = EventsPayload(
        generatedAt: iso(Date()),
        status: errorMsg == nil ? "no_access" : "error",
        errorMessage: errorMsg,
        today: [], tomorrow: [],
        weather: weather
    )
    write(payload)
    exit(0)
}

let cal = Calendar.current
let todayStart = cal.startOfDay(for: Date())
let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart)!
let dayAfter = cal.date(byAdding: .day, value: 2, to: todayStart)!

let payload = EventsPayload(
    generatedAt: iso(Date()),
    status: "ok",
    errorMessage: nil,
    today:    fetchEvents(store, from: todayStart, to: tomorrowStart),
    tomorrow: fetchEvents(store, from: tomorrowStart, to: dayAfter),
    weather:  weather
)
write(payload)
