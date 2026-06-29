# CalendarSaver

A macOS screensaver that shows today's calendar as a stylised vertical day
timeline, with current weather in the header. Designed to run on a Mac mini
as an always-on, auto-locking calendar display.

Built for macOS 26 (Tahoe). No third-party dependencies. No API keys.

## What problem this solves

macOS does not natively support widgets or calendar info on the Lock Screen
(unlike iOS). Apple's screensaver framework can host third-party `.saver`
bundles, but those bundles run inside the `legacyScreenSaver` sandbox which
blocks the IPC needed for EventKit. So you can't just call EventKit from a
screensaver and ask for today's events — it fails with `mach error 4099`
(MACH_SEND_INVALID_DEST: sandbox blocked the XPC connection to `calaccessd`).

The architecture below is what works on Tahoe.

## Architecture

```
┌──────────────────────────────┐                       ┌──────────────────────────────┐
│  CalendarRefresh (helper)    │                       │  CalendarSaver (.saver)      │
│                              │                       │                              │
│  Plain Swift CLI binary,     │  writes JSON into     │  ScreenSaverView subclass    │
│  runs as your user           │  the saver bundle's   │  hosting a SwiftUI view via  │
│  (no sandbox).               │  Resources directory  │  NSHostingView.              │
│                              │  ───────────────────► │                              │
│  Calls EventKit.             │                       │  Reads JSON from its OWN     │
│  Writes events.json.         │                       │  Bundle.resourceURL — a path │
│                              │                       │  the sandbox always permits. │
│  Launched once a minute by   │                       │                              │
│  a user LaunchAgent.         │                       │  Renders day timeline.       │
└──────────────────────────────┘                       └──────────────────────────────┘
```

The helper writes the JSON into **every** installed `CalendarSaver*.saver`
bundle's `Contents/Resources/` directory (so test + polished bundles both see
fresh data), then re-signs each bundle ad-hoc — macOS Tahoe hides
invalid-signature bundles from the screensaver picker, so the re-sign is
mandatory after each write. See `NOTES.md` for why.

## Weather

The helper also fetches current weather from **Open-Meteo**
(`api.open-meteo.com`) — keyless, free, EU-based, no signup. Data is cached
for 15 minutes (reused from the previous `events.json` payload) to avoid
hammering the API.

Location is hardcoded as constants near the top of
`CalendarRefresh/CalendarRefresh.swift`:

```swift
let WEATHER_LAT:   Double = 51.473185   // SW11 3ET (Battersea, London)
let WEATHER_LON:   Double = -0.167173
let WEATHER_LABEL: String = "London"
let WEATHER_CACHE_SECONDS: TimeInterval = 15 * 60
```

Edit + `make reload` to change. UK postcodes can be converted to lat/lon
via `https://api.postcodes.io/postcodes/<POSTCODE>`.

We deliberately did NOT use Apple's WeatherKit — it requires a paid Apple
Developer account ($99/yr) and JWT signing, which contradicts the
"no third-party dependencies, no keys" goal. Open-Meteo aggregates from the
same upstream meteorological agencies as Apple does (ECMWF, DWD, NOAA,
MeteoFrance) so the data quality is comparable.

## Repository layout

```
~/Source/CalendarSaver/
  CalendarRefresh/         The unsandboxed helper that reads EventKit.
  CalendarSaverTest/       Minimal diagnostic saver used to prove the
                           architecture (read JSON from sandbox).
                           Keep installed; useful when things break.
  CalendarSaver/           The polished day-timeline screensaver.
  README.md                You are here.
  NOTES.md                 Gotchas, dead-ends, and what we learned.
```

Each subdirectory has its own `README.md` with build details and file-level
docs. This top-level doc covers the end-to-end story.

## End-to-end build / install

From a fresh checkout, run these in order:

```bash
# 1. Build the polished saver first so its Resources/ directory exists
cd ~/Source/CalendarSaver/CalendarSaver
make install                                  # builds bundle, installs to ~/Library/Screen Savers/

# 2. Build the test saver (optional but useful for diagnosing future issues)
cd ~/Source/CalendarSaver/CalendarSaverTest
make install

# 3. Build helper, run once to grant Calendar access, then schedule it
cd ~/Source/CalendarSaver/CalendarRefresh
make run        # builds, installs, runs once — triggers macOS Calendar permission prompt. Click Allow.
make load       # bootstraps the LaunchAgent so it refreshes every 60 seconds
```

