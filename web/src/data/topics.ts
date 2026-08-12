// Topic hubs: curated slices of the theme-page collection, in one place so the
// hub pages, the /puzzles/ index links, and the sitemap can never disagree
// about which hubs exist.
//
// Membership is derived from each theme page's own data (reference book,
// difficulty chip) rather than hand-listed, so a new theme page lands in the
// right hubs automatically.

type ThemeFacts = { slug: string; reference: string; difficulty: string };

const OT_BOOKS =
  /\b(Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|Samuel|Kings|Chronicles|Ezra|Nehemiah|Esther|Job|Psalm|Proverbs|Ecclesiastes|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi)\b/;
const NT_BOOKS =
  /\b(Matthew|Mark|Luke|John|Acts|Romans|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Titus|Philemon|Hebrews|James|Peter|Jude|Revelation|Gospels)\b/;

// "Genesis to Revelation" spans the whole Bible — claiming it for either
// testament hub would be wrong, so those pages live only on the main index.
const WHOLE_BIBLE = /Genesis to Revelation/;

// The church-calendar arc: Advent and Christmas, then Holy Week through
// Pentecost. Curated by slug — a reference line can't tell "Easter story"
// from "story that happens to be in Luke".
const HOLIDAY_SLUGS = new Set([
  'christmas',
  'easter',
  'the-last-supper',
  'the-garden-of-gethsemane',
  'the-crucifixion',
  'the-road-to-emmaus',
  'the-ascension',
  'the-day-of-pentecost',
  'feasts-and-festivals',
]);

export type Topic = {
  slug: string;
  path: string;
  name: string;
  title: string;
  description: string;
  eyebrow: string;
  h1: string;
  intro: string[];
  match: (t: ThemeFacts) => boolean;
};

export const TOPICS: Topic[] = [
  {
    slug: 'old-testament',
    path: '/puzzles/old-testament/',
    name: 'Old Testament',
    title: 'Old Testament Bible Crossword Puzzles — Bible Crossword Challenge',
    description:
      'Bible crossword puzzles from the Old Testament — Creation, the Exodus, David, Daniel, and the prophets. Play free on iPhone and iPad, or print the PDF.',
    eyebrow: 'Genesis to Malachi',
    h1: 'Old Testament crossword puzzles',
    intro: [
      'From the first words of Genesis to the last of the prophets, these puzzles walk the Old Testament story by story: the ark and the flood, the parted sea, a shepherd boy with five smooth stones, a night in the lions&rsquo; den. Every clue is drawn from the King James Version, and every puzzle ends on the verse at the heart of its story.',
      'Play any theme free in the app, or use the printable PDF on its page for Sunday school and home study.',
    ],
    match: (t) => !WHOLE_BIBLE.test(t.reference) && OT_BOOKS.test(t.reference),
  },
  {
    slug: 'new-testament',
    path: '/puzzles/new-testament/',
    name: 'New Testament',
    title: 'New Testament Bible Crossword Puzzles — Bible Crossword Challenge',
    description:
      'Bible crossword puzzles from the New Testament — the Gospels, the parables, the miracles, and the early church. Play free on iPhone and iPad, or print the PDF.',
    eyebrow: 'Matthew to Revelation',
    h1: 'New Testament crossword puzzles',
    intro: [
      'The manger in Bethlehem, the Sermon on the Mount, a storm calmed with a word, an empty tomb at dawn &mdash; these puzzles build their grids from the Gospels, the Acts of the Apostles, and the letters that followed. Every clue is rooted in the King James Version, and every puzzle closes on Scripture.',
      'Play any theme free in the app, or use the printable PDF on its page for Sunday school and home study.',
    ],
    match: (t) => !WHOLE_BIBLE.test(t.reference) && NT_BOOKS.test(t.reference),
  },
  {
    slug: 'christmas-and-easter',
    path: '/puzzles/christmas-and-easter/',
    name: 'Christmas & Easter',
    title: 'Christmas & Easter Bible Crossword Puzzles — Bible Crossword Challenge',
    description:
      'Seasonal Bible crossword puzzles for Christmas, Holy Week, Easter, and Pentecost. Play free on iPhone and iPad, or print the PDF for church and Sunday school.',
    eyebrow: 'The church year',
    h1: 'Christmas &amp; Easter crossword puzzles',
    intro: [
      'The great seasons of the church year, as crosswords: the star over Bethlehem and the wise men&rsquo;s gifts, the upper room and the garden, the cross, the empty tomb, and the rushing wind of Pentecost. Good for Advent calendars, Holy Week devotionals, and the Sunday school table.',
      'Play any theme free in the app, or print the PDF from its page &mdash; each printable includes the full grid, clues, and answer key.',
    ],
    match: (t) => HOLIDAY_SLUGS.has(t.slug),
  },
  {
    slug: 'for-kids',
    path: '/puzzles/for-kids/',
    name: 'For kids',
    title: 'Bible Crossword Puzzles for Kids — Bible Crossword Challenge',
    description:
      'Easy Bible crossword puzzles for kids and Sunday school — Noah’s Ark, David and Goliath, Jonah, and more. Play free on iPad, or print the free PDF.',
    eyebrow: 'Easy difficulty',
    h1: 'Bible crosswords for kids',
    intro: [
      'Every puzzle here is graded <em>Easy</em>: the stories children already love &mdash; the animals boarding the ark, Jonah and the great fish, a giant felled by a sling &mdash; with short answers and clues that can be solved straight from the story. Fair hints in the app help young solvers over a hard square without giving the puzzle away.',
      'For classrooms and Sunday school, every theme page has a free printable PDF with the grid, the clues, and an answer key for the teacher.',
    ],
    match: (t) => t.difficulty === 'Easy',
  },
];

/** Difficulty as carried in the theme page's meta chip line ("15×15 grid · Easy · …"). */
export const difficultyOf = (meta: string) =>
  meta.split('·').map((s) => s.trim()).find((s) => /^(Easy|Medium|Hard)$/.test(s)) ?? '';
