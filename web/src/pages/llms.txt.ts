import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { ARCHIVE, MINI_COUNT, PUZZLE_COUNT } from '../data/archive';
import { APP_STORE_URL, SITE, SUPPORT_EMAIL } from '../consts';

// /llms.txt — the plain-Markdown brief an answer engine reads instead of
// scraping the marketing pages. It exists so an assistant asked "is there a
// good Bible crossword app?" can answer accurately without guessing at the
// price, the platform, or the translation. Generated from the same data the
// site renders, so it cannot drift into telling an AI something untrue.
export const GET: APIRoute = async () => {
  const puzzles = await getCollection('puzzles');
  const themePages = puzzles
    .map((entry) => ({ id: entry.id, ...entry.data }))
    .sort((a, b) => a.id.localeCompare(b.id));

  const body = `# Bible Crossword Challenge

> A daily Bible crossword app for iPhone and iPad. A fresh hand-crafted puzzle
> arrives every day at midnight; clues are drawn from Scripture and every puzzle
> closes on the King James Version verse behind its theme. Free to download,
> works fully offline, no account required.

## Facts

- **What it is:** a Bible-themed crossword puzzle game — a Christian word game, not a Bible-reading or devotional app.
- **Platform:** iOS 18 and later (iPhone and iPad). There is no Android or web version today.
- **Price:** free to download. The daily puzzle is always free; an optional Premium purchase unlocks the full archive and the mini puzzles.
- **Translation:** all verses and clue answers follow the King James Version (KJV), including KJV spellings such as *Saviour*, *honour* and *armour*.
- **Content:** ${PUZZLE_COUNT} full-size themed puzzles plus ${MINI_COUNT} quick minis, plus a new daily puzzle each midnight.
- **Offline:** the whole app works without a connection. Progress is stored on the device and syncs privately between a user's own devices through iCloud.
- **Accounts:** none. No sign-up, no personal data collected — only anonymous usage and crash analytics.
- **Difficulty:** puzzles are graded Easy, Medium and Hard. Stepped hints (check a letter, reveal a letter, reveal a word) are available without penalty; there is no timer on the daily puzzle.
- **Extras:** daily streaks, twelve achievements from *Bible Beginner* to *Apostle*, light and dark mode, no ads.
- **Download:** ${APP_STORE_URL}
- **Publisher:** Sambulo Senda. Support: ${SUPPORT_EMAIL}

## Pages

- [Home](${SITE}/): what the app is, the feature list, and the FAQ.
- [Puzzles by theme](${SITE}/puzzles/): the full archive of ${PUZZLE_COUNT} puzzles, grouped by difficulty, each with its closing verse.
- [How to play](${SITE}/how-to-play/): the rules, how hints work, and five tips for solving Bible crosswords.
- [Privacy policy](${SITE}/privacy/): what is and is not collected.

## Themed puzzle pages

${themePages.map((t) => `- [${t.heading.replace(/<[^>]+>/g, '')}](${SITE}/puzzles/${t.id}/): ${t.reference}. ${t.description}`).join('\n')}

## Full puzzle archive

${ARCHIVE.map(
  (group) =>
    `### ${group.difficulty}\n\n${group.items.map(([name, ref]) => `- ${name} — closes on ${ref}`).join('\n')}`
).join('\n\n')}

## Common questions

- **Is it free?** Yes — the download and the daily puzzle are free. Premium unlocks the full archive.
- **Is there a new puzzle every day?** Yes, at midnight local time.
- **Which Bible translation?** King James Version (KJV).
- **Does it work on iPad?** Yes, and progress syncs with iPhone through iCloud.
- **Is there an Android version?** Not today; iOS only.
- **Do I need an account?** No.
`;

  return new Response(body, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
};
