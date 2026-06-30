import SwiftUI
import AppKit

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

            // Events — laid out into columns so overlaps render side-by-side.
            let availableWidth = size.width - (size.width * 0.12) - lineX - 16
            let laidOut = Self.layout(events: payload?.today ?? [])
            ForEach(laidOut) { item in
                eventBlock(item.event,
                           range: range,
                           pxPerHour: pxPerHour,
                           availableWidth: availableWidth,
                           gutterWidth: lineX,
                           column: item.column,
                           columnCount: item.columnCount,
                           hasOverflowAbove: item.hasOverflowAbove)
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
                            gutterWidth: CGFloat,
                            column: Int,
                            columnCount: Int,
                            hasOverflowAbove: Bool) -> some View {
        if let start = event.startDate, let end = event.endDate {
            let cal = Calendar.current
            let startMinutes = CGFloat(cal.component(.hour, from: start)) * 60 + CGFloat(cal.component(.minute, from: start))
            let endMinutes   = CGFloat(cal.component(.hour, from: end))   * 60 + CGFloat(cal.component(.minute, from: end))
            let baseMinutes  = CGFloat(range.lowerBound) * 60

            let y = ((startMinutes - baseMinutes) / 60) * pxPerHour
            // Bordered box matches the actual scheduled time — no minimum.
            // Text content has its natural height and may extend below.
            let slotHeight = max(4, ((endMinutes - startMinutes) / 60) * pxPerHour - 4)

            // Column geometry — each event takes 1/N of available width.
            let columnGap: CGFloat = columnCount > 1 ? 6 : 0
            let columnWidth = (availableWidth - columnGap * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            let xInColumns = CGFloat(column) * (columnWidth + columnGap)

            let isPast    = end < now
            let isCurrent = start <= now && end > now

            let titleOpacity: Double = isPast ? 0.35 : 1.0

            // Border colour/style varies with the user's response to the invite.
            // Current event always wins (orange) so you can spot what's now.
            // pending  → amber          → "you haven't responded yet"
            // tentative→ amber, dashed  → "soft commit"
            // accepted/nil → green      → default
            let amber = Color(red: 0.95, green: 0.70, blue: 0.20)
            let status = event.myStatus
            let isPending   = status == "pending"
            let isTentative = status == "tentative"

            let borderColor: Color = {
                if isCurrent { return .orange }
                if isPending || isTentative { return amber }
                return .green
            }()
            let borderWidth: CGFloat = isCurrent ? 2 : 1.2
            let dashPattern: [CGFloat]? = isTentative ? [4, 3] : nil
            let fillColor: Color = {
                if isCurrent { return Color.orange.opacity(0.08) }
                if isPending || isTentative { return amber.opacity(0.05) }
                return Color.green.opacity(0.05)
            }()

            // When this event's slot is too short for its text content, the
            // text overflows below the slot box. The bottom border at the
            // slot bottom would otherwise cut through the overflowing text.
            // Instead, we draw the bottom border with a gap precisely where
            // the text sits — measured via NSFont metrics — and continue the
            // border on either side of the text.
            let hasOwnOverflow = slotHeight < Self.estimatedTextHeight
            let drawTop = !hasOverflowAbove
            let bottomGap: ClosedRange<CGFloat>? = hasOwnOverflow
                ? Self.gap(forText: event, columnWidth: columnWidth)
                : nil

            ZStack(alignment: .topLeading) {
                // Fill clipped to the slot rectangle (independent of border).
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)
                    .frame(width: columnWidth, height: slotHeight)
                // Border with edges selectively drawn.
                EventBorder(cornerRadius: 6, drawTop: drawTop, drawBottom: true,
                            bottomGap: bottomGap)
                    .stroke(borderColor,
                            style: StrokeStyle(lineWidth: borderWidth,
                                               lineCap: .butt,
                                               dash: dashPattern ?? []))
                    .frame(width: columnWidth, height: slotHeight)

                // Text content — natural height, overflows below the box for
                // short meetings. No border around the overflow.
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(format(start)) – \(format(end))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
                        .monospacedDigit()
                    Text(event.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let loc = event.location, !loc.isEmpty {
                        Text(loc)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.gray.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: columnWidth, alignment: .topLeading)
            }
            .opacity(titleOpacity)
            .offset(x: gutterWidth + 12 + xInColumns, y: y)
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

    // MARK: - Shapes

    /// A border with independently-controllable top and bottom edges.
    /// Sides are always drawn; rounded corners only appear adjacent to an
    /// edge that IS drawn. The bottom edge can carry a `bottomGap` range
    /// (x-coordinates relative to the rect's left edge) inside which the
    /// border is NOT drawn — used so the bottom edge doesn't cut through
    /// overflowing text.
    fileprivate struct EventBorder: Shape {
        let cornerRadius: CGFloat
        let drawTop: Bool
        let drawBottom: Bool
        let bottomGap: ClosedRange<CGFloat>?

        func path(in rect: CGRect) -> Path {
            var p = Path()
            let r = min(cornerRadius, min(rect.width, rect.height) / 2)

            // Top edge (with rounded corners) — drawn only if drawTop.
            if drawTop {
                p.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
                p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                               control: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
                p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                               control: CGPoint(x: rect.maxX, y: rect.minY))
            }

            // Left edge.
            let leftTop    = drawTop    ? rect.minY + r : rect.minY
            let leftBottom = drawBottom ? rect.maxY - r : rect.maxY
            p.move(to: CGPoint(x: rect.minX, y: leftTop))
            p.addLine(to: CGPoint(x: rect.minX, y: leftBottom))

            // Right edge.
            let rightTop    = drawTop    ? rect.minY + r : rect.minY
            let rightBottom = drawBottom ? rect.maxY - r : rect.maxY
            p.move(to: CGPoint(x: rect.maxX, y: rightTop))
            p.addLine(to: CGPoint(x: rect.maxX, y: rightBottom))

            // Bottom edge (with rounded corners + optional middle gap).
            if drawBottom {
                // Bottom-right rounded corner.
                p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
                p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                               control: CGPoint(x: rect.maxX, y: rect.maxY))

                let cornerLeft  = rect.minX + r
                let cornerRight = rect.maxX - r

                if let gap = bottomGap {
                    // Gap range is in rect-local coordinates; shift to absolute x.
                    let gapStart = rect.minX + gap.lowerBound
                    let gapEnd   = rect.minX + gap.upperBound

                    // Right-side segment, if any straight space remains right of the gap.
                    if gapEnd < cornerRight {
                        p.addLine(to: CGPoint(x: max(gapEnd, cornerLeft), y: rect.maxY))
                    }
                    // Jump across the gap.
                    let leftSegmentStart = min(gapStart, cornerRight)
                    if leftSegmentStart > cornerLeft {
                        p.move(to: CGPoint(x: leftSegmentStart, y: rect.maxY))
                        p.addLine(to: CGPoint(x: cornerLeft, y: rect.maxY))
                    } else {
                        p.move(to: CGPoint(x: cornerLeft, y: rect.maxY))
                    }
                } else {
                    p.addLine(to: CGPoint(x: cornerLeft, y: rect.maxY))
                }

                // Bottom-left rounded corner.
                p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                               control: CGPoint(x: rect.minX, y: rect.maxY))
            }

            return p
        }
    }

    // MARK: - Overlap layout

    /// One event positioned into a column within its overlap cluster.
    fileprivate struct LaidOutEvent: Identifiable {
        let event: CalendarEvent
        let column: Int            // 0-based column within the cluster
        let columnCount: Int       // total columns in this event's cluster
        let hasOverflowAbove: Bool // previous event in this column has text spilling into ours
        var id: String { event.id }
    }

    /// Conservative estimate of the height an event's text content occupies.
    /// Time line (11pt) + title (16pt, up to 2 lines) + location (12pt) + spacing + padding.
    fileprivate static let estimatedTextHeight: CGFloat = 56

    /// Computes the bottom-edge gap range for an event whose text overflows
    /// below its slot. The gap is positioned at the text's actual horizontal
    /// extent (left padding → rightmost edge of the widest text line),
    /// capped at the inner column width minus padding on each side.
    fileprivate static func gap(forText event: CalendarEvent, columnWidth: CGFloat) -> ClosedRange<CGFloat> {
        let leftPadding: CGFloat = 10
        let rightPadding: CGFloat = 10
        let innerWidth = max(0, columnWidth - leftPadding - rightPadding)

        // Measure each text element at its actual font; the widest determines
        // the gap (so the gap covers wherever text *could* be at that y).
        let timeFont     = NSFont.systemFont(ofSize: 11, weight: .regular)
        let titleFont    = NSFont.systemFont(ofSize: 16, weight: .medium)
        let locationFont = NSFont.systemFont(ofSize: 12, weight: .regular)

        var widest: CGFloat = 0
        let timeText = "00:00 – 00:00"  // representative width for the time line
        widest = max(widest, (timeText as NSString).size(withAttributes: [.font: timeFont]).width)
        widest = max(widest, (event.title as NSString).size(withAttributes: [.font: titleFont]).width)
        if let loc = event.location, !loc.isEmpty {
            widest = max(widest, (loc as NSString).size(withAttributes: [.font: locationFont]).width)
        }

        let effectiveWidth = min(widest, innerWidth)
        // Add a small visual breathing margin so the gap isn't flush against text.
        let margin: CGFloat = 4
        let start = max(0, leftPadding - margin)
        let end   = min(columnWidth, leftPadding + effectiveWidth + margin)
        return start...end
    }

    /// Greedy interval-column assignment:
    /// - Sort events by start time.
    /// - Group transitively overlapping events into clusters.
    /// - Within each cluster, place each event in the first column whose
    ///   previous occupant has finished. New column if none free.
    /// - All events in a cluster share its columnCount, so they render
    ///   at consistent widths side-by-side.
    fileprivate static func layout(events: [CalendarEvent]) -> [LaidOutEvent] {
        struct Dated {
            let event: CalendarEvent
            let start: Date
            let end: Date
        }
        let dated: [Dated] = events.compactMap { e in
            guard let s = e.startDate, let n = e.endDate else { return nil }
            return Dated(event: e, start: s, end: n)
        }.sorted { $0.start < $1.start }

        var result: [LaidOutEvent] = []
        var clusterStart = 0
        var clusterMaxEnd: Date? = nil
        var columnEnds: [Date] = []      // each column's last-event-end
        var clusterAssignments: [Int] = []  // column index per event in cluster

        // Per column, the previous event's duration + end-time, used to
        // decide whether overflow text from above passes through our top edge.
        var lastEventPerColumn: [Int: (duration: TimeInterval, end: Date)] = [:]
        // Events shorter than this almost certainly have text overflowing
        // below their slot at typical timeline scales (60–90 px/hour).
        let shortEventThreshold: TimeInterval = 30 * 60     // 30 minutes
        let adjacentTolerance:   TimeInterval = 60          // ≤ 1 min gap counts as "directly above"

        func flushCluster() {
            let columnCount = max(1, columnEnds.count)
            for offset in 0..<clusterAssignments.count {
                let absoluteIndex = clusterStart + offset
                let col  = clusterAssignments[offset]
                let item = dated[absoluteIndex]

                var overflowAbove = false
                if let prev = lastEventPerColumn[col],
                   prev.duration < shortEventThreshold,
                   item.start.timeIntervalSince(prev.end) <= adjacentTolerance {
                    overflowAbove = true
                }

                result.append(LaidOutEvent(
                    event: item.event,
                    column: col,
                    columnCount: columnCount,
                    hasOverflowAbove: overflowAbove
                ))

                lastEventPerColumn[col] = (
                    duration: item.end.timeIntervalSince(item.start),
                    end: item.end
                )
            }
            columnEnds = []
            clusterAssignments = []
        }

        for (i, item) in dated.enumerated() {
            if let maxEnd = clusterMaxEnd, item.start < maxEnd {
                // Continue current cluster.
                clusterMaxEnd = max(maxEnd, item.end)
            } else {
                // Flush previous cluster, start new one.
                flushCluster()
                clusterStart = i
                clusterMaxEnd = item.end
            }
            // Assign to first column whose last event ends ≤ this event's start.
            var assigned = false
            for (col, end) in columnEnds.enumerated() {
                if end <= item.start {
                    columnEnds[col] = item.end
                    clusterAssignments.append(col)
                    assigned = true
                    break
                }
            }
            if !assigned {
                clusterAssignments.append(columnEnds.count)
                columnEnds.append(item.end)
            }
        }
        flushCluster()
        return result
    }
}
