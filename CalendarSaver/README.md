# CalendarSaver

The polished day-timeline screensaver.

## What it looks like

Vertical day timeline against a black background:

- Big clock + date in the header.
- Hour gutter down the left, faint horizontal grid lines.
- Event blocks positioned by start/end time; height proportional to duration.
- Past events at 35% opacity. Current event (the one the "now" line crosses)
  gets a brighter orange border.
- Thin orange "now" line + dot ticks down through the day.
- Empty day: "Nothing scheduled today" centered.

Default visible range: **08:00 → 20:00**. Auto-extends if any of today's
events fall outside that.

## How it gets data

It does NOT call EventKit (the legacy screensaver sandbox blocks the XPC
needed for that — confirmed via `mach error 4099`). Instead:

1. The CalendarRefresh LaunchAgent runs once a minute as your user.
2. It reads EventKit and writes JSON into this bundle's own Resources dir
   (`~/Library/Screen Savers/CalendarSaver.saver/Contents/Resources/events.json`).
3. This saver reads that JSON via `Bundle(for: self).resourceURL` — a path
   the sandbox always permits.

## Build / install

```
make install      # build + copy into ~/Library/Screen Savers/
make reload       # install + kill cached legacyScreenSaver + run helper
make uninstall    # remove
make clean        # blow away build/
```

`make reload` is the one to use after editing code — it forces macOS to load
the new binary on the next screensaver activation.

## Files

- `CalendarSaverView.swift` — `ScreenSaverView` subclass hosting SwiftUI.
- `Dashboard.swift` — the SwiftUI day-timeline view.
- `Models.swift` — `Codable` types for the JSON payload.
- `Info.plist` — bundle metadata. `NSPrincipalClass = CalendarSaverView`.
- `Makefile` — build / install / reload / uninstall / clean.
