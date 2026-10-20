import { feedback } from "./feedback";
import { HTTPError, json } from "./http";
import { checkLimits, LimitError, type Route } from "./limits";
import { transcribe } from "./transcribe";

/// The app's only backend: proxies Deepgram and OpenAI so their keys never ship in the app. It never accepts
/// arbitrary prompts or model parameters, so it can't be used as a general-purpose proxy.
///
/// TODO before launch: App Attest. Until then the device id is self-reported, and the global daily caps
/// in wrangler.jsonc bound the worst case.
export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    const route = routes[url.pathname];
    if (!route) return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    const device = request.headers.get("X-Yapso-Device") ?? "";
    if (!/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i.test(device)) {
      return json({ error: "missing_device" }, 400);
    }

    try {
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      if (!(await env.IP_LIMITER.limit({ key: ip })).success) throw new LimitError();
      await checkLimits(env, route, device.toUpperCase());
      return route === "transcribe" ? await transcribe(request, url, env) : await feedback(request, env);
    } catch (error) {
      if (error instanceof LimitError) return json({ error: "rate_limited" }, 429);
      if (error instanceof HTTPError) return json({ error: error.code }, error.status);
      if (error instanceof DOMException && error.name === "TimeoutError") return json({ error: "upstream_timeout" }, 504);
      console.error(route, error);
      return json({ error: "internal" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

const routes: Record<string, Route | undefined> = {
  "/transcribe": "transcribe",
  "/feedback": "feedback",
};
