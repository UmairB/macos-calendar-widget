# Notes — what we tried, what failed, what we learned

This file exists so that future-me (or a future maintainer) doesn't have to
re-discover any of these. Each section is a thing that surprised us, with
enough context to judge edge cases.

## 1. EventKit calls from inside legacyScreenSaver are blocked

**Symptom**: Calling `EKEventStore.requestFullAccessToEvents` from a
`ScreenSaverView` subclass returns with this error to its completion handler:

```
Error Domain=NSMachErrorDomain Code=4099
"The operation couldn't be completed. (mach error 4099)"
```

Internally the system logs:

```
[com.apple.calendar.daemon:CADXPCProxyHelper] Received error from calaccessd
connection: Error Domain=NSCocoaErrorDomain Code=4099
[com.apple.eventkit:EventKit] Error loading access: Error Domain=NSMachErrorDomain
Code=4099
```

**Root cause**: macOS 26's `legacyScreenSaver` is sandboxed (`AppSandbox`
appears in its launch log). The sandbox profile denies the Mach lookup
`com.apple.CalendarAgent` (visible in kernel sandbox log:
`Sandbox: legacyScreenSaver(NNNN) deny(1) mach-lookup com.apple.CalendarAgent`).
EventKit cannot open the XPC connection to `calaccessd`, and the error
bubbles up as Mach error 4099 (`MACH_SEND_INVALID_DEST`).

**Consequence**: No EventKit, no Contacts, no Reminders, no FileVault, no
anything that needs daemons reachable via Mach lookup. The screensaver is a
purely passive display.

