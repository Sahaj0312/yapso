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
- Mic permission is requested **before** the topic can be revealed, so nobody burns a day on a permission prompt. Notification permission is requested at the same moment (first spin) so the research nudges work. No speech-recognition permission is needed (SpeechAnalyzer runs on-device without it).

## 2. Topics

- **Concrete, niche, explainable concepts** — not philosophical/opinion prompts. Examples: "The Lindy Effect", "How submarines control depth", "Tardigrades", "The Byzantine Generals Problem", "Why Venice is sinking".
- Sweet spot: researchable in 10 minutes, explainable in 90 seconds. Not too broad ("Physics"), not unresearchably obscure.
- Each topic: `id`, `title`, `domain` (Science, Technology, History, Economics, Psychology, Nature, Culture, …). Title only — no hint/subtitle.
- **Per-user random**, never repeating for that user (a topic used for practice is also consumed). If the pool is exhausted, repeats are allowed.
- Pool: ~500 topics, AI-generated in bulk, reviewed by hand, bundled as JSON, updatable from the Worker later.
- Rerolling via reinstall is accepted for v1.

## 3. Feedback

Delivered as native, animated UI from structured data — **never a wall of AI text**. Sequence:

1. **Instant, on-device delivery metrics** (cards count up): words per minute, filler-word count, longest pause, time used. Each shows Δ vs the user's 7‑day rolling average once ≥3 daily attempts exist.
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

## 5. Practice mode (Pro)

- Unlocks only after today's daily attempt is done.
- Random new topic or redo of a past topic (from History). Same full flow (10:00 research, start early allowed, 90s).
- Full AI feedback, labelled "Practice" in History. Does not affect streak, progress, trends, or coach profile.
- Capped at ~5 analyses/device/day by the Worker.

## 6. Streaks

- Count consecutive local days with a completed daily attempt. Missing a day resets to 0. No freezes in v1.

## 7. Monetization

- **Free:** daily attempt + on-device delivery metrics + transcript + audio. **One** real AI feedback on the first daily attempt. After that the AI section renders a **hardcoded blurred preview** (identical for all free users).
- **Pro:** AI content feedback + coach memory, practice mode, Progress tab (trends + focus areas).
- The free attempt's coach profile is kept silently; if the user later subscribes, the coach continues from it.
- Paywalls: (1) dismissible soft paywall at end of onboarding, (2) real pitch after the free AI feedback is used up. Mocked with a fake Subscribe button until RevenueCat is integrated.
- Everything is unlocked during development.

## 8. Onboarding

1. 2–3 screens explaining the rules (one spin a day, 10 min to research, 90s, no do-overs).
2. Pain-point questions (single-tap):
   - When does speaking trip you up? Meetings / Interviews / Presentations / Explaining things to friends / I ramble in general
   - What happens? (multi) Blank out / Say "um" a lot / Ramble without a point / Speak too fast / Lose confidence
   - What's the goal? Career / School / Confidence / Just getting sharper
3. Reflect-back screen ("You blank under pressure and ramble. Yapso trains exactly that…").
4. Mic permission with a short rationale.
5. Soft paywall (dismissible) → Home.

No speaking during onboarding. No account. Notification permission is requested at the first spin; the daily reminder (default 18:00, only if today's yap isn't done) reuses it.

## 9. App structure

- **Today** — streak, spin / active session / today's result; practice entry after the daily attempt.
- **History** — attempts list → full feedback, transcript, audio playback. Practice labelled.
- **Progress** (Pro) — trend charts (daily attempts only) + Your focus areas.
- Settings (gear): reminder time, spin sound toggle, subscription.

## 10. Design

- Tasteful and minimal, Notion-like. Not game-y, not tacky. Good motion and haptics, restrained.
- Follows system light/dark. Speaking screen uses the same theme, restrained.
- Spin sound off by default (toggle in Settings).
- iPhone only, portrait. English only.

## 11. Technical

- SwiftUI, iOS 26+, iPhone only.
- **SwiftData + CloudKit** sync from day one. Model rules: every property optional or defaulted, no unique constraints, all relationships optional.
- **Audio** stored on-device only (not synced), retained 30 days. Transcripts, metrics, feedback, profile sync.
- **Transcription** on-device via `SpeechAnalyzer` / `SpeechTranscriber`. Audio never leaves the phone.
- **Delivery metrics** computed on-device. Fillers come from the transcript (SpeechTranscriber keeps "um", "uh", "like,", "you know"). Pauses are measured from audio levels, because the transcriber folds silence into the next word's time range. The speech model is reserved and downloaded at launch. On-device transcription does not work in the Simulator; test on a device.
- **Backend:** Cloudflare Worker proxying OpenAI. Apple App Attest + per-device rate limits. API key only in the Worker. Model name configurable in Worker config (mini-tier default; eval against a stronger model on sample transcripts before launch).
- **Analytics:** TelemetryDeck (events only, never transcripts/audio), added just before launch. No ATT prompt required.
- **Payments:** RevenueCat, later.

## 12. Build order

1. Data models (CloudKit-compatible), day/streak/topic-picking logic, seed topics.
2. Daily flow: rolodex reveal → research timer → 90s recorder.
3. On-device transcription + delivery metrics.
4. Worker + OpenAI analysis + coach profile round-trip.
5. Feedback UI and animations.
6. History, Progress.
7. Onboarding, paywall mocks, notifications.
8. Topic pool (500), TelemetryDeck, RevenueCat.