After step 3 the helper will populate `events.json` inside both saver bundles
and re-sign them so they're picker-visible.

## macOS configuration done manually

These are settings I made by hand outside this repo. They're not automated by
the Makefiles because they need either `sudo` (interactive password prompt)
or System Settings clicks.

### Power management (`sudo pmset`)

```bash
sudo pmset -a displaysleep 0
sudo pmset repeat sleep MTWRFSU 23:00:00 wakeorpoweron MTWRFSU 07:00:00
```

| Setting          | Value    | Effect                                                            |
| ---              | ---      | ---                                                               |
| `displaysleep`   | `0`      | Display never sleeps from idle — the screensaver runs uninterrupted |
| `sleep`          | `0`      | System never sleeps from idle (already 0 by default on Mac mini)  |
| repeat sleep     | 23:00 daily | Full system sleep every night                                  |
| repeat wakepoweron | 07:00 daily | Wake every morning                                           |

Verify with `pmset -g | grep -E "displaysleep|^ sleep "` and `pmset -g sched`.

### System Settings → Screen Saver

- Picked **"Calendar Saver"** from the list (not "CalendarSaverTest").
- Set **"Start Screen Saver when inactive"** to a short idle delay.

### System Settings → Lock Screen

- Set **"Require password after screen saver begins or display is turned off"**
  to **Immediately**. This makes the screensaver act as a lock — the calendar
  is visible but unlocking requires a password.

### System Settings → Desktop & Dock → Hot Corners

- Set one corner (e.g. top-right) to **"Start Screen Saver"** (NOT "Lock
  Screen" — that bypasses the screensaver and goes straight to the login
  window, which can't host third-party savers).
- Flick the cursor to that corner when walking away to lock manually.

Verify with:

```bash
defaults read com.apple.dock wvous-tr-corner   # 5 = Start Screen Saver
```

## Daily operation

Once installed and configured, the system works like this:

1. **Idle** → screensaver activates after the inactivity delay.
2. **Calendar Saver shows** the day timeline with live calendar data
   (refreshed every 60 seconds by the helper LaunchAgent).
3. **Move mouse / press key** → screensaver dismisses → password required
   (because of the Lock Screen setting).
4. **23:00 → 07:00** → system sleeps overnight via `pmset repeat`.

The helper writes a log to
`~/Library/Application Support/CalendarSaver/refresh.log` and also keeps a
visibility copy of the JSON at
`~/Library/Application Support/CalendarSaver/events.json`.

## Troubleshooting

If the screensaver shows wrong data, the wrong screensaver, or doesn't appear
in the picker, the most common causes are:

| Symptom                                       | Cause                                            | Fix                                                  |
| ---                                           | ---                                              | ---                                                  |
| Polished saver not in picker                  | Tahoe caches the picker list                     | Cmd+Q System Settings, reopen                        |
| Polished saver not in picker, bundle invalid  | Resources modified after signing, seal broken    | Helper auto-fixes on next run; or `make reload`      |
| Old behaviour after editing saver code        | `legacyScreenSaver` caches loaded bundles in memory | `pkill -9 -f legacyScreenSaver` (or `make reload`) |
| Empty events / "no calendar access"           | Calendar permission revoked                      | Run `~/Library/Application Support/CalendarSaver/bin/calendar-refresh` once in Terminal, click Allow |
| Display sleeps in the middle of screensaver   | `displaysleep` reverted                          | `sudo pmset -a displaysleep 0`                       |

`NOTES.md` has deeper detail on each of these and the reasoning behind the
architecture.

## Uninstall

```bash
cd ~/Source/CalendarSaver/CalendarRefresh && make uninstall   # unloads LaunchAgent, removes helper binary
cd ~/Source/CalendarSaver/CalendarSaver     && make uninstall
cd ~/Source/CalendarSaver/CalendarSaverTest && make uninstall

# Optional: revert the manual changes
sudo pmset -a displaysleep 10      # macOS default
sudo pmset repeat cancel            # clear overnight schedule
rm -rf "$HOME/Library/Application Support/CalendarSaver"
```

In System Settings, pick a different Screen Saver, reset the Lock Screen
password timing, and clear the Hot Corner if you no longer want it.
