export type Route = "transcribe" | "feedback";

export class LimitError extends Error {}

/// Counts a request against the device's and everyone's daily allowance (UTC days), throwing once either is used up.
/// KV is eventually consistent, so a burst can slip a few over; the caps are a cost backstop, not exact quotas.
export async function checkLimits(env: Env, route: Route, device: string): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const deviceLimit = Number(route === "transcribe" ? env.DEVICE_DAILY_TRANSCRIBE : env.DEVICE_DAILY_FEEDBACK);
  const globalLimit = Number(route === "transcribe" ? env.GLOBAL_DAILY_TRANSCRIBE : env.GLOBAL_DAILY_FEEDBACK);

  const deviceKey = `${day}:${route}:${device}`;
  const globalKey = `${day}:${route}:all`;
  const [deviceCount, globalCount] = await Promise.all([count(env, deviceKey), count(env, globalKey)]);
  if (deviceCount >= deviceLimit || globalCount >= globalLimit) throw new LimitError();

  const ttl = { expirationTtl: 2 * 24 * 60 * 60 };
  await Promise.all([
    env.LIMITS.put(deviceKey, String(deviceCount + 1), ttl),
    env.LIMITS.put(globalKey, String(globalCount + 1), ttl),
  ]);
}

async function count(env: Env, key: string): Promise<number> {
  return Number((await env.LIMITS.get(key)) ?? 0);
}
