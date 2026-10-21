# Yapso — Product Spec (v1)

One random topic a day. Ten minutes to research it. Ninety seconds to explain it. Honest feedback after.

Yapso trains two things at once: **articulating clearly under time pressure**, and **actually learning something niche** every day.

---

## 1. Core loop

1. **Spin.** Home shows "Today's topic is ready". The user taps Spin; a typographic rolodex scrolls real topic names and settles on today's topic (spring physics, soft haptic ticks, one firm landing haptic). The result is pre-decided; the spin is theatre. The daily spin is never skippable; practice spins are.
2. **Research (10:00).** The clock starts the moment the reel lands. Research happens *outside* the app (Safari, ChatGPT, books, anything) — there is no in-app notes feature.
   - Screen: topic name (large, long-press to copy), domain, countdown, **Search this** (opens a Google search in Safari), **I'm ready — start speaking** (confirmation sheet).
   - Local notifications at 1:00 remaining and at 0:00.
   - User may start early.
3. **Speak (90s, hard cap).** Starts automatically when research ends. If the user is outside the app at that moment, returning shows a 3‑2‑1 countdown and recording starts — it cannot be deferred.
   - Screen: topic small at top, thin countdown ring, subtle live waveform, **Done** button.
   - User may stop early; time used becomes a metric.
   - **Interruptions are bad luck.** A call, crash, or leaving the app ends the attempt; whatever was recorded is analysed. No restarts.
4. **Feedback.** See §3.

### Rules
- One counted ("daily") attempt per local calendar day. Day resets at **local midnight**; an attempt revealed before midnight counts for the day it was revealed.
- If a revealed daily attempt never reaches the speaking phase, it is forfeited (no streak credit) once the calendar day its research window ended in has passed. (A 23:55 reveal can still be spoken just after midnight.)
- Mic permission is requested **before** the topic can be revealed, so nobody burns a day on a permission prompt. Notification permission is requested at the same moment (first spin) so the research nudges work. No speech-recognition permission is needed (Deepgram, and the on-device fallback, run without it).

### Calibration (first run)
- After onboarding, Today shows a **calibration** before the first spin: 60 seconds on an easy, zero-prep personal question, no research, 3‑2‑1 then record. Default: "Walk me through your perfect Saturday, from the moment you wake up." ("Different question" cycles to "Teach me how to make something you're good at making" and "Tell me about a place you love").
- Transcribed by Deepgram (needs a connection, like daily talks), then the Worker returns a **speaking profile**: one of six speaker types (Storyteller, Sprinter, Professor, Minimalist, Improviser, Diplomat; names and blurbs fixed in the app), a two-sentence summary, 1–2 strengths, 1–3 focus areas, and a tip for the first topic. Baselines (pace, fillers per minute, longest pause) come from the on-device metrics.
- **The reveal:** the profile is a letterpress tarot-style card (`ProfileCard`): cream stock, one of six Codex-generated medieval woodcut-style tarot scenes numbered I–VI (Storyteller: minstrel by a fire; Sprinter: running herald; Professor: scholar at a lectern; Minimalist: the Hermit; Improviser: the Fool; Diplomat: Justice), the numeral and name in ember, with paper grain and a sliding glint from a Metal shader (`CardFinish.metal`), tilted in 3D by device motion (CoreMotion, no permission) plus a slow idle drift and drag, with a soft warm bloom. (A holographic foil version was tried first and dropped: too bright to read; pearl and midnight-gold variants were also compared.) It flips in alone on a dark stage; a tap glides it to the top and reveals the coach's note: three short conversational paragraphs ("I noticed…") and a one-line starting point (pace, fillers a minute, longest pause).
- The profile seeds the coach memory (focus areas, strengths, first tip) and is kept across daily memory updates. Shown on Today until "Spin your first topic", in History ("Your first talk"), and on Progress ("You started as…").
- Free for everyone, never the free tier's one AI feedback, never part of the streak or trends. An empty calibration asks for another go.

## 2. Topics

- **Concrete, niche, explainable concepts** — not philosophical/opinion prompts. Examples: "The Lindy Effect", "How submarines control depth", "Tardigrades", "The Byzantine Generals Problem", "Why Venice is sinking".
- Sweet spot: researchable in 10 minutes, explainable in 90 seconds. Not too broad ("Physics"), not unresearchably obscure.
- Each topic: `id`, `title`, `domain` (Science, Technology, History, Economics, Psychology, Nature, Culture, …). Title only — no hint/subtitle.
- **Per-user random**, never repeating for that user (a topic used for practice is also consumed). If the pool is exhausted, repeats are allowed.
- Pool: 514 topics across 17 domains (Science, Space, Technology, Engineering, History, Economics, Business, Psychology, Body, Nature, Geography, Culture, Language, Food, Math, Design, Law), AI-generated in bulk, still to be reviewed by hand, bundled as JSON, updatable from the Worker later.
- Rerolling via reinstall is accepted for v1.

