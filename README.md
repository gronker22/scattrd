# scattrd

A local-only macOS menubar app that measures **attention quality**, not just time.
It watches which app is in front, records uninterrupted focus blocks, and turns
your day into a single **Focus Score (0–100)**.

> Your data never leaves your Mac. No cloud, no account, no network calls.

## What works in v1

- **Live Focus Score** in the menubar, color-coded (green / orange / red).
- **Context-switch tracking** — every 5 seconds, with idle detection
  (away-from-keyboard time is excluded). App-level, plus browser-tab domains
  when enabled.
- **Dropdown dashboard** — today's switches, average focus length, longest streak,
  deep-work blocks, and a **Distraction Leaderboard** of your top focus killers.
- **Daily Summary notification** — a Spotify-Wrapped-style nudge at a time you pick
  (default 5pm), leading with one striking, personalized stat. Plus an on-demand
  recap and a "Send Test Summary Now" button. Requires running `scattrd.app`.
- **Focus Replay dashboard** — opens in its **own native app window** (a built-in
  web view, not your browser) with a scrubbable day timeline, an hourly attention
  curve, the distraction leaderboard, and 7-day weekly patterns + a
  morning/afternoon focus fingerprint. Rendered locally; never leaves your Mac.
- **SQLite storage** at `~/Library/Application Support/scattrd/focus.sqlite`.
- **Browser tab tracking** — in Safari / Chrome / Arc / Brave / Edge it records the
  active tab's **domain** (only the domain, never the full URL) and categorizes it,
  so `youtube.com` counts as distraction, `github.com` as deep work — and tab
  switches finally register as real context switches. One-time Automation
  permission; falls back to app-level if declined or unsupported (Firefox).
- **Launch at login** — a toggle in the menu (standard macOS login item).
- **Local & private by default.** Core tracking needs **zero permissions**. Browser-tab
  tracking is opt-in (Automation) and stores only domains. Nothing ever leaves your Mac.

## The Focus Score

Weighted blend of three 0–100 sub-scores (see `FocusScore.swift`):

| Sub-score | Rewards | Weight |
|-----------|---------|--------|
| Sustain   | Longer average focus blocks (20 min = perfect)        | 40% |
| Switching | Fewer switches per hour (exponential decay)           | 35% |
| Deep work | A long unbroken streak (45 min = perfect)             | 25% |

All constants live at the top of `FocusScore.swift` — easy to tune.

## Build & run

```bash
./install.sh            # builds + installs to /Applications + launches (recommended)
# — or, to build without installing —
./build_app.sh          # builds ./scattrd.app, then:
open scattrd.app    # launches into the menubar (look for the 🧠 icon)
```

> SwiftPM (`swift build`) does **not** work on this machine — the build compiles
> with `swiftc` directly plus a toolchain workaround. See the top of `build_app.sh`.

A 🧠 icon with a number appears in the menubar. Give it ~5 minutes of real work,
then click it.

## Known v1 limitations

- **Firefox tabs aren't readable** (Firefox isn't scriptable for tab URLs), so it
  falls back to app-level tracking. Safari and all Chromium browsers work.
- **Tab tracking runs an AppleScript every 5s** on the main thread; the first call
  to each browser triggers the one-time "control [browser]" permission prompt.
- The 5pm daily-summary notification isn't scheduled yet (summary is on-demand).
- The dashboard is a snapshot generated when you open it — reopen it to refresh.

## Roadmap (build order)

1. ✅ Background tracker + SQLite storage
2. ✅ Fragmentation / focus score
3. ✅ Menubar icon with live score + today's breakdown
4. ✅ Daily summary notification (scheduled, Spotify-Wrapped style)
5. ✅ Full dashboard: Focus Replay timeline + weekly patterns
6. ✅ Browser tab-level tracking (Automation opt-in) + launch at login
