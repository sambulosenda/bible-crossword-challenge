import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
// The puzzle archive, in one place. The /puzzles/ page renders it, the ItemList
// structured data enumerates it, and /llms.txt lists it for answer engines —
// so it lives here rather than being retyped in three templates.

/** Themes that have a landing page of their own. */
export const FEATURED = [
  { href: '/puzzles/noahs-ark/', eyebrow: 'Genesis 6&ndash;9', name: "Noah's Ark", sub: 'Easy · Bible crossword' },
  { href: '/puzzles/david-and-goliath/', eyebrow: '1 Samuel 17', name: 'David and Goliath', sub: 'Easy · Bible crossword' },
  { href: '/puzzles/christmas/', eyebrow: 'Luke 2 · Matthew 2', name: 'Christmas', sub: 'Easy · Bible crossword' },
  { href: '/puzzles/easter/', eyebrow: 'Matthew 28', name: 'Easter', sub: 'Easy · Bible crossword' },
  { href: '/puzzles/ten-commandments/', eyebrow: 'Exodus 20', name: 'Ten Commandments', sub: 'Easy · Bible crossword' },
  { href: '/puzzles/psalm-23/', eyebrow: "The Shepherd&rsquo;s Psalm", name: 'Psalm 23', sub: 'Easy · Bible crossword' },
  { href: '/puzzles/books-of-the-bible/', eyebrow: 'Genesis to Revelation', name: 'Books of the Bible', sub: 'Hard · Bible crossword' },
] as const;

/**
 * The app's own puzzle bank, read at build time so every count and list on the
 * site matches what ships. It used to be typed here by hand and drifted: the
 * site said 92 puzzles and 90 minis while the App Store said 290+. Ids are
 * content-stable (see the iOS generator), titles are what the app shows.
 */
type BankPuzzle = { id: string; title: string; difficulty: string; reference: string };
const BANK: BankPuzzle[] = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../../Bible Crossword Challenge/Resources/puzzles.json', import.meta.url)), 'utf8'),
);
const kind = (p: BankPuzzle) => (p.id.startsWith('pack-') ? 'pack' : p.id.split('-')[0]);
const count = (k: string) => BANK.filter((p) => kind(p) === k).length;

/** Every puzzle in the app, grouped by difficulty. [title, closing verse]. */
const TIERS: { difficulty: string; items: [string, string][] }[] = ['Easy', 'Medium', 'Hard'].map((difficulty) => ({
  difficulty,
  items: BANK.filter((p) => kind(p) === 'daily' && p.difficulty.toLowerCase() === difficulty.toLowerCase())
    .map((p) => [p.title, p.reference] as [string, string])
    .sort((a, b) => a[0].localeCompare(b[0])),
}));

/**
 * Archive puzzle title → the theme landing page that covers it.
 *
 * The two naming systems are deliberately different: the archive lists the
 * puzzle names as they appear in the app, while a landing page covers a whole
 * theme (/puzzles/christmas/ speaks for both *The Christmas Story* and *Wise
 * Men from the East*). So the link is stated here rather than guessed from the
 * titles, which only ever matched by luck.
 */
/** Archive title → its landing page. Drives both the ItemList structured data
    and the links in the visible archive list, so an entry added here is
    immediately crawlable from the hub. Several titles share a page where the
    app ships two puzzles on one subject — two near-identical pages would be
    thin content, one page linked twice is not. */
