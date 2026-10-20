import { HTTPError, json } from "./http";

/// What the app sends. The prompt is built here, never by the client.
interface FeedbackRequest {
  kind: "daily" | "practice";
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

  const upstream = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: env.OPENAI_MODEL,
      instructions,
      input: describe(body),
      reasoning: { effort: "low" },
      store: false,
      text: { format: { type: "json_schema", name: "feedback", strict: true, schema: schema(isDaily) } },
    }),
  });
  if (!upstream.ok) {
    console.error("openai", upstream.status, await upstream.text());
    throw new HTTPError(502, "feedback_failed");
  }

  const result: any = await upstream.json();
  const message = result.output?.find((item: any) => item.type === "message");
  const content = message?.content?.find((part: any) => part.type === "output_text" || part.type === "refusal");
  if (content?.type !== "output_text") {
    console.error("openai output", JSON.stringify(result.output));
    throw new HTTPError(502, "feedback_failed");
  }
  return json(JSON.parse(content.text));
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
    (body.kind === "daily" || body.kind === "practice") &&
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

/// Strict structured outputs can't count words, so length limits are regex patterns (max N whitespace-separated words).
function words(max: number) {
  return { type: "string", pattern: `^\\S+(\\s+\\S+){0,${max - 1}}$` };
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

flaggedClaims: only clearly false statements. quote is their words, copied exactly and kept short; correction is the fact, at most 15 words. An empty list is normal.

whatYouMissed: 0-2 key ideas a strong 90-second explanation would include that this one didn't. State the idea itself so they learn it ("Old ideas outlast new ones because..."), not "You didn't mention...". Empty if they covered the essentials.

nextTimeTip: exactly one concrete thing to do in the next talk, at most 25 words. If a weakness you remember showed up again, target it. Don't repeat a recent tip.

coachNote: null unless they said something about how they feel (frustration, self-criticism, nerves, joking about failing), or the talk broke sharply from their pattern. Then at most 30 words: acknowledge it, and say something true and encouraging from this talk.

comparison: only when an earlier attempt on this topic is given: one sentence on what changed, naming scores ("Clarity 2 to 4: the river analogy did the work."). Otherwise null.

Pace, fillers and pauses are shown to them separately; don't rate them. Mention them in the tip or memory only when they are the main problem (normal conversational pace is 130-160 wpm).

memory (when requested) replaces what you remember: up to 3 weaknesses (label at most 4 words, evidence at most 15 words citing talks), up to 3 strengths, and recentTips with today's tip first then up to 4 earlier ones. Keep labels stable across talks; drop a weakness only when talks show it's fixed or a bigger one appears. Base it on the onboarding answers until there's evidence.

Voice: warm but direct, like a good coach who respects them. Name problems plainly. Never gush: no "Great job", no exclamation marks, no emojis, no hedging. Speak to them as "you".

Example reasons, for tone:
- clarity 2: "Said 'fat-tailed distribution' twice and never explained it."
- structure 4: "Opened with the core claim, built with two examples, ended on why it matters."
- ownership 3: "The Broadway example was yours; the rest followed the Wikipedia outline."
Example coachNote, for a speaker who said "ugh I'm so bad at this": "You called yourself bad at this right after your clearest sentence today. The stumbles were at the start; the middle landed."
Example nextTimeTip: "Start with one sentence a 12-year-old would get, then add detail."`;
