# StrongMe — build notes

*What shipped in each slice, the choices made where the spec was silent, and what's deliberately stubbed.*

---

# Tests — the intelligence layer, pinned

New `StrongMeTests` unit-test target (hosted in the app, Swift Testing, runs with `xcodebuild test -scheme StrongMe`). 19 tests pin the behaviors past code reviews caught regressions in, rather than chasing UI:

- **Usual recall regex** — explicit forms match; "I had lunch" (the review bug) stays a statement.
- **topUsual** — seeds are never recalled; most-established wins per meal.
- **UsualLearner** — meal labels stick once set; unknown upgrades; seeds graduate; empty items learn nothing.
- **Offline fallback parser** — distress overrides everything (including food-ish sentences); "call me steve" vs "i'm exhausted"; weight needs context ("ate 2 eggs" is food, not a bodyweight); unclassifiable input is kept, never dropped.
- **Coach cache stamp** — steps/timestamp changes don't re-bill a review; real data changes do (`reviewStamp` made internal for this).
- **App↔widget snapshot contract** — a frozen JSON fixture must decode, so renaming a `WidgetSnapshot` field on either side fails a test instead of silently blanking the widget.

Gotcha worth remembering: a SwiftData `ModelContext` does not keep its `ModelContainer` alive — test helpers must return the container, or the first use traps inside SwiftData and takes the whole parallel run with it.

---

# Milestone 3, slice 2 — widgets (Lock Screen, Home Screen, Control Center)

New `StrongMeWidgets` extension target, embedded in the app:

