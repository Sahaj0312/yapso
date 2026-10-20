import { HTTPError, json } from "./http";

/// 90 seconds of 32 kbps AAC is ~350 KB; uncompressed PCM would be ~4 MB.
const maxBytes = 8 * 1024 * 1024;

/// Raw audio in, Deepgram's `results` out, in Deepgram's own shape so the app parses one format whichever way it calls Deepgram.
export async function transcribe(request: Request, url: URL, env: Env): Promise<Response> {
  const length = Number(request.headers.get("Content-Length") ?? 0);
  if (!request.body || length <= 0) throw new HTTPError(400, "empty_audio");
  if (length > maxBytes) throw new HTTPError(413, "audio_too_large");

  const query = new URLSearchParams({
    model: env.DEEPGRAM_MODEL,
    language: "en",
    filler_words: "true",
    punctuate: "true",
  });
  // The topic title, so niche vocabulary is recognized. Bounded so it can't be used to bloat requests.
  for (const term of url.searchParams.getAll("keyterm").slice(0, 3)) {
    if (term.length <= 100) query.append("keyterm", term);
  }

  const upstream = await fetch(`https://api.deepgram.com/v1/listen?${query}`, {
    method: "POST",
    headers: {
      Authorization: `Token ${env.DEEPGRAM_API_KEY}`,
      "Content-Type": request.headers.get("Content-Type") ?? "audio/mp4",
    },
    body: request.body,
  });
  if (!upstream.ok) {
    console.error("deepgram", upstream.status, await upstream.text());
    throw new HTTPError(502, "transcription_failed");
  }
  const result: any = await upstream.json();
  // Only what the app reads; Deepgram's metadata includes request ids and model details.
  return json({ results: result.results });
}
