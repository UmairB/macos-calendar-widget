import ScreenSaver
import SwiftUI
import AppKit

@objc(CalendarSaverView)
final class CalendarSaverView: ScreenSaverView {

    private var hostingView: NSHostingView<Dashboard>!
    private var model = DashboardModel()

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 30.0   // re-evaluate twice a minute
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 30.0
        commonSetup()
    }

    private func commonSetup() {
        let dashboard = Dashboard(payload: model.payload, now: model.now)
        hostingView = NSHostingView(rootView: dashboard)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        refresh()
    }

    override func startAnimation() {
        super.startAnimation()
        refresh()
    }

    override func animateOneFrame() {
        refresh()
    }

    private func refresh() {
        model.reload()
        hostingView.rootView = Dashboard(payload: model.payload, now: model.now)
        NSLog("CALENDARSAVER: refresh now=\(model.now) today=\(model.payload?.today.count ?? -1)")
    }
}

/// Decodes the JSON written by CalendarRefresh from the bundle Resources directory.
final class DashboardModel {
    private(set) var payload: EventsPayload?
    private(set) var now: Date = Date()

    func reload() {
        now = Date()
        guard let resources = Bundle(for: CalendarSaverView.self).resourceURL else { return }
        let url = resources.appendingPathComponent("events.json")
        do {
            let data = try Data(contentsOf: url)
            payload = try JSONDecoder().decode(EventsPayload.self, from: data)
        } catch {
            NSLog("CALENDARSAVER: decode/read failed: \(error.localizedDescription)")
            payload = nil
        }
    }
}
