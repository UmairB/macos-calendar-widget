import SwiftUI

struct Dashboard: View {
    let payload: EventsPayload?
    let now: Date

    // Visible hour range — auto-extends if events fall outside the default 8–20.
    private var hourRange: ClosedRange<Int> {
        var lo = 8
        var hi = 20
        let events = payload?.today.compactMap { ($0.startDate, $0.endDate) } ?? []
        let cal = Calendar.current
        for (start, end) in events {
            if let s = start { lo = min(lo, cal.component(.hour, from: s)) }
            if let e = end   { hi = max(hi, cal.component(.hour, from: e) + 1) }
        }
        return lo...hi
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header(width: geo.size.width)
                    .padding(.top, geo.size.height * 0.04)
                    .padding(.horizontal, geo.size.width * 0.06)

                timeline(in: geo.size)
                    .padding(.horizontal, geo.size.width * 0.06)
                    .padding(.top, geo.size.height * 0.02)
                    .padding(.bottom, geo.size.height * 0.04)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(width: CGFloat) -> some View {
        HStack(alignment: .center) {
            Text(timeString)
                .font(.system(size: width * 0.10, weight: .thin))
                .foregroundColor(.white)
                .monospacedDigit()
                .kerning(-2)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(weekdayString)
                    .font(.system(size: width * 0.024, weight: .regular))
                    .foregroundColor(.gray)
                Text(dateString)
                    .font(.system(size: width * 0.024, weight: .light))
                    .foregroundColor(.gray)
                if let weather = payload?.weather {
                    weatherView(weather, width: width)
                        .padding(.top, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func weatherView(_ weather: WeatherSnapshot, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 8) {
                Text(weather.conditionIcon)
                    .font(.system(size: width * 0.024))
                Text("\(Int(weather.temperatureC.rounded()))°")
                    .font(.system(size: width * 0.028, weight: .regular))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("— \(weather.conditionText)")
                    .font(.system(size: width * 0.020, weight: .light))
                    .foregroundColor(.gray)
            }
            Text("H:\(Int(weather.highC.rounded()))°  L:\(Int(weather.lowC.rounded()))°")
                .font(.system(size: width * 0.016, weight: .light))
                .foregroundColor(Color.gray.opacity(0.75))
                .monospacedDigit()
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timeline(in size: CGSize) -> some View {
        let range = hourRange
        let hours = range.upperBound - range.lowerBound
        let timelineHeight = size.height * 0.78
        let pxPerHour = timelineHeight / CGFloat(hours)
        let gutterWidth: CGFloat = max(46, size.width * 0.05)
        let lineX = gutterWidth

        ZStack(alignment: .topLeading) {
            // Hour grid
            ForEach(range, id: \.self) { h in
                let y = CGFloat(h - range.lowerBound) * pxPerHour
                HStack(spacing: 8) {
                    Text(String(format: "%02d", h))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.65))
                        .frame(width: gutterWidth - 12, alignment: .trailing)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
                .offset(y: y - 8)
            }

            // Vertical spine
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .offset(x: lineX)

            // Events
            ForEach(payload?.today ?? []) { event in
                eventBlock(event,
                           range: range,
                           pxPerHour: pxPerHour,
                           availableWidth: size.width - (size.width * 0.12) - lineX - 16,
                           gutterWidth: lineX)
            }

            // Empty state
            if (payload?.today.isEmpty ?? true) && payload?.status == "ok" {
                Text("Nothing scheduled today")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color.gray.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .frame(height: timelineHeight)
            }

            // Now indicator (only if in range)
            nowIndicator(range: range, pxPerHour: pxPerHour, width: size.width * 0.88, lineX: lineX)
        }
        .frame(height: timelineHeight, alignment: .top)
    }

    @ViewBuilder
    private func eventBlock(_ event: CalendarEvent,
                            range: ClosedRange<Int>,
                            pxPerHour: CGFloat,
                            availableWidth: CGFloat,
                            gutterWidth: CGFloat) -> some View {
        if let start = event.startDate, let end = event.endDate {
            let cal = Calendar.current
            let startMinutes = CGFloat(cal.component(.hour, from: start)) * 60 + CGFloat(cal.component(.minute, from: start))
            let endMinutes   = CGFloat(cal.component(.hour, from: end))   * 60 + CGFloat(cal.component(.minute, from: end))
            let baseMinutes  = CGFloat(range.lowerBound) * 60

            let y      = ((startMinutes - baseMinutes) / 60) * pxPerHour
            let height = max(28, ((endMinutes - startMinutes) / 60) * pxPerHour - 4)

            let isPast    = end < now
            let isCurrent = start <= now && end > now

            let titleOpacity: Double = isPast ? 0.35 : 1.0
            let borderColor: Color = isCurrent ? .orange : Color.white.opacity(0.18)
            let borderWidth: CGFloat = isCurrent ? 2 : 1

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(format(start)) – \(format(end))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
                        .monospacedDigit()
                    Spacer()
                }
                Text(event.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let loc = event.location, !loc.isEmpty {
                    Text(loc)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: availableWidth, height: height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.orange.opacity(0.08) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .opacity(titleOpacity)
            .offset(x: gutterWidth + 12, y: y)
        }
    }

    @ViewBuilder
    private func nowIndicator(range: ClosedRange<Int>, pxPerHour: CGFloat, width: CGFloat, lineX: CGFloat) -> some View {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        if hour >= range.lowerBound && hour <= range.upperBound {
            let minutes = CGFloat(hour - range.lowerBound) * 60 + CGFloat(minute)
            let y = (minutes / 60) * pxPerHour
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: width, height: 1.5)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .offset(x: -4)
            }
            .offset(x: lineX, y: y)
        }
    }

    // MARK: - Formatting

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"; return f
    }()

    private var timeString:    String { Self.timeFormatter.string(from: now) }
    private var weekdayString: String { Self.weekdayFormatter.string(from: now) }
    private var dateString:    String { Self.dateFormatter.string(from: now) }

    private func format(_ d: Date) -> String { Self.timeFormatter.string(from: d) }
}
