# CalendarSaverTest

A minimal macOS screensaver bundle that exists to answer ONE question:

> On macOS 26, does an EventKit calendar read from inside the `legacyScreenSaver`
> sandbox actually return events, or does the sandbox block it?

The answer decides the architecture of the real CalendarSaver. There is no UI,
no styling, no event-loading optimization here — just enough to render the
sandbox result on screen.

## What it does

On `startAnimation`:
1. Calls `EKEventStore.requestFullAccessToEvents` (macOS 14+ API).
2. If granted, queries today's events with `predicateForEvents` and counts them.
3. Renders three lines on a black background: title, status, count (if any).

No network. No file writes outside `~/Library/Screen Savers/`. No third-party
dependencies. Just `ScreenSaver` + `EventKit` + `AppKit`.

## Build

Requires Xcode Command Line Tools (already installed if `xcode-select -p` works).

```
make build
```

Produces `build/CalendarSaverTest.saver`, ad-hoc signed (no Developer ID).

## Install

```
make install
```

Copies the bundle into `~/Library/Screen Savers/`.

## Test

1. **System Settings → Screen Saver** — select "CalendarSaverTest".
2. Trigger it: System Settings → Lock Screen → "Start Screen Saver when
   inactive" → set a short timeout, or use a hot corner.
3. Wait for the screensaver to start.

## Possible outcomes

| Outcome | Interpretation | Next step |
|---|---|---|
| **"Access GRANTED" + count** | Sandbox allows EventKit. Best case. | Build real saver against EventKit directly. |
| **"Access DENIED (or no prompt shown)"** | Either the sandbox blocked the prompt UI, or it allowed the call but you declined a prompt. | Use helper pattern: launchd job writes events to a JSON file outside the sandbox; saver reads the file. |
| **"Error: …"** | EventKit returned a specific error. | Read the error; usually points at TCC permission. |
| **Counter ticks forever** | The prompt was suppressed and no decision recorded. | Same as DENIED — helper pattern. |

## Uninstall

```
make uninstall
```

## Clean

```
make clean
```

Deletes `build/`.

## Files

- `CalendarSaverTestView.swift` — the screensaver view.
- `Info.plist` — bundle metadata + Calendar usage strings.
- `Makefile` — build / install / uninstall / clean.