**Workaround**: Run EventKit in a process that is NOT sandboxed (the
`CalendarRefresh` helper, launched by the user's LaunchAgent), and pass data
to the saver via a file the saver can read.

## 2. NSHomeDirectory() inside the sandbox returns a container path, not the user home

**Symptom**: The first version of the test saver did:

```swift
let path = (NSHomeDirectory() as NSString)
    .appendingPathComponent("Library/Application Support/CalendarSaver/events.json")
```

…and reported the file wasn't there, despite the helper definitely writing it
at `/Users/umairb/Library/Application Support/CalendarSaver/events.json`.

**Root cause**: For sandboxed processes, `NSHomeDirectory()` returns the
process's data container path, not the real user home. For
`legacyScreenSaver` it resolves to something under
`~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/`.
The saver was looking at a directory that simply doesn't have our JSON.

**Workaround**: Always use `Bundle(for: type(of: self)).resourceURL` to locate
files. This returns the **actual** on-disk location the saver was loaded
from, which is guaranteed readable by the sandbox (you can't run code you
can't read).

## 3. Modifying a bundle's Resources breaks its code signature, and Tahoe hides invalid bundles from the picker

**Symptom**: After `make install` of the polished saver, it didn't appear in
System Settings → Screen Saver. The test saver did. `codesign --verify`
reported:

```
/Users/umairb/Library/Screen Savers/CalendarSaver.saver: a sealed resource is
missing or invalid
file added: ...Resources/events.json
```

**Root cause**: `codesign` seals all files under `Contents/`, including
`Resources/`. When the helper writes `events.json` into `Resources/`
post-install, the seal is broken. macOS 26 stopped showing invalid-signature
bundles in the screensaver picker (Sonoma was more lenient).

**Workaround**: The helper runs `codesign --force --sign - --timestamp=none`
on each affected bundle immediately after writing `events.json`. Ad-hoc
re-signing is fast (~50ms) and the helper is unsandboxed, so it has write
access to `~/Library/Screen Savers/`. See `CalendarRefresh.swift`.

**Why not Developer ID + notarisation?** That would let us sign once
properly and the signature would remain valid as long as the bundle
contents matched the original seal — except we WANT to modify the bundle
every minute, so the seal would still be invalidated. So this only helps if
you stop putting the JSON inside the bundle. The other places we could put
it (anywhere in the user's home) are blocked by the sandbox profile. Bundle
Resources is the path that works.

## 4. legacyScreenSaver caches loaded bundles in memory across activations

**Symptom**: Edited the saver source, ran `make install`, triggered the
screensaver — saw the OLD behaviour. The saver code wasn't picked up.
Confirmed the on-disk binary contained the new code via `strings`. But the
running screensaver was using something stale.

**Root cause**: macOS Tahoe keeps `legacyScreenSaver` processes alive between
screensaver activations. We saw the same PIDs (11015, 11016) handling
screensaver activations 3 days apart. The `.saver` bundle is loaded once into
the process and the loaded code stays in memory.

**Workaround**: `pkill -9 -f legacyScreenSaver` after each install. macOS
respawns a fresh process on next activation, which loads the new bundle from
disk. The `CalendarSaver/Makefile`'s `make reload` target does install + kill
+ helper-run in one step.

## 5. Hot Corner: "Start Screen Saver" vs "Lock Screen"

**Symptom**: Clicking the Apple-menu "Lock Screen" item (or Ctrl+Cmd+Q)
sends the Mac to the login window, NOT to the screensaver. The display then
sleeps and the calendar is never visible.

**Root cause**: macOS treats the login window and the screensaver as
completely separate UI contexts. The login window runs *before* a user
session and only Apple's built-in content can render there — no third-party
`.saver` bundles, ever. Apple has never opened this surface.

**Workaround**: Use a Hot Corner set to **"Start Screen Saver"** (System
Settings → Desktop & Dock → Hot Corners). Combined with "Require password
immediately after screensaver begins," this gives you the lock-with-calendar
behaviour. The actual Lock Screen menu item is the wrong tool.

## 6. TCC cdhash invalidation on rebuild

**Symptom**: After rebuilding the helper, the next run prompts for Calendar
access again, even though you already granted it.

**Root cause**: TCC (the macOS permission system) identifies ad-hoc-signed
binaries by their `cdhash` — a hash of the binary's code segments. Every
rebuild produces a slightly different binary (timestamps, dyld metadata) and
therefore a different `cdhash`. TCC sees "new binary, no record" and
re-prompts.

**Workaround**: Live with it. The prompt only fires on the helper, which
runs from the LaunchAgent — so when the helper rebuilds, the next scheduled
run is silent unless you've also done a manual `make run` from a TTY (which
is the path that surfaces the prompt). To eliminate this entirely you'd need
to sign with a stable Developer ID (~$99/yr Apple developer account).

## 7. Weather data source choice — keyless vs. "same as macOS Weather app"

**Question**: Where should weather come from?

**The candidates considered**:

- **Apple WeatherKit** (the macOS Weather app's source). Requires a paid
  Apple Developer account, a registered Service ID, a `.p8` signing key, and
  per-request JWT signing. "No API key" is technically true but the
  credential burden is equivalent — and we're ad-hoc signing everything else
  in this project, so adding an Apple Developer prerequisite contradicted
  the project's "self-contained, no paid prerequisites" posture.
- **OpenWeatherMap** — needs an API key. Free tier limited. Key rotation
  becomes a chore.
- **wttr.in** — keyless but a hobby project; unreliable historically.
- **Open-Meteo** — what we picked. Keyless. No signup. EU-based
  (`Open-Meteo Authority B.V.`). Used widely in open-source weather tools.
  Aggregates from the same upstream sources as Apple (ECMWF, DWD, NOAA,
  MeteoFrance).

**Implementation**: HTTP GET against `api.open-meteo.com/v1/forecast`,
synchronous via a semaphore (consistent with the EventKit pattern in the
helper). 15-minute cache: each helper run reads the previous
`events.json`, and reuses the embedded weather if its `fetchedAt`
timestamp is < 15 min old. Otherwise refetches. This avoids one network
call per minute.

**Failure modes**: If Open-Meteo is unreachable, `fetchWeather()` returns
nil and that run's payload has no weather block — the saver simply omits
that section. Next minute's run tries again. If the cache is still fresh
(< 15 min), the cached value is used regardless of network state. (A
future improvement could fall back to a stale cache on fetch failure;
right now it doesn't.)

## Things tried that we threw out

- **icalBuddy** — a popular CLI that reads Calendar.app's local store.
  Lightly maintained (last meaningful release ~4 years ago) and relies on
  internal Calendar database formats that Apple changes occasionally.
  Replaced with a 100-line Swift CLI that uses EventKit directly.
- **WebViewScreenSaver** — an actively maintained third-party screensaver
  that renders a URL as the screensaver. Ad-hoc signed. Would have worked,
  but the combination of (a) trust profile of an unknown developer's binary
  and (b) the screenSaver+local-HTML+launchd-regenerator architecture being
  ugly led us to write our own.
- **Reading `~/Library/Application Support/CalendarSaver/events.json` from
  the saver directly** — blocked by the sandbox, even when using an absolute
  hardcoded path. The bundle-Resources approach is the only file path the
  sandbox always permits.
- **Stripping `com.apple.quarantine` on downloaded binaries** — I did this
  once with the WebViewScreenSaver download and shouldn't have. Quarantine
  exists so the user gets a chance to evaluate the binary. Don't do this
  silently. Mentioning here so future-me doesn't repeat the mistake.
