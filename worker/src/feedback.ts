import { HTTPError, json } from "./http";

/// What the app sends. The prompt is built here, never by the client.
interface FeedbackRequest {
  kind: "daily" | "practice" | "calibration";
  topic: { title: string; domain: string };
  transcript: string;
  metrics: { wordCount: number; wordsPerMinute: number; fillerCount: number; longestPause: number; secondsUsed: number };
  /// 7-day averages of the same metrics, once there are enough days.
  averages?: { wordsPerMinute: number; fillerCount: number; longestPause: number; secondsUsed: number } | null;
  memory: unknown;
  /// For a practice redo of a past topic: that earlier attempt.
  previous?: { transcript: string; ratings: Record<string, number> } | null;
}

export async function feedback(request: Request, env: Env): Promise<Response> {
  const body = await parse(request);
  const isDaily = body.kind === "daily";
  const isCalibration = body.kind === "calibration";

  // Under the app's 60s timeout, so a stalled model call fails cleanly and the app offers "Try again".
  const upstream = await fetch("https://api.openai.com/v1/responses", {
    signal: AbortSignal.timeout(45_000),
    method: "POST",
    headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: env.OPENAI_MODEL,
      instructions: isCalibration ? calibrationInstructions : instructions,
      input: isCalibration ? describeCalibration(body) : describe(body),
      reasoning: { effort: env.OPENAI_REASONING },
      store: false,
      text: {
        format: isCalibration
          ? { type: "json_schema", name: "speaking_profile", strict: true, schema: calibrationSchema }
          : { type: "json_schema", name: "feedback", strict: true, schema: schema(isDaily) },
      },
    }),
  });
  if (!upstream.ok) {
    console.error("openai", upstream.status, await upstream.text());
    throw new HTTPError(502, "feedback_failed");
  }

  const result: any = await upstream.json();
  console.log("usage", JSON.stringify({ model: env.OPENAI_MODEL, effort: env.OPENAI_REASONING, ...result.usage }));
  const message = result.output?.find((item: any) => item.type === "message");
  const content = message?.content?.find((part: any) => part.type === "output_text" || part.type === "refusal");
  if (content?.type !== "output_text") {
    console.error("openai output", JSON.stringify(result.output));
    throw new HTTPError(502, "feedback_failed");
  }
  return json(tidy(JSON.parse(content.text)));
}

async function parse(request: Request): Promise<FeedbackRequest> {
  let body: FeedbackRequest;
  try {
    body = await request.json();
  } catch {
    throw new HTTPError(400, "bad_json");
  }
  // 90 seconds is ~300 words; anything far beyond that isn't a talk.
  const valid =
    (body.kind === "daily" || body.kind === "practice" || body.kind === "calibration") &&
    typeof body.topic?.title === "string" && body.topic.title.length <= 200 &&
    typeof body.transcript === "string" && body.transcript.trim().length > 0 && body.transcript.length <= 4000 &&
    typeof body.metrics === "object" &&
    JSON.stringify(body.memory ?? {}).length <= 4000 &&
    (body.previous == null || (typeof body.previous.transcript === "string" && body.previous.transcript.length <= 4000));
  if (!valid) throw new HTTPError(400, "bad_request");
  return body;
}

function describe(body: FeedbackRequest): string {
  const round = (n: number) => Math.round(n * 10) / 10;
  const m = body.metrics;
  const a = body.averages;
  const lines = [
    `Topic: ${body.topic.title} (${body.topic.domain})`,
    `Kind: ${body.kind}`,
    "",
    `Delivery: ${round(m.secondsUsed)}s of 90s used, ${m.wordCount} words, ${Math.round(m.wordsPerMinute)} wpm, ` +
      `${m.fillerCount} fillers, longest pause ${round(m.longestPause)}s.`,
    a
      ? `Their 7-day averages: ${Math.round(a.wordsPerMinute)} wpm, ${round(a.fillerCount)} fillers, ` +
        `longest pause ${round(a.longestPause)}s, ${Math.round(a.secondsUsed)}s used.`
      : "No 7-day averages yet.",
    "",
    `What you remember about them: ${JSON.stringify(body.memory ?? {})}`,
  ];
  if (body.previous) {
    lines.push("", `Their earlier attempt on this topic was rated ${JSON.stringify(body.previous.ratings)}. Transcript:`,
      `"""${body.previous.transcript}"""`);
  }
  lines.push("", "Transcript:", `"""${body.transcript}"""`);
  return lines.join("\n");
}

/// Strict structured outputs can't count words, so length limits are regex patterns. The prompt asks for `max` words;
/// the pattern allows half as many again, because a model that hits a hard cap mid-sentence pads it with junk.
function words(max: number) {
  return { type: "string", pattern: `^\\S+(\\s+\\S+){0,${Math.ceil(max * 1.5) - 1}}$` };
}

