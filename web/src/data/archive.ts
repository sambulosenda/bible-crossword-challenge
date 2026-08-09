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

/** Every puzzle in the app, grouped by difficulty. [title, closing verse]. */
const TIERS: { difficulty: string; items: [string, string][] }[] = [
  {
    difficulty: 'Easy',
    items: [
      ['Animals of the Bible', 'Isaiah 11:6'], ['Crossing the Red Sea', 'Exodus 14:22'], ["Daniel in the Lions' Den", 'Daniel 6:22'], ['David and Goliath', '1 Samuel 17:45'], ['Faith, Hope, and Love', '1 Corinthians 13:13'], ['Father Abraham', 'Genesis 15:6'], ['Feeding the Five Thousand', 'John 6:9'], ['Fruits of Faith', 'Galatians 5:22'], ['He Is Risen', 'Matthew 28:6'], ['In the Beginning', 'Genesis 1:1'], ['Jonah and the Whale', 'Jonah 1:17'], ['Joseph the Dreamer', 'Genesis 37:3'], ['King David', 'Psalm 23:1'], ['Noah and the Flood', 'Genesis 7:1'], ['Praise and Worship', 'Psalm 95:1'], ['Samson and Delilah', 'Judges 13:24'], ['Samuel Hears God', '1 Samuel 3:10'], ['The Burning Bush', 'Exodus 3:2'], ['The Christmas Story', 'Luke 2:7'], ['The Garden of Eden', 'Genesis 2:18'], ['The Good Samaritan', 'Luke 10:27'], ['The Lord Is My Shepherd', 'Psalm 23:1'], ["The Lord's Prayer", 'Matthew 6:9'], ['The Prodigal Son', 'Luke 15:24'], ['The Ten Commandments', 'Exodus 20:12'], ['The Twelve Disciples', 'Mark 3:14'], ['The Walls of Jericho', 'Joshua 6:20'], ['Wise Men from the East', 'Matthew 2:2'], ['All Things Work Together', 'Romans 8:28'], ['God Is Love', '1 John 4:8'], ['Through Christ Which Strengtheneth', 'Philippians 4:13'],
    ],
  },
  {
    difficulty: 'Medium',
    items: [
      ['Angels of the Bible', 'Psalm 91:11'], ['Calming the Storm', 'Mark 4:39'], ["Gideon's Three Hundred", 'Judges 7:7'], ['Isaac and Rebekah', 'Genesis 25:21'], ["Jacob's Ladder", 'Genesis 28:12'], ['John the Baptist', 'Matthew 3:1'], ['King Saul', '1 Samuel 10:24'], ['Manna in the Wilderness', 'Exodus 16:14'], ['Miracles of Jesus', 'John 20:30'], ['Parables of the Kingdom', 'Matthew 13:44'], ['Places in the Holy Land', 'Micah 5:2'], ['Promises of God', '2 Corinthians 1:20'], ['Queen Esther', 'Esther 4:14'], ['Saul on the Damascus Road', 'Acts 9:4'], ['Sermon on the Mount', 'Matthew 5:14'], ["Solomon's Wisdom", 'Proverbs 1:7'], ['Songs of Praise', 'Psalm 100:1'], ['The Armour of God', 'Ephesians 6:11'], ['The Ascension', 'Acts 1:10'], ['The Baptism of Jesus', 'Mark 1:11'], ['The Beatitudes', 'Matthew 5:5'], ['The Crucifixion', 'Luke 23:33'], ['The Day of Pentecost', 'Acts 2:4'], ['The Fiery Furnace', 'Daniel 3:25'], ['The Fruit of the Spirit', 'Galatians 5:22'], ['The Good Shepherd', 'John 10:11'], ['The Last Supper', 'Luke 22:19'], ['The Parable of the Sower', 'Matthew 13:3'], ['The Patience of Job', 'Job 1:21'], ['The Story of Ruth', 'Ruth 1:16'], ['The Ten Plagues', 'Exodus 11:1'], ['The Tower of Babel', 'Genesis 11:4'], ['Walking on Water', 'Matthew 14:27'], ['Women of the Bible', 'Proverbs 31:25'], ['Words of the Wise', 'Proverbs 3:5'], ['A Time to Every Purpose', 'Ecclesiastes 3:1'], ['Casting All Your Care', '1 Peter 5:7'], ['Faith Without Works', 'James 2:26'], ['Thoughts of Peace', 'Jeremiah 29:11'],
    ],
  },
  {
    difficulty: 'Hard',
    items: [
      ['Books of the New Testament', 'John 3:16'], ['Books of the Old Testament', 'Genesis 1:1'], ['Elijah and the Fire', '1 Kings 18:38'], ['Elisha the Prophet', '2 Kings 4:36'], ['Feasts and Festivals', 'Acts 2:1'], ['Kings of Israel and Judah', '1 Kings 2:12'], ['Lazarus, Come Forth', 'John 11:25'], ['Nehemiah Rebuilds', 'Nehemiah 2:20'], ["Paul's Journeys", 'Acts 1:8'], ['Shipwrecked on Malta', 'Acts 27:25'], ['Tempted in the Desert', 'Matthew 4:3'], ['The Book of Revelation', 'Revelation 1:8'], ['The Early Church', 'Acts 2:42'], ['The Garden of Gethsemane', 'Mark 14:36'], ['The Major Prophets', 'Isaiah 40:8'], ['The Names of God', 'Exodus 3:14'], ['The Road to Emmaus', 'Luke 24:31'], ['The Tabernacle', 'Exodus 25:8'], ['The Transfiguration', 'Mark 9:3'], ['I Change Not', 'Malachi 3:6'], ['New Every Morning', 'Lamentations 3:23'], ['With All Thine Heart', 'Deuteronomy 6:5'],
    ],
  },
];

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
  'The Armour of God': '/puzzles/armour-of-god/',
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

/** Minis are not enumerated here, so this one is typed. Keep it in step with
 * `puzzles.json` — `kind: "mini"` — when the bank grows. */
export const MINI_COUNT = 90;
