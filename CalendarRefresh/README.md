# CalendarRefresh

A small Swift command-line tool that reads today's and tomorrow's events from
EventKit, fetches current weather from Open-Meteo, and writes both as JSON to
a known location for the screensaver to consume. Designed to be invoked once
a minute by a user LaunchAgent.

Exists because the legacy screensaver sandbox on macOS 26 blocks EventKit's
XPC connection (mach error 4099). The screensaver itself can't call EventKit
or make network requests reliably, so this helper bridges the gap: it runs
as your user (outside any sandbox) and leaves a JSON file the saver can read.

## What it does

1. Calls `EKEventStore.requestFullAccessToEvents`.
2. Queries today's and tomorrow's events (start-of-today → start-of-day-after).
3. For each event, reads the current user's attendee status (`accepted` /
   `pending` / `tentative` / `delegated`) — declined invites are dropped.
4. Fetches current temperature, today's high/low, and weather condition from
   Open-Meteo. Cached for 15 minutes (reuses the value from the previous
   `events.json` if still fresh).
5. Writes `~/Library/Application Support/CalendarSaver/events.json`
   atomically (write to `.tmp`, then replace), then mirrors the file into
   every installed `CalendarSaver*.saver` bundle's `Contents/Resources/`
   directory and re-signs each bundle ad-hoc (Tahoe hides invalid-signature
   bundles from the screensaver picker).
6. Exits 0.

If Calendar access is denied or errors, writes a payload with
`"status": "no_access"` or `"status": "error"` and an empty events list,
then exits 0.

The only external network call is to `api.open-meteo.com`. No file writes
outside `~/Library/Application Support/CalendarSaver/` and the installed
`.saver` bundles.

## JSON shape

```json
{
  "generatedAt": "2026-06-26T13:45:00Z",
  "status": "ok",
  "errorMessage": null,
  "today": [
    {
      "title": "Standup",
      "start": "2026-06-26T09:00:00Z",
      "end":   "2026-06-26T09:30:00Z",
      "allDay": false,
      "location": "Zoom",
      "calendar": "Work",
      "myStatus": "accepted"
    }
  ],
  "tomorrow": [],
  "weather": {
    "fetchedAt": "2026-06-26T13:45:00Z",
    "temperatureC": 18.5,
    "highC": 21.2,
    "lowC": 12.1,
    "weatherCode": 1,
    "conditionText": "Mainly clear",
    "conditionIcon": "🌤",
    "label": "MyLocation"
  }
}
```

## Configure location

Before the first build, copy the example config and edit your coordinates:

```
cp Location.swift.example Location.swift
$EDITOR Location.swift
```

`Location.swift` is gitignored, so your real coordinates never get committed.
UK postcodes can be converted to lat/lon via:

```
curl -fsSL "https://api.postcodes.io/postcodes/<YOUR-POSTCODE>"
```

## Build

```
make build
```

Produces `build/calendar-refresh`, an ad-hoc-signed Mach-O executable with
`Info.plist` embedded in the `__TEXT,__info_plist` section. The embedded
plist is what tells TCC to show the Calendar permission prompt.

## Install + run once (to grant permission)

```
make run
```

This installs the binary to
`~/Library/Application Support/CalendarSaver/bin/calendar-refresh` and runs
it once. On first run, macOS will show a Calendar permission prompt. Allow it.
After that, the binary will run silently and write the JSON.

## Schedule it

```
make load
```

Materializes the LaunchAgent plist from the template (substituting `$HOME`),
installs it to `~/Library/LaunchAgents/com.example.calendarrefresh.plist`,
and bootstraps it. It will run at load and then every 60 seconds.

## Unload / uninstall

```
make unload      # stops the LaunchAgent, leaves binary
make uninstall   # unload + remove the binary
make clean       # remove build/
```

## TCC + ad-hoc signing wart

TCC tracks Calendar permission by code signature cdhash for ad-hoc binaries.
Every time you rebuild this tool, the cdhash changes, and TCC forgets the
permission — so the *next* run will prompt again. Annoying, but harmless.
This goes away if you sign with a self-signed code-signing certificate or
an Apple Developer ID. See `NOTES.md` in the repo root.

## Files

- `CalendarRefresh.swift` — the tool (~170 lines).
- `Location.swift.example` — placeholder location config; copy to
  `Location.swift` (gitignored) and edit before building.
- `Info.plist` — embedded into the binary; declares Calendar usage strings.
- `com.example.calendarrefresh.plist.template` — LaunchAgent template with
  `@@HOME@@` placeholder; the Makefile substitutes your actual home.
- `Makefile` — build / install / run / load / unload / uninstall / clean.
