import Foundation

struct CalendarEvent: Codable, Identifiable {
    let title: String
    let start: String      // ISO8601
    let end: String        // ISO8601
    let allDay: Bool
    let location: String?
    let calendar: String

    var id: String { "\(start)|\(title)" }

    var startDate: Date? { Self.iso.date(from: start) }
    var endDate: Date? { Self.iso.date(from: end) }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

struct WeatherSnapshot: Codable {
    let fetchedAt: String
    let temperatureC: Double
    let highC: Double
    let lowC: Double
    let weatherCode: Int
    let conditionText: String
    let conditionIcon: String
    let label: String
}

struct EventsPayload: Codable {
    let generatedAt: String
    let status: String
    let errorMessage: String?
    let today: [CalendarEvent]
    let tomorrow: [CalendarEvent]
    let weather: WeatherSnapshot?
}
