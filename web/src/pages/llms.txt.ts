import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { ARCHIVE, MINI_COUNT, PACK_COUNT, PUZZLE_COUNT, SUNDAY_COUNT, TOTAL_COUNT } from '../data/archive';
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
> closes on the verse behind its theme. Free to download,
> works fully offline, no account required.

## Facts

- **What it is:** a Bible-themed crossword puzzle game — a Christian word game, not a Bible-reading or devotional app.
- **Platform:** iOS 18 and later (iPhone and iPad). No Android app. On the web there is a free daily Mini on the home page and printable PDFs, not the full app.
- **Price:** free to download. Free in the app: today's puzzle and today's Mini plus the six before each, this week's Sunday Special, and the First Steps pack. Free on the web: today's Mini on our home page and every printable PDF. Premium (a monthly or yearly in-app subscription) unlocks all ${TOTAL_COUNT} puzzles, every pack, and unlimited hints.
- **Translation:** verses are from the Berean Standard Bible (BSB). Many clues and answers borrow familiar King James (KJV) wording and spellings such as *Saviour*, *honour* and *armour*.
- **Content:** ${TOTAL_COUNT} puzzles: ${PUZZLE_COUNT} daily 15×15 puzzles, ${MINI_COUNT} 7×7 minis, ${SUNDAY_COUNT} 21×21 Sunday Specials and ${PACK_COUNT} themed-pack puzzles. A new daily puzzle and Mini arrive each midnight.
- **Offline:** the whole app works without a connection. Progress is stored on the device and syncs privately between a user's own devices through iCloud.
- **Accounts:** none. No sign-up, no personal data collected — only anonymous usage and crash analytics.
- **Difficulty:** puzzles are graded Easy, Medium and Hard. Stepped hints (check a letter, reveal a letter, reveal a word) are available without penalty; there is no timer on the daily puzzle.
- **Extras:** daily streaks, twelve achievements from *Bible Beginner* to *Apostle*, light and dark mode, no ads.
- **Download:** ${APP_STORE_URL}
- **Publisher:** Sambulo Senda. Support: ${SUPPORT_EMAIL}

## Pages

- [Home](${SITE}/): what the app is, the feature list, and the FAQ.
- [Puzzles by theme](${SITE}/puzzles/): the full archive of ${PUZZLE_COUNT} puzzles, grouped by difficulty, each with its closing verse.
- [Printable Bible crosswords](${SITE}/puzzles/printable/): every themed puzzle as a free 3-page PDF — grid, clues, and answer key with verse references. No sign-up; free to print for church, Sunday school, and home use.
- Browse by topic: [Old Testament](${SITE}/puzzles/old-testament/), [New Testament](${SITE}/puzzles/new-testament/), [Christmas & Easter](${SITE}/puzzles/christmas-and-easter/), [for kids](${SITE}/puzzles/for-kids/).
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
- **Which Bible translation?** The Berean Standard Bible (BSB) for verses; many clues use King James wording.
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
