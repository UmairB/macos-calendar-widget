# CalendarRefresh

A small Swift command-line tool that reads today's and tomorrow's events from
EventKit and writes them to a JSON file. Designed to be invoked once a minute
by a user LaunchAgent.

Exists because the legacy screensaver sandbox on macOS 26 blocks EventKit's
XPC connection (mach error 4099). The screensaver itself can't call EventKit,
so this helper bridges the gap: it runs as your user (outside any sandbox)
and leaves a JSON file the saver can read.

## What it does

1. Calls `EKEventStore.requestFullAccessToEvents`.
2. Queries today's events (start-of-today → start-of-tomorrow).
3. Queries tomorrow's events (start-of-tomorrow → start-of-day-after).
4. Writes `~/Library/Application Support/CalendarSaver/events.json`
   atomically (write to `.tmp`, replace).
5. Exits 0.

If access is denied or errors, writes a payload with `"status": "no_access"`
or `"status": "error"` and an empty events list, then exits 0. The saver can
then render a clear message instead of just failing silently.

No network calls. No file writes outside
`~/Library/Application Support/CalendarSaver/`.

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
      "calendar": "Work"
    }
  ],
  "tomorrow": []
}
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
installs it to `~/Library/LaunchAgents/com.umairb.calendarrefresh.plist`,
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
This goes away if you sign with a Developer ID.

## Files

- `CalendarRefresh.swift` — the tool (~110 lines).
- `Info.plist` — embedded into the binary; declares Calendar usage strings.
- `com.umairb.calendarrefresh.plist.template` — LaunchAgent template with
  `@@HOME@@` placeholder; the Makefile substitutes your actual home.
- `Makefile` — build / install / run / load / unload / uninstall / clean.