- **Lock Screen mic** (circular): one tap → app opens straight into voice capture via `strongme://talk`.
- **Protein at a glance**: Home Screen small (grams, target, gradient bar in the current UI style's palette) + Lock Screen circular gauge and rectangular bar. Tapping any of them deep-links to the protein sheet (`strongme://protein`).
- **Control Center**: "Talk to StrongMe" control (add it in Control Center's edit mode; also assignable to the Action Button as a control).

**Architecture** — the widget never opens the SwiftData store. The app publishes a tiny JSON snapshot (`WidgetSnapshot`: day, protein, target, style) to App Group defaults (`group.com.be01.StrongMe`) and pokes `WidgetCenter` — on every food save (`EntryLogger.saveFood`, so Siri logging updates widgets too), on protein-target change via Siri, and once on backgrounding, which sweeps up deletes/edits/undo/style changes without instrumenting every closure. A snapshot from yesterday renders as **0g** — the truthful read of a new day — and the timeline carries a midnight entry so the reset happens without the app.

Deep links route through `onOpenURL` → the same in-process `PendingIntentActions` channel the App Intents use (no persisted flags, nothing stale).

Alongside: `AppSettings` now holds every persisted-defaults key (the code-review's "scattered raw strings" cleanup) plus the App Group constants the two processes must agree on.

**Device note**: automatic signing needs the App Group capability on both bundle IDs — first build on device, let Xcode register `group.com.be01.StrongMe` (it will offer to). Verified on simulator: appex embeds + validates, snapshot lands in the group container, `strongme://talk` reaches the app.

---

# UI style A/B/C — third take: "Daybook"

Where Journal changed only the treatment, Daybook changes **layout and palette**, each with a stated reason:

- **Stats become one quiet strip** (StatStrip): the spec says "one insight, not a dashboard," yet the 2×2 grid gave ambient Tier-0 data the prime real estate. Demoted to a single ruled line of four figures; the read and protein become the heroes.
- **Today is a visible thread**: the protein-sheet feedback ("show me what I ate") generalized — the home screen now shows the day's log chronologically (meals, reflections, trained-today), each row tappable to edit, with the reflection prompt at the thread's natural end.
- **One confident suggestion** instead of the six-chip carousel: meal-aware smart memory has earned commitment — "Usual breakfast — Eggs + toast · +22g, tap to log" (long-press to remove).
- **Clay palette** (PaletteSet.earthen): indigo-on-oat is a mind/evening register; this app is equally body/food/warmth. Linen paper, espresso ink, pine for the voice and controls, terracotta as the protein signal. Distinct in a market of blue/green/purple health apps.

**Implementation**: Palette became computed over a `PaletteSet` (classic | earthen) resolved from the current style — all existing `Palette.x` call sites unchanged, so sheets/coach/capture inherit the clay palette automatically under Daybook. Care card colors deliberately constant across palettes. All three styles verified by screenshot; classic is regression-clean.

---

# UI style A/B — "Soft cards" vs "Journal"

An alternate visual style, switchable live from the Aa button in the header (temporary chrome — one style wins and the picker goes away). Same layout, same interactions; only the visual language changes (`UIStyle` in Theme.swift, persisted in `uiStyle`).

**Journal**: the editorial answer to "cards in a grid is every health app." No containers — the daily read is an open serif paragraph over a hairline rule; the stat grid becomes a ruled ledger with oversized Fraunces numerals; protein is a serif figure over a 3pt apricot thread; chips and rows keep ghost outlines (hairline, no fill weight, no shadow) purely for tap affordance. Leans into the one thing that's distinctly ours — the serif voice — and turns data into typography.

**Implementation**: `cardBackground` branches per style (ghost in journal), so every sheet inherits automatically; StatCard/ProteinCard/insight/reflection-prompt have explicit journal variants since they're the centerpiece. Switching animates via @AppStorage — no restart.

Verified both styles on simulator (sim gotcha for scripted testing: cfprefsd caches the prefs domain, so behind-its-back plutil writes need a `launchctl stop com.apple.cfprefsd.xpc.daemon` to stick).

---

# Milestone 3, slice 1a — code-review fixes

A high-effort review of the slice (8 finder angles → 39 candidates → 10 verified findings) surfaced one theme: the Siri path had skipped guards the in-app path earned. All ten fixed:

1. **Typed in-memory pending actions** (`PendingIntentActions`, replacing the UserDefaults flags): fixes the Action-Button race (flag written after consumption already ran — certain failure when the app was frontmost), the stale distress flag firing on unrelated launches (declined Siri prompts now correctly evaporate), and two-sheet contention (one optional action = at most one presentation).
2. **Usual recall can't hijack statements**: the regex now requires an explicit "log" or "usual" — "I had lunch" goes to the parser, as it should. And `topUsual` **excludes seeds**: recall never files food you've never actually eaten (seeds remain tappable chips).
3. **Siri weight parity**: unspecified units resolve via the user's Health preference (was: pounds for everyone), and zero-value weights are rejected instead of written.
4. **Explicit `context.save()`** after every intent mutation — background launches may never run autosave, and Siri must not confirm a log that then evaporates.
5. **Empty-parse guard** on the Siri food path (in-app already had it), plus `UsualLearner` refuses to learn a nameless usual from empty items.
6. **Usual meal labels stick**: one off-schedule dinner no longer flips a 20-time breakfast's label and breaks "log my usual breakfast".
7. **ProteinSheet rebuilt on one live 7-day @Query** keyed to Today's `dayStart`: the bars can no longer go stale against the meal list, today's rows aren't fetched twice, and the sheet agrees with the screen behind it across midnight.

Review also logged cleanup debt (duplicated sheet chrome/day-labels/bar-rows, the intent-vs-app routing switch, scattered settings keys) — deferred, tracked in the review report.

---

# Milestone 3, slice 1 — App Intents foundation

"The best logging never opens the app." Siri, Shortcuts, and the Action Button now funnel into the same parser and stores as the talk control (`Intents/AppIntents.swift`):

- **`LogEntryIntent`** — "Hey Siri, log food in StrongMe" → Siri asks "What would you like to log?" → the sentence runs through the usual-recall shortcut, then the Claude parser (Haiku), and files food / weight / reflection / target / name. **Optimistic logging**: Siri's reply says exactly what was understood ("Logged: 2 eggs, toast — about 25 grams of protein"), with a chip snippet under the dialog; History/Undo in-app are the correction loop.
- **`LogUsualIntent`** — "Log my usual breakfast in StrongMe", fully hands-free: the meal is an enum in the Siri phrase itself, no follow-up question, zero API calls.
- **`TalkIntent`** — "Talk to StrongMe" / the Action Button: opens the app straight into the listening sheet (verified via the pending-flag path).
- **The distress guardrail survives the shortcut path**: a concerning entry via Siri is never logged and never gets a banner — the app opens to the full care response (`CareCard`, now shared between the capture flow and a standalone sheet).
- Plumbing: `AppStores` (one ModelContainer shared by UI and intents), `EntryLogger` (save/recall logic extracted from the capture sheet — one code path for tap, talk, and Siri).

Action Button setup: Settings → Action Button → Shortcut → "Talk to StrongMe" (or "Log" for the Siri-dialog flow). Widget (Lock Screen / Control Center) is the next slice — it needs a widget extension target.

---

# Post-2.5 — smart memory slice

The spec's compounding promise — "the app gets easier the longer you use it" — made concrete:

1. **Usuals learn their meal.** `UsualMeal.mealLabel` (with a one-time backfill for pre-existing seeds); each confirmed log updates it, recency wins.
2. **Time-aware chips.** The "your usual" row floats the current meal's usuals to the front — breakfasts in the morning, dinners at night; frequency breaks ties.
3. **"Log my usual breakfast."** Recognized locally (no API call) when the utterance is just the command; pre-fills your top usual for that meal in the confirm sheet ("Your usual — tweak anything before logging"). No usual saved yet → a gentle notice. "log breakfast: eggs and toast" still parses normally.
4. **"Call me Steve."** New parser kind (`name`, explicit forms only — "i'm exhausted" stays a reflection); confirm card notes the name never leaves the device; greeting becomes "Good evening, Steve."
5. **Feel:** a light haptic when the silence detector files your entry (feedback without looking), and the daily read crossfades when it regenerates instead of snapping.

---

# Post-2.5 — protein sheet

Tapping the protein bar now answers "what have I eaten today?" directly (`ProteinSheet.swift`): today's meals with per-meal protein and time, edit/delete in place (same replace-on-confirm loop), a "+ Log a meal" shortcut, 7-day protein bars with a target tick, and the coach one tap deeper ("Am I on track with protein?"). Previously it opened History-on-today, which buried the answer under the month grid. Debug arg: `-open-protein`.

---

# Post-2.5 — button-up batch

1. **AccentColor → indigo** — alerts, menus, and selection chrome no longer flash iOS blue.
2. **Launch screen → oat** — kills the white blink at cold start (`LaunchBackground` color asset + `UILaunchScreen` dict).
3. **Dynamic Type works** — every `AppFont` size is anchored to the nearest system text style via `relativeTo:`; verified at XXXL (layout holds, minor label wrapping at extreme sizes only).
4. **VoiceOver labels** on all icon-only buttons (chip ×, edit/delete, keyboard toggle, month chevrons, coach send).
5. **Long-press a usual chip → "Remove from usuals"** — one-off meals can't squat in the row.
6. **Correction dedup** — repeat fixes refresh the existing correction's date instead of stacking duplicates in the 10-slot prompt window.

---

# Post-2.5 — forgiveness batch

1. **Undo in the toast.** Every log and delete now carries a 4.5-second Undo: one-tap usuals, food/weight/target confirms, and History deletions (food, reflections, and app-written weigh-ins re-insert on undo). Forgiveness is the design brief; this is its cheapest expression.
2. **Coach review cache.** Reopening the coach reuses the last review while the underlying data hasn't changed (SHA-256 over the trend summary minus its volatile lines — timestamp, live step count — plus the day). Verified: a relaunch renders the review instantly with zero API calls. New data → fresh review, as before.
3. **Editable meal label.** The "Breakfast · logged to food" line on the confirm sheet is a menu — tap to recategorize before logging.
4. **Deletable spoken weigh-ins.** Weight rows in History show a trash button *only* for samples this app wrote (source check against the bundle ID) — a misheard "812" no longer requires a trip to the Health app. Scale/watch samples stay read-only. Sub-line distinguishes "you said it" vs "synced".
5. **Permission hint.** The metric-sheet empty state now says where to fix Health access if data never fills in.

---

# Post-2.5 — dead-end pass (dogfood feedback)

Three fixes from first real use: things you could see but not touch.

1. **History opens on today.** The day detail moved from a nested sheet to an inline section below the month grid, pre-selected to today — open the calendar and today's entries (or its honest empty state) are already there. Tapping another day swaps the list; selected day gets an indigo outline.
2. **Everything logged is now reachable for editing.** Recent reflections on Today are tappable (reopens the talk control prefilled, replaces on confirm — same as History rows, now with a pencil affordance), and the protein card opens History-on-today where meals are edited/deleted. Synced Health rows (workouts, watch/scale weights) stay read-only — Health owns them.
3. **Stat cards are doors, not dead pixels.** Tapping Steps / Sleep / Training / Weight opens that metric's **last two weeks** — calm bars for steps and sleep, a workout list for training, readings with deltas for weight (`MetricSheet.swift`). Direction over decimal points, never a raw table. "Ask your coach →" sits at the bottom and opens the coach with a tailored question auto-asked — history first, intelligence one tap deeper. Debug arg: `-open-metric-steps|sleep|training|weight`.

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

Two tiers, two constants in `ClaudeClient.swift`:

- **`claude-haiku-4-5`** (`parseModel`) — entry parsing and chip macro estimates. Routine structured extraction; $1/$5 per MTok and the fastest tier, which is exactly what the parse sheet wants. Haiku doesn't take the `effort` parameter, so the parse path sends only the JSON-schema `output_config`. Because routing (including distress) now lives on a small model, the conservative on-device distress screen runs as a **backstop over every Claude parse** — if it sees clear signals, the care response wins regardless of the model's routing.
- **`claude-sonnet-5`** (`model`) — the coach and the daily insight, the product's voice.

History: milestone 1 shipped on `claude-fable-5` + Opus fallback (Fable-specific `fallbacks` param and beta header since removed) → all-Sonnet in milestone 2 → this split.

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
