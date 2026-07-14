# StrongMe — build notes

*What shipped in each slice, the choices made where the spec was silent, and what's deliberately stubbed.*

---

# Milestone 2.5 — experience polish

Seven fixes that close the gap between "works" and "feels effortless", before moving to system entry points:

1. **Chip fixes now fix this log.** Renaming a chip ("coffee" → "large oat latte") re-estimates its protein/calories via a tiny single-item Claude call (local table fallback), so the macros correct immediately — previously only *future* parses learned. The macro line shows "updating estimate…" while it resolves.
2. **Add-a-chip** — a dashed ＋ chip in the confirm sheet for anything the parse missed; added items get the same async macro estimate.
3. **Auto-finish on silence** — speak, pause ~1.8s, and the entry files itself (transcript-change timestamps from SFSpeech). The "Done" button remains as a manual override; "Type instead" still available.
4. **Day rollover + freshness** — `TodayView` is now a thin wrapper owning `dayStart`; the content (and its day-anchored queries) rebuilds at midnight, and Health data refreshes every time the app returns to the foreground. Previously an overnight-resident app showed yesterday's protein.
5. **Insight staleness** — the daily read's cache key is now a stamp of *day + meals logged + weight + target*, so logging a meal regenerates it (verified live: the read updated to cite "12g of protein logged today"). Any same-day cached read still shows while a new one generates.
6. **Voice-set protein target** — "set my protein target to 160" is a new parser kind with its own confirm card; updates the bar and the coach's context. Works in the offline fallback too.
7. **Feel** — typing mode auto-focuses the keyboard; logging fires a success haptic alongside the toast.

---

# Milestone 2 — the coach + calendar/history

## What's in this build

1. **On-demand coach** (`Coach/CoachSheet.swift`, `Intelligence/CoachSession.swift`) — tapping the insight card opens the coach, which immediately runs the **"How am I doing?" review**, then offers the four suggestion chips and free-form ask, all as a running conversation. Pull, not push: nothing ever notifies.
2. **Grounded + private by construction** (`Intelligence/TrendSummary.swift`) — the coach only ever sees a compact plain-text trend summary (protein by day ×7, today's meals, training days ×14, weight trend, sleep, steps, resting HR, up to 5 short reflection excerpts). The sheet's **"What your coach can see"** disclosure shows that exact text verbatim — the privacy tradeoff made visible, per the spec.
3. **Claude-written daily insight** — generated once per day from the same summary (effort low, ≤35 words, must cite a real number), cached in `@AppStorage`; the rule-based `InsightEngine` remains the offline/keyless fallback.
4. **Calendar / History** (`History/HistorySheet.swift`) — month grid with calm indigo dots (never a red "missed day"), neutral empty days, month navigation capped at the current month. Tap any day → day detail listing synced workouts/weights (read-only) and food/reflections with **edit, delete, and add** — including on empty days, which is how back-dating works.
5. **Edit = re-parse, not a form** — editing an entry reopens the talk/type control prefilled with the original words; confirming replaces the old entry (`CaptureRequest.replacing…`). Fixing a bad parse never means retyping into fields.

## Coach behavior rules (in the system prompt)

Priority-ordered: coach-not-clinician (defers on medical) → cite real figures, never invent → suggestions not prescriptions, never guilt → no calorie obsession → reflections noticed but never interpreted/diagnosed; distress answered with warmth + real resources → scope bounded (no multi-week programming or full meal plans). Replies use `effort: medium`.

## Model choice (updated)

Everything now runs on **`claude-sonnet-5`** — near-Opus quality on this kind of work at a third of the cost ($3/$15 vs $10/$50 per MTok), and snappier for the parse sheet. The original `claude-fable-5` + Opus-fallback setup from milestone 1 was swapped out; the Fable-specific `fallbacks` parameter and beta header went with it. Model is a single constant in `ClaudeClient.swift` if you want to move the coach back up-tier later.

## Milestone 2 choices

| Area | Choice | Why |
|---|---|---|
| Coach conversation | In-memory per sheet session, not persisted | A check-in, not a chat log; keeps stored data minimal. |
| Review on open | Runs automatically | "One tap produces a plain-language read" — the tap is opening the coach. |
| Back-dated entries | Land at noon of the target day | No time picker; trends don't care. |
| Day markers | Food, reflections, workouts, weight readings | Anything logged or synced counts; the dot is deliberately uniform. |
| Insight staleness | Cached for the calendar day | Re-generating on every log would burn tokens for marginal freshness; the protein bar itself is always live. |
| Keyless coach | Sheet still opens, shows what it *would* do + the data disclosure, input disabled | The privacy story should be inspectable before any key is set. |
| Debug flags | `-open-coach`, `-open-history` (DEBUG only), alongside `-skip-health-auth` | Scripted screenshots / UI tests. |

## Verified (milestone 2)

- Clean build; Today, History (grid + dots + month nav), and the keyless coach sheet all screenshot-verified on the simulator.
- Found a real reflection from your own device testing already routed and stored correctly ("Testing 1 to 3") — its dot shows on July 12.
- Needs your manual pass (sandbox can't tap): live coach review + Q&A with your API key, day-detail edit/delete/back-date, and the daily insight after first launch with a key.

---

# Milestone 1 build notes

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

- **Model**: originally `claude-fable-5` with a server-side Opus 4.8 fallback, as the brief specified — **switched to `claude-sonnet-5` for everything in milestone 2** (see "Model choice" above).
- **Structured outputs** (`output_config.format` with a strict JSON schema) so every parse is guaranteed machine-readable — no brittle string extraction. `effort: low` — parsing is routine work; low effort keeps it fast and cheap while staying accurate.
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