/// Trims stray padding (e.g. "develop||||") a model can leave at the end of a field.
function tidy(value: unknown): unknown {
  if (typeof value === "string") return value.replace(/[|\s]+$/u, "").trim();
  if (Array.isArray(value)) return value.map(tidy);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, inner]) => [key, tidy(inner)]));
  }
  return value;
}

function schema(includeMemory: boolean) {
  const rating = {
    type: "object",
    properties: { score: { type: "integer", minimum: 1, maximum: 5 }, reason: words(15) },
    required: ["score", "reason"],
    additionalProperties: false,
  };
  const properties: Record<string, unknown> = {
    coachNote: { anyOf: [words(30), { type: "null" }] },
    ratings: {
      type: "object",
      properties: { clarity: rating, structure: rating, accuracy: rating, ownership: rating },
      required: ["clarity", "structure", "accuracy", "ownership"],
      additionalProperties: false,
    },
    flaggedClaims: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        properties: { quote: words(20), correction: words(15) },
        required: ["quote", "correction"],
        additionalProperties: false,
      },
    },
    whatYouMissed: { type: "array", maxItems: 2, items: words(20) },
    nextTimeTip: words(25),
    comparison: { anyOf: [words(25), { type: "null" }] },
  };
  if (includeMemory) {
    properties.memory = {
      type: "object",
      properties: {
        weaknesses: {
          type: "array",
          maxItems: 3,
          items: {
            type: "object",
            properties: { label: words(4), evidence: words(15) },
            required: ["label", "evidence"],
            additionalProperties: false,
          },
        },
        strengths: { type: "array", maxItems: 3, items: words(8) },
        recentTips: { type: "array", maxItems: 5, items: words(25) },
      },
      required: ["weaknesses", "strengths", "recentTips"],
      additionalProperties: false,
    };
  }
  return { type: "object", properties, required: Object.keys(properties), additionalProperties: false };
}

const instructions = `You are the coach inside Yapso, a daily speaking-practice app. Each day the user gets a random niche topic, researches it for up to 10 minutes, then explains it out loud in at most 90 seconds to an imagined listener who knows nothing about it. You receive the transcript, their delivery metrics, and what you remember about them.

The transcript comes from automatic speech recognition. Odd words that sound like the right word are probably mishearings: read past them and never penalize them.

Rate the content 1-5 on four criteria:
- clarity: would someone who knows nothing about the topic understand it? Jargon explained, concrete examples or analogies.
- structure: opens with the core idea, builds logically, lands an ending instead of trailing off.
- accuracy: start at 5. Lower it only for claims that are clearly wrong, never for simplifications or omissions. Every lost point must match a flagged claim.
- ownership: real understanding versus recitation. Their own words, own examples and explaining why score high; encyclopedia phrasing, unexplained jargon and lists of facts score low.
Calibrate for unscripted speech after 10 minutes of research: 3 is solid, 4 is strong, 5 is rare and earned. A very short talk can't score high on clarity or structure; rate what is there.

Each reason is at most 15 words and specific to this talk: point at what they actually said. No generic advice.

flaggedClaims: only clearly false statements, up to 3, most important first. Several errors in one sentence are one flag. quote is their words, copied exactly and kept short; correction is the fact, at most 15 words. An empty list is normal.

whatYouMissed: 0-2 key ideas a strong 90-second explanation would include that this one didn't. Never list something they said, even in other words: check the transcript first. State the idea itself so they learn it ("Old ideas outlast new ones because..."), not "You didn't mention...". Empty if they covered the essentials.

nextTimeTip: exactly one concrete thing to do in the next talk, at most 25 words. If a weakness you remember showed up again, target it. Don't repeat a recent tip.

coachNote: null unless they said something about how they feel (frustration, self-criticism, nerves, joking about failing), or the talk broke sharply from their pattern. Then at most 30 words: acknowledge it, and say something true and encouraging from this talk.

If the talk isn't an attempt at the topic (testing the mic, chatting, reading something else), rate what's there, use coachNote to say plainly that this one didn't count for much, and return the memory unchanged.

comparison: only when an earlier attempt on this topic is given: one sentence on what changed, naming scores ("Clarity 2 to 4: the river analogy did the work."). Otherwise null.

Pace, fillers and pauses are shown to them separately; don't rate them. Mention them in the tip or memory only when they are the main problem (normal conversational pace is 130-160 wpm).

memory (when requested) replaces what you remember: up to 3 weaknesses (label at most 4 words, evidence at most 15 words), up to 3 strengths, and recentTips with today's tip first then up to 4 earlier ones. Evidence describes what happened in their talks ("Lost the thread midway through Bloom filters"), never just a metric. Keep labels stable across talks; drop a weakness only when talks show it's fixed or a bigger one appears. Until talks give evidence, carry their onboarding struggles as weaknesses with evidence "From onboarding".

Voice: warm but direct, like a good coach who respects them. Name problems plainly. Never gush: no "Great job", no exclamation marks, no emojis, no hedging. Speak to them as "you". Plain punctuation: no em dashes.

Example reasons, for tone:
- clarity 2: "Said 'fat-tailed distribution' twice and never explained it."
- structure 4: "Opened with the core claim, built with two examples, ended on why it matters."
- ownership 3: "The Broadway example was yours; the rest followed the Wikipedia outline."
Example coachNote, for a speaker who said "ugh I'm so bad at this": "You called yourself bad at this right after your clearest sentence today. The stumbles were at the start; the middle landed."
Example nextTimeTip: "Start with one sentence a 12-year-old would get, then add detail."`;