export const THEME_PAGE: Record<string, string> = {
  'David and Goliath': '/puzzles/david-and-goliath/',
  'Noah and the Flood': '/puzzles/noahs-ark/',
  'The Christmas Story': '/puzzles/christmas/',
  'Wise Men from the East': '/puzzles/christmas/',
  'He Is Risen': '/puzzles/easter/',
  'The Ten Commandments': '/puzzles/ten-commandments/',
  'The Lord Is My Shepherd': '/puzzles/psalm-23/',
  'Books of the Old Testament': '/puzzles/books-of-the-bible/',
  'Books of the New Testament': '/puzzles/books-of-the-bible/',
  'Jonah and the Whale': '/puzzles/jonah-and-the-whale/',
  "Daniel in the Lions' Den": '/puzzles/daniel-in-the-lions-den/',
  'The Good Samaritan': '/puzzles/the-good-samaritan/',
  'The Prodigal Son': '/puzzles/the-prodigal-son/',
  "The Lord's Prayer": '/puzzles/the-lords-prayer/',
  'The Armor of God': '/puzzles/armour-of-god/',
  'The Fruit of the Spirit': '/puzzles/fruit-of-the-spirit/',
  'Fruits of Faith': '/puzzles/fruit-of-the-spirit/',
  'The Beatitudes': '/puzzles/the-beatitudes/',
  'In the Beginning': '/puzzles/in-the-beginning/',
  'The Garden of Eden': '/puzzles/garden-of-eden/',
  'Crossing the Red Sea': '/puzzles/crossing-the-red-sea/',
  'The Burning Bush': '/puzzles/the-burning-bush/',
  'The Walls of Jericho': '/puzzles/the-walls-of-jericho/',
  'Father Abraham': '/puzzles/father-abraham/',
  'Joseph the Dreamer': '/puzzles/joseph-the-dreamer/',
  'Isaac and Rebekah': '/puzzles/isaac-and-rebekah/',
  "Jacob's Ladder": '/puzzles/jacobs-ladder/',
  'Samson and Delilah': '/puzzles/samson-and-delilah/',
  "Gideon's Three Hundred": '/puzzles/gideons-three-hundred/',
  'Samuel Hears God': '/puzzles/samuel-hears-god/',
  'King Saul': '/puzzles/king-saul/',
  'King David': '/puzzles/king-david/',
  'Animals of the Bible': '/puzzles/animals-of-the-bible/',
  'Faith, Hope, and Love': '/puzzles/faith-hope-and-love/',
  'Praise and Worship': '/puzzles/praise-and-worship/',
  'Songs of Praise': '/puzzles/songs-of-praise/',
  'Feeding the Five Thousand': '/puzzles/feeding-the-five-thousand/',
  'Calming the Storm': '/puzzles/calming-the-storm/',
  'Walking on Water': '/puzzles/walking-on-water/',
  'The Twelve Disciples': '/puzzles/the-twelve-disciples/',
  'Angels of the Bible': '/puzzles/angels-of-the-bible/',
  'John the Baptist': '/puzzles/john-the-baptist/',
  'Manna in the Wilderness': '/puzzles/manna-in-the-wilderness/',
  'Miracles of Jesus': '/puzzles/miracles-of-jesus/',
  'Parables of the Kingdom': '/puzzles/parables-of-the-kingdom/',
  'The Parable of the Sower': '/puzzles/the-parable-of-the-sower/',
  'Places in the Holy Land': '/puzzles/places-in-the-holy-land/',
  'Promises of God': '/puzzles/promises-of-god/',
  'Queen Esther': '/puzzles/queen-esther/',
  'Saul on the Damascus Road': '/puzzles/saul-on-the-damascus-road/',
  'Sermon on the Mount': '/puzzles/sermon-on-the-mount/',
  "Solomon's Wisdom": '/puzzles/solomons-wisdom/',
  'The Ascension': '/puzzles/the-ascension/',
  'The Baptism of Jesus': '/puzzles/the-baptism-of-jesus/',
  'The Crucifixion': '/puzzles/the-crucifixion/',
  'The Day of Pentecost': '/puzzles/the-day-of-pentecost/',
  'The Fiery Furnace': '/puzzles/the-fiery-furnace/',
  'The Good Shepherd': '/puzzles/the-good-shepherd/',
  'The Last Supper': '/puzzles/the-last-supper/',
  'The Patience of Job': '/puzzles/the-patience-of-job/',
  'The Story of Ruth': '/puzzles/the-story-of-ruth/',
  'The Ten Plagues': '/puzzles/the-ten-plagues/',
  'The Tower of Babel': '/puzzles/the-tower-of-babel/',
  'Women of the Bible': '/puzzles/women-of-the-bible/',
  'Words of the Wise': '/puzzles/words-of-the-wise/',
  'Elijah and the Fire': '/puzzles/elijah-and-the-fire/',
  'Elisha the Prophet': '/puzzles/elisha-the-prophet/',
  'Feasts and Festivals': '/puzzles/feasts-and-festivals/',
  'Kings of Israel and Judah': '/puzzles/kings-of-israel-and-judah/',
  'Lazarus, Come Forth': '/puzzles/lazarus-come-forth/',
  'Nehemiah Rebuilds': '/puzzles/nehemiah-rebuilds/',
  "Paul's Journeys": '/puzzles/pauls-journeys/',
  'Shipwrecked on Malta': '/puzzles/shipwrecked-on-malta/',
  'Tempted in the Desert': '/puzzles/tempted-in-the-desert/',
  'The Book of Revelation': '/puzzles/the-book-of-revelation/',
  'The Early Church': '/puzzles/the-early-church/',
  'The Garden of Gethsemane': '/puzzles/the-garden-of-gethsemane/',
  'The Major Prophets': '/puzzles/the-major-prophets/',
  'The Names of God': '/puzzles/the-names-of-god/',
  'The Road to Emmaus': '/puzzles/the-road-to-emmaus/',
  'The Tabernacle': '/puzzles/the-tabernacle/',
  'The Transfiguration': '/puzzles/the-transfiguration/',
};

/** Total full-size puzzles, derived so the count on the page can never drift. */
/** The tier heading, built from the list it labels rather than typed beside it.
 *
 * It used to be a literal — "Easy · 28 puzzles" — and it went stale the moment
 * ten dailies shipped without anyone editing this file, leaving the page
 * counting 82 puzzles while the app held 92. A heading that derives from its
 * own list cannot disagree with it. */
export const ARCHIVE = TIERS.map((t) => ({
  ...t,
  tier: `${t.difficulty} · ${t.items.length} puzzles`,
}));

export const PUZZLE_COUNT = ARCHIVE.reduce((n, g) => n + g.items.length, 0);

export const MINI_COUNT = count('mini');
export const SUNDAY_COUNT = count('sunday');
export const PACK_COUNT = count('pack');
/** Everything a Premium player can open: dailies, minis, Sunday Specials and pack puzzles. */
export const TOTAL_COUNT = BANK.length;
/** Rounded down to ten for copy ("more than 290"), so a new puzzle never makes it wrong. */
export const TOTAL_ROUNDED = Math.floor(TOTAL_COUNT / 10) * 10;
