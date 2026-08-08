// Live App Store facts, read at build time from Apple's public lookup API.
//
// The rating is fetched rather than typed into the source because a hard-coded
// number is true on the day it is written and false a week later — and a stale
// `aggregateRating` in structured data is worse than none at all: Google treats
// markup that contradicts the page (or reality) as spam, not as a typo.
//
// Every failure path returns null, and every consumer omits the rating when it
// gets null. A build with no network loses a line of social proof; it can never
// gain a false one.

const LOOKUP = 'https://itunes.apple.com/lookup';

export interface AppRating {
  /** Mean score, rounded to one decimal — 4.81818 → 4.8. */
  value: number;
  /** How many ratings stand behind it. */
  count: number;
}

// One lookup per build, not one per page that asks.
let cached: AppRating | null | undefined;

export async function getAppRating(appStoreId: string): Promise<AppRating | null> {
  if (cached !== undefined) return cached;
  try {
    const res = await fetch(`${LOOKUP}?id=${appStoreId}&country=us`, {
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`itunes lookup returned ${res.status}`);
    const data = await res.json();
    const result = data?.results?.[0];
    const value = Number(result?.averageUserRating);
    const count = Number(result?.userRatingCount);

    // Apple reports a brand-new app as 0 stars from 0 ratings. That is absence
    // of data, not a zero-star app, and marking it up would be a lie told in
    // schema.org — so it is filtered here rather than at each call site.
    if (!Number.isFinite(value) || !Number.isFinite(count) || count < 1 || value <= 0) {
      cached = null;
      return cached;
    }
    cached = { value: Math.round(value * 10) / 10, count };
  } catch (err) {
    console.warn('[app-store] rating lookup failed, omitting rating:', err instanceof Error ? err.message : err);
    cached = null;
  }
  return cached;
}