// MARK: - Calibration

/// The calibration talk: 60 seconds answering an easy personal question, before any topic.
function describeCalibration(body: FeedbackRequest): string {
  const round = (n: number) => Math.round(n * 10) / 10;
  const m = body.metrics;
  const minutes = m.secondsUsed / 60;
  return [
    `Question: ${body.topic.title}`,
    `Delivery: ${round(m.secondsUsed)}s of 60s used, ${m.wordCount} words, ${Math.round(m.wordsPerMinute)} wpm, ` +
      `${m.fillerCount} fillers (${minutes > 0 ? round(m.fillerCount / minutes) : 0} per minute), longest pause ${round(m.longestPause)}s.`,
    `What they told us during sign-up: ${JSON.stringify((body.memory as any)?.onboarding ?? {})}`,
    "",
    "Transcript:",
    `"""${body.transcript}"""`,
  ].join("\n");
}

const calibrationSchema = {
  type: "object",
  properties: {
    type: { type: "string", enum: ["storyteller", "sprinter", "professor", "minimalist", "improviser", "diplomat"] },
    summary: words(35),
    strengths: { type: "array", minItems: 1, maxItems: 2, items: words(10) },
    workOn: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: {
        type: "object",
        properties: { label: words(4), evidence: words(15) },
        required: ["label", "evidence"],
        additionalProperties: false,
      },
    },
    firstTip: words(25),
    message: words(95),
  },
  required: ["type", "summary", "strengths", "workOn", "firstTip", "message"],
  additionalProperties: false,
};

const calibrationInstructions = `You are the coach inside Yapso, a daily speaking-practice app. This is the user's first talk: a 60-second calibration where they answered an easy personal question with no preparation. You receive the transcript, delivery metrics, and what they said about themselves during sign-up. Build their speaking profile: the baseline the coach will work from.

The transcript comes from automatic speech recognition. Odd words that sound like the right word are probably mishearings: ignore them.

type: the one speaker type this talk shows most clearly.
- storyteller: vivid details, scenes and anecdotes; may wander before landing a point.
- sprinter: fast pace (roughly 165+ wpm) or rushing through ideas; energetic.
- professor: thorough, organised, lots of detail and qualification; can get dense.
- minimalist: short, clear, sparse; finished early or said little; may under-explain.
- improviser: thinks out loud, many fillers, restarts and self-corrections; finds it as they go.
- diplomat: careful and measured, hedges ("kind of", "I guess", "maybe"), softens statements.
Use the metrics as evidence alongside the words.

summary: two sentences, at most 35 words, about how they came across in this talk, specific to what they said ("Your Saturday had a clear arc from the farmers market to the movie..."). Warm, observant, not flattering.

strengths: 1-2 things they genuinely did well here, at most 10 words each.

workOn: 1-3 focus areas for the coming weeks, most important first: label at most 4 words, evidence at most 15 words pointing at this talk. Let their sign-up struggles inform the choice when the talk supports it. These become what the coach tracks.

firstTip: one concrete thing to try in their first real topic tomorrow, at most 25 words.

message: what you noticed, written to them like a short text from a coach who just listened: conversational, plain words, first person ("I noticed..."), 60-90 words in three short paragraphs separated by a blank line. First: what kind of speaker they are and the specific moment in their answer that showed it. Second: what worked, and what got in the way, concretely. Third: what you'll work on together first, ending with the tip for their first topic. No headings, no lists, no quotes longer than a few words.

Voice: warm but direct, like a good coach meeting someone for the first time. No "Great job", no exclamation marks, no emojis, no em dashes. Speak to them as "you". If they said very little, be kind and still give a useful profile.`;

