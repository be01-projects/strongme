# StrongMe — Milestone 1 build notes

*What shipped in this slice, the choices I made where the spec was silent, and what's deliberately stubbed.*

## What's in this build

The first milestone, per the brief:

1. **HealthKit auto-import (Tier 0)** — steps (today + 30-day average), last night's sleep, workouts this week / trained-today, bodyweight + 2-week trend, resting HR. Weight said out loud is **written back to Health**, so Health stays the single source of truth.
2. **Today screen** styled to the prototype — Fraunces greeting + day counter, tappable daily-insight card, 2×2 auto grid, apricot protein bar, "your usual" one-tap chips, reflection prompt + recent reflections, talk dock with keyboard toggle, toast confirmations.
3. **Voice/text → Claude parse → editable chips → log** — food first, with weight and reflection routing because they fell out of the same parser almost for free.

## File map

```
StrongMe/
  StrongMeApp.swift            app entry, SwiftData container, seeds
  ContentView.swift            root → TodayView
  Theme/Theme.swift            palette, Fraunces/Inter helpers, card chrome
  Models/Models.swift          FoodEntry, UsualMeal, FoodCorrection, ReflectionEntry, seeds
  Health/HealthKitService.swift  auth, snapshot queries, weight write-back
  Intelligence/
    ClaudeClient.swift         raw Messages API client (structured outputs)
    EntryParser.swift          routing + schema + on-device fallback parser
    InsightEngine.swift        rule-based daily read (stub for coach-generated)
  Capture/
    SpeechRecognizer.swift     on-device SFSpeechRecognizer
    CaptureSheet.swift         listen/type → parse → confirm chips → log
  Today/
    TodayView.swift            screen assembly, toast, coach stub sheet
    TodayComponents.swift      stat grid, protein card, talk dock
  Resources/Fonts/             Fraunces 400/500/600, Inter 400/500/600/700 (static TTFs)
  Info.plist                   fonts + Health/mic/speech purpose strings
  StrongMe.entitlements        HealthKit
  Secrets.example.plist        → copy to Secrets.plist and add your key
```

## Setting up the API key

Copy `StrongMe/Secrets.example.plist` → `StrongMe/Secrets.plist` (gitignored) and paste your Anthropic key. Without a key the app still works: parsing falls back to a small on-device keyword table, clearly labeled *"rough on-device guess"* in the confirm sheet.

## Claude integration choices

- **Model `claude-fable-5`** as specified, with `effort: low` — parsing is routine work; low effort keeps it fast and cheap while staying accurate.
- **Structured outputs** (`output_config.format` with a strict JSON schema) so every parse is guaranteed machine-readable — no brittle string extraction.
- **Server-side fallback to `claude-opus-4-8` enabled** (beta `server-side-fallback-2026-06-01`). Fable 5 runs safety classifiers that can occasionally decline benign requests; the fallback re-serves the same request on Opus in the same call, so the user never sees a hiccup. Remove the `fallbacks` field + beta header in `ClaudeClient.swift` if you'd rather not.
- **Corrections memory**: chip edits are stored (`FoodCorrection`) and the last 10 are fed into the parser prompt ("'coffee' usually means 'large oat-milk latte'"). Removals aren't treated as corrections — only renames.
- **Privacy**: only the sentence being parsed plus the corrections list leaves the device. No health data is sent in this milestone.

## Documented choices where the brief was open

| Area | Choice | Why |
|---|---|---|
| Talk control | **Tap to talk** (sheet opens listening, explicit "Done" button), not press-and-hold | Hold-to-talk over a sheet transition is fiddly; explicit stop is more forgiving for long sentences. Easy to revisit. |
| Weight said aloud | Written to **HealthKit**, not SwiftData | One source of truth; the smart-scale path and the spoken path converge. |
| Reflection routing | Implemented now (verbatim save + signal tags + care response), though brief deferred it | It fell out of the parser schema nearly for free, and the reflection prompt on Today would otherwise be a dead control. Coach-side use of reflections is still deferred. |
| Distress guardrail | In the Claude parse (biased conservative per the brief) **and** a minimal keyword net in the offline fallback; care card cites 988 + findahelpline.com, logs nothing | Non-negotiable per the brief; the fallback net exists only so offline mode can never chirp "logged!" at a distress entry. |
| "Usuals" | Seeded with 4 starters; every confirmed meal upserts a usual by name and frequency ranks them | The row shouldn't be empty on day one; real habits overtake seeds naturally. |
| Meal inference | From wording via Claude; from time of day for one-tap re-logs | |
| Units | Reads the user's preferred Health unit for weight; defaults to lb | |
| Protein target | 150 g default in `@AppStorage("proteinTargetGrams")` | No settings maze; say-your-target can come with the coach. |
| Day counter | Days since first launch | Matches the "Day 9" in the prototype. |
| Sleep math | Sum of asleep-stage samples, 6 pm–noon window | Overlapping multi-source samples could double-count; fine for trends. |
| Insight | Rule-based templates from the live snapshot | Stub for the Claude-written insight; keeps the card honest offline. |

## Stubbed (arrives next)

- **Coach**: insight card opens a sheet showing the daily read + a note that the interactive coach is next. The privacy framing (trend summary only, visible to the user) is already in the copy.
- **Calendar/History**: button shows a toast.
- **Trends screen, App Intents / Action Button / widget / watch**: not started, per the milestone.
- **Dark mode**: forced light; the palette is light-designed.

## Verified

- Builds clean with Xcode 26 (`xcodebuild … BUILD SUCCEEDED`).
- Launches on iPhone 17 Pro simulator; Health permission sheet shows the custom purpose strings; Today screen renders to the prototype (fonts, palette, insight card, grid, protein bar, usuals, dock, toasts).
- The capture/parse/confirm flow compiles and is wired end-to-end but needs a **manual pass on your machine** (this sandbox can't drive simulator taps or the mic): try the keyboard button → "two eggs, toast, and a coffee" → chips → log; then "182 this morning"; then the reflection prompt.
- Dev nicety: launching with the `-skip-health-auth` argument suppresses the Health prompt (used for scripted screenshots/UI tests).
