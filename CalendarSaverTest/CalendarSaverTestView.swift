import ScreenSaver
import AppKit
import Foundation

// Step-2 test: instead of calling EventKit (which the sandbox blocks),
// read the JSON file produced by the CalendarRefresh helper and display
// what we got. This proves whether the legacyScreenSaver sandbox allows
// reads from ~/Library/Application Support/.

private struct CalendarEvent: Codable {
    let title: String
    let start: String
    let end: String
    let allDay: Bool
    let location: String?
    let calendar: String
}

private struct EventsPayload: Codable {
    let generatedAt: String
    let status: String
    let errorMessage: String?
    let today: [CalendarEvent]
    let tomorrow: [CalendarEvent]
}

@objc(CalendarSaverTestView)
final class CalendarSaverTestView: ScreenSaverView {

    private var status: String = "Reading events.json…"
    private var payloadSummary: String? = nil
    private var firstEvent: String? = nil

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 5.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 5.0
    }

    override func startAnimation() {
        super.startAnimation()
        readEvents()
    }

    override func animateOneFrame() {
        // Re-read every 5s while screensaver is up, so changes appear.
        readEvents()
        needsDisplay = true
    }

    private func readEvents() {
        // Use the saver's own bundle Resources path — guaranteed readable
        // inside the legacyScreenSaver sandbox.
        guard let resourceURL = Bundle(for: type(of: self)).resourceURL else {
            status = "READ FAILED — no resourceURL"
            payloadSummary = nil
            firstEvent = nil
            NSLog("CALENDARSAVER: no resourceURL from bundle")
            return
        }
        let url = resourceURL.appendingPathComponent("events.json")
        NSLog("CALENDARSAVER: trying to read \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(EventsPayload.self, from: data)
            status = "READ OK — status=\(payload.status)"
            payloadSummary = "today=\(payload.today.count)  tomorrow=\(payload.tomorrow.count)  generated=\(payload.generatedAt)"
            if let first = payload.today.first {
                firstEvent = "\(first.title)  [\(first.calendar)]"
            } else {
                firstEvent = "(no events today)"
            }
            NSLog("CALENDARSAVER: SUCCESS today=\(payload.today.count) tomorrow=\(payload.tomorrow.count)")
        } catch let e as NSError {
            status = "READ FAILED — code=\(e.code) domain=\(e.domain)"
            payloadSummary = e.localizedDescription
            firstEvent = url.path
            NSLog("CALENDARSAVER: read failed code=\(e.code) domain=\(e.domain) desc=\(e.localizedDescription) path=\(url.path)")
        }
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()

        let para = NSMutableParagraphStyle()
        para.alignment = .center

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 40, weight: .light),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .regular),
            .foregroundColor: NSColor.lightGray,
            .paragraphStyle: para,
        ]
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: para,
        ]

        let cx = bounds.midX
        let cy = bounds.midY

        drawCentered("CalendarSaver — Sandbox File Read Test",
                     at: NSPoint(x: cx, y: cy + 140), attrs: titleAttrs)
        drawCentered(status,
                     at: NSPoint(x: cx, y: cy + 60), attrs: bodyAttrs)
        if let s = payloadSummary {
            drawCentered(s, at: NSPoint(x: cx, y: cy + 10), attrs: bodyAttrs)
        }
        if let e = firstEvent {
            drawCentered(e, at: NSPoint(x: cx, y: cy - 40), attrs: bodyAttrs)
        }
        drawCentered("Move mouse or press a key to exit",
                     at: NSPoint(x: cx, y: 40), attrs: dimAttrs)
    }

    private func drawCentered(_ text: String, at point: NSPoint, attrs: [NSAttributedString.Key: Any]) {
        let ns = text as NSString
        let size = ns.size(withAttributes: attrs)
        ns.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y), withAttributes: attrs)
    }
}
