# StrongMe — roadmap

*The living plan. `Ref/health-app-spec-v1.md` is the product spec (untouched);
`BUILD_NOTES.md` records what shipped and why. This file tracks where we are.
Build order follows the spec's de-risk sequence.*

## ✅ Milestone 1 — foundation *(shipped 2026-07-12, commit `481cfad`)*
- [x] HealthKit auto-import: steps, sleep, workouts, weight + trend, resting HR
- [x] Spoken weight writes back to Health
- [x] Today screen to the prototype (fonts, palette, insight card, grid, protein bar, usuals, reflection prompt, talk dock, toasts)
- [x] Voice/text → Claude parse → editable chips → log (food, weight, reflection routing)
- [x] Corrections memory ("coffee" → "large oat-milk latte")
- [x] Distress care card with real crisis resources
- [x] On-device fallback parser when keyless/offline

## ✅ Milestone 2 — coach + history *(shipped 2026-07-13, commit `0940dfc`, PR #1)*
- [x] On-demand coach: auto "how am I doing?" review, suggestion chips, free-form ask
- [x] TrendSummary + "What your coach can see" verbatim disclosure (the privacy guarantee)
- [x] Claude-written daily insight, cached per day, rule-based fallback
- [x] Calendar/History: calm dots, day detail, edit / delete / back-date
- [x] Edit = reopen talk control prefilled, replace on confirm
- [x] Model switch: everything on `claude-sonnet-5`

## ✅ Milestone 2.5 — experience polish *(shipped 2026-07-14)*
- [x] Chip rename/add re-estimates macros for *this* log (not just future parses)
- [x] Add-a-chip for items the parse missed
- [x] Auto-finish listening on a longer pause — speak and lower the phone
- [x] Day rollover: queries + protein bar reset at midnight; Health refresh on foregrounding
- [x] Daily insight regenerates after new logs (stamp-based cache) instead of going stale
- [x] Voice-settable protein target ("set my protein target to 160")
- [x] Auto-focused keyboard in typing mode; success haptic on log

## ✅ Post-2.5 dead-end pass *(2026-07-15, dogfood feedback)*
- [x] History opens on today — day detail inline below the grid, not a nested sheet
- [x] Reflections on Today tappable to edit; protein card opens today's entries
- [x] Stat cards open a 2-week metric history (bars/rows) with ask-coach one tap deeper

## ✅ Post-2.5 forgiveness batch *(2026-07-15)*
- [x] Undo in the toast for every log and delete
- [x] Coach review cached against a data-stamp (instant, free reopens)
- [x] Meal label editable on the confirm sheet
- [x] App-written weigh-ins deletable from History (Health-owned ones stay read-only)
- [x] Health-permission hint in empty states

## ✅ Post-2.5 button-up batch *(2026-07-15)*
- [x] Indigo accent color, oat launch screen (no white flash)
- [x] Dynamic Type via relativeTo anchors; VoiceOver labels on icon buttons
- [x] Long-press to remove a usual; correction memory dedup

## ✅ Post-2.5 protein sheet *(2026-07-15)*
- [x] Protein bar opens a focused today's-meals view (edit/delete, 7-day bars, coach)

## ✅ Post-2.5 smart memory slice *(2026-07-16)*
- [x] Usuals learn meal labels; time-aware chip ordering
- [x] "Log my usual breakfast" pre-fills from memory (local, zero API)
- [x] "Call me Steve" greeting personalization
- [x] Auto-finish haptic; insight crossfade

## ⏳ Milestone 3 — logging without opening the app
- [x] App Intents foundation — LogEntryIntent (parse anything, optimistic + snippet), LogUsualIntent (hands-free meal enum), TalkIntent (open listening); distress opens the app, never a banner *(2026-07-18)*
- [x] Action Button support — point it at "Talk to StrongMe" or "Log" in Settings
- [ ] Lock Screen / Control Center widget (one-tap talk) — needs widget extension target
- [ ] Home Screen widget (protein bar + today at a glance) — nice-to-have
- [ ] Apple Watch complication + minimal watch capture — *likely its own slice; largest lift*

## ⏳ Milestone 4 — trends
- [ ] Swipeable weekly/monthly views: direction, not raw tables
- [ ] Forgiving streaks ("trained 3× this week", graceful recovery — never loss-aversion)
- [ ] Protein, training frequency, weight trend, sleep as the four lenses

## 🔬 In trial
- [ ] UI style trial: "Soft cards" vs "Journal" (treatment) vs "Daybook" (layout + clay palette) — live with them, land one, remove the picker

## Backlog (unscheduled)
- [ ] Dark-mode palette pass (currently forced light)
- [ ] The single gentle daily prompt (max one, well-timed, easily off)
- [ ] Persist coach conversations? (currently per-session by design — revisit)
- [ ] Keychain-based API key entry (paste once, no file) — before any TestFlight
- [ ] Reflection signals surfaced in Trends ("felt flat ×2 this week")

## Explicitly out (per spec)
No social/accounts · no CGM · no precise calorie DB · no multi-week programming
or meal plans · no Android/web