## 3. Feedback

Delivered as native, animated UI from structured data — **never a wall of AI text**. Sequence:

1. **Instant delivery metrics** (computed on-device from the transcript and audio) (cards count up): words per minute, filler-word count, longest pause, time used. Each shows Δ vs the user's 7‑day rolling average once ≥3 daily attempts exist.
2. **Transcript** with fillers and long pauses highlighted (shown while the AI call is in flight).
3. **Content ratings** (1–5 each, one-line reason ≤15 words):
   - **Clarity** — would someone who knows nothing about the topic actually get it? Jargon explained, analogies/examples.
   - **Structure** — opens with the core idea, builds, lands the ending.
   - **Accuracy** — only flags *clearly* wrong claims; quotes them. Never nitpicks.
   - **Ownership** — understanding vs recitation. Own words/examples score high; encyclopedia tone, unexplained jargon, suspiciously even pace with zero fillers score low.
4. **Flagged claims** (if any): quote + one-line correction.
5. **What you missed**: ≤2 bullets — the key ideas a good explanation would include. Doubles as the "learn" moment.
6. **Next time, try…**: exactly one tip.

Rules:
- Any transcript with ≥1 word goes to the AI, even very short ones. The coach reads the emotional content too (e.g. "oh shit, I suck" → honest reassurance).
- An empty transcript skips the AI call and shows a hardcoded kind card. Streak still counts. Does not consume the free AI feedback.
- Coach voice: **warm but direct**. Names problems plainly, never gushes, no emojis, no "Great job!" filler. Pinned via system prompt + 2–3 example outputs.
- Enforced by OpenAI Structured Outputs with hard length limits per field.

## 4. Coach memory

- A small **coach profile** lives on-device (synced via iCloud): top ~3 weaknesses (label + evidence), strengths, recent tips, onboarding answers.
- Seeded by onboarding pain-point answers.
- Each daily analysis request sends: profile + transcript + delivery metrics + recent metric averages. The model returns feedback **and an updated profile**, which replaces the stored one.
- **Only daily attempts write to the profile and to progress/trends.** Practice uses the profile as read-only context.
- Redoing a past topic in practice also sends the previous attempt's summary, so feedback can compare ("Clarity 2 → 4").
- Visible to the user as **Your focus areas** (Progress tab).

## 5. Rehearsals: practice for real life

Random topics train the underlying skill; rehearsals connect it to the moments users told us they struggle with.

- **Today is a home screen:** today's topic on top (an ember Spin card, or once done a summary card that opens the full result), then **"Recommended for you"**: three rehearsals as rows in one card (two from the user's top situation from onboarding, one from the next, preferring untried ones; rotate daily, stable within a day), then "Browse all 70 rehearsals" → a **Rehearsals** page with category chips (Interviews, Speaking up, Presenting, Meetings, Everyday; the user's first) over one vertical list. 70 bundled scenarios in `scenarios.json`.
- **Flow:** tap a scenario and the 30-second prep starts at once (no spin, no research, no "one go" confirmation; **Stop** abandons it), then up to 90 seconds. The prompt stays on screen while speaking.
- **Feedback** is scenario-specific: Clarity, Structure, **Relevance** (did you answer what was asked) and **Presence** (conviction vs hedging), "A strong answer includes" (≤2), one tip, and a comparison with the last attempt at the same scenario. Rehearsals read the coach memory but never update it, and never count toward the streak or Progress.
- **Try again** on the result (and in History) retakes the same scenario, compared with the previous take. Cards show the best score so far.
- **Pro**, with one free rehearsal for free users. Available any time, before or after the daily. Up to 8 a day (Worker per-device limits: 25 transcriptions, 20 feedbacks a day).
- After any talk, its full result shows on Today until **Done**; then Today returns to the home screen.
- Random-topic practice (and redoing past topics) was replaced by rehearsals. Old practice attempts still display.

## 6. Streaks

- Count consecutive local days with a completed daily attempt. Missing a day resets to 0. No freezes in v1.

## 7. Monetization

- **Free:** daily attempt + on-device delivery metrics + transcript + audio. **One** real AI feedback on the first daily attempt. After that the AI section renders a **hardcoded blurred preview** (identical for all free users).
- **Pro:** AI content feedback + coach memory, rehearsals (one free try for free users), Progress tab (trends + focus areas).
- The free attempt's coach profile is kept silently; if the user later subscribes, the coach continues from it.
- Paywalls: (1) dismissible soft paywall at end of onboarding, (2) real pitch after the free AI feedback is used up. Mocked with a fake Subscribe button until RevenueCat is integrated.
- Everything is unlocked during development.

## 8. Onboarding

0. Welcome: the live rolodex reel above the "yapso." wordmark and tagline, ember "Get started".
1. One "How it works" page: three numbered steps (spin, 10 min to research, 90s), "One spin a day. No do-overs."
2. Pain-point questions (single-tap):
   - When does speaking trip you up? Meetings / Interviews / Presentations / Explaining things to friends / I ramble in general
   - What happens? (multi) Blank out / Say "um" a lot / Ramble without a point / Speak too fast / Lose confidence
   - What's the goal? Career / School / Confidence / Just getting sharper
   Single-choice questions advance on tap; each answer has an icon.
3. "Your plan": the reflect-back headline ("In meetings, you blank under pressure and ramble."), what the coach will watch for (from the struggles), and the daily routine.
4. Mic permission with a short rationale.
5. Soft paywall (dismissible) → Home.

No speaking during onboarding. No account. Notification permission is requested at the first spin; the daily reminder (default 18:00, only on days not yet spun; one-off reminders scheduled a week ahead and refreshed on open) reuses it. Turning the reminder on in Settings also asks, if never asked.

## 9. App structure

- **Today** — streak and Settings gear, today's topic card (Spin, or summary → full result), then the rehearsal library. A just-finished talk shows in full until Done.
- **History** — attempts list → full feedback, transcript, audio playback. Practice labelled.
- **Progress** (Pro) — trend charts (daily attempts only) + Your focus areas.
- Settings (gear): reminder time, spin sound toggle, subscription.

## 10. Design

- Tasteful and minimal, Notion-like. Not game-y, not tacky. Good motion and haptics, restrained.
- **Paper and ink** (`Views/Theme.swift`): warm off-white paper (#F6F4EF) / warm near-black (#121110), cards one step up with a hairline edge, ink text, and one accent, **ember** (#D9542A / #F0703F), matching the icon's dot: the streak, the selected tab, the moment's main button (Spin, Get started, Start Pro), the clocks, countdown and waveform, filler highlights, ratings and charts, the coach note and "Next time" card, and onboarding selections. Everything else stays ink.
- **Type:** New York serif (`Font.display`) for topic titles and headlines, including navigation titles; SF for everything else.
- **Illustrations:** four ink line drawings (rolodex, microphone, whistle + stopwatch, seedling) generated with Codex image generation, stored as template images so they draw in the current ink color. App icon: a serif "y." with an ember dot, with a dark variant.
- Follows system light/dark. Speaking screen uses the same theme, restrained.
- Spin sound off by default (toggle in Settings).
- iPhone only, portrait. English only.

## 11. Technical

- SwiftUI, iOS 26+, iPhone only.
- **SwiftData + CloudKit** sync from day one. Model rules: every property optional or defaulted, no unique constraints, all relationships optional.
- **Audio** stored on-device (not synced), re-encoded to ~32 kbps AAC after the talk (~350 KB per 90s), retained 30 days. It is uploaded only to be transcribed and not kept by us. Transcripts, metrics, feedback, profile sync. The privacy label must declare audio sent to a processor.
- **Transcription** by Deepgram Nova-3 (`filler_words=true`, topic title as a keyterm), via the Worker. Release builds never hold the Deepgram key; Debug builds can call Deepgram directly with `DEEPGRAM_DEV_KEY` from the gitignored `Config/Secrets.xcconfig`.
  - **Daily talks: Deepgram only.** Offline, the talk is saved and the results screen says a connection is needed, then analyzes automatically once one appears.
  - **Practice talks: Deepgram, falling back to on-device** `SpeechAnalyzer` / `SpeechTranscriber` when offline or when Deepgram fails. Results then say the offline model was used and offer "Transcribe again online" once connected. The offline model is reserved and downloaded at launch; it does not work in the Simulator.
- **Delivery metrics** computed on-device. Fillers come from the transcript (both transcribers keep "um", "uh"; "like,", "you know" are detected from context). Pauses are measured from audio levels, because transcribers fold silence into word time ranges.
- **Backend:** Cloudflare Worker proxying OpenAI and Deepgram (`POST /transcribe` passes Deepgram's JSON through). Apple App Attest + per-device rate limits. API key only in the Worker. Model and reasoning effort configurable in `worker/wrangler.jsonc`: `gpt-5.6-luna` at low effort: 4–8s, ~$0.001 per talk, caught every planted error in the test set. `gpt-5.6-terra` at low is the upgrade if feedback feels thin (warmer notes, better memory; ~$0.008 per talk). `gpt-5.4-mini` at medium was about as good as Luna but ~8x the cost.
- **Analytics:** TelemetryDeck (events only, never transcripts/audio), added just before launch. No ATT prompt required.
- **Payments:** RevenueCat, later.

## 12. Build order

1. Data models (CloudKit-compatible), day/streak/topic-picking logic, seed topics.
2. Daily flow: rolodex reveal → research timer → 90s recorder.
3. Transcription (Deepgram, on-device fallback for practice) + delivery metrics.
4. Worker + OpenAI analysis + coach profile round-trip.
5. Feedback UI and animations.
6. History, Progress.
7. Onboarding, paywall mocks, notifications.
8. Topic pool (500), TelemetryDeck, RevenueCat.
