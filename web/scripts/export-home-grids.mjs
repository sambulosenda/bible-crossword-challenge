// Copies the few real puzzles the home page draws from the app bundle into
// src/data/home-grids.json, so the page shows grids the app actually ships
// rather than invented patterns.
//
// The output is committed: the site build never reaches outside web/, so a
// change to the app's puzzles shows up here only when this is re-run.
//
//   node scripts/export-home-grids.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SOURCE = new URL('../../Bible Crossword Challenge/Resources/puzzles.json', import.meta.url);
const OUT = new URL('../src/data/home-grids.json', import.meta.url);

const HERO_PUZZLE = 'daily-011'; // Jonah and the Whale
const HERO_ANSWER = 'JONAH';
const SUNDAY_PUZZLE = 'sunday-001'; // From Eden to Ararat

// Home theme cards: landing page → the app puzzle whose grid is its thumbnail.
const THEMES = [
  { href: '/puzzles/noahs-ark/', tag: 'Genesis 6–9', name: "Noah's Ark", puzzle: 'Noah and the Flood' },
  { href: '/puzzles/david-and-goliath/', tag: '1 Samuel 17', name: 'David and Goliath', puzzle: 'David and Goliath' },
  { href: '/puzzles/ten-commandments/', tag: 'Exodus 20', name: 'The Ten Commandments', puzzle: 'The Ten Commandments' },
  { href: '/puzzles/psalm-23/', tag: 'Psalm 23', name: 'The Lord Is My Shepherd', puzzle: 'The Lord Is My Shepherd' },
  { href: '/puzzles/christmas/', tag: 'Luke 2 · Matthew 2', name: 'The Christmas Story', puzzle: 'The Christmas Story' },
  { href: '/puzzles/easter/', tag: 'Matthew 28', name: 'Easter: He Is Risen', puzzle: 'He Is Risen' },
  { href: '/puzzles/books-of-the-bible/', tag: 'Genesis to Revelation', name: 'Books of the Bible', puzzle: 'Books of the Old Testament' },
];

const puzzles = JSON.parse(readFileSync(SOURCE, 'utf8'));
const byId = new Map(puzzles.map((p) => [p.id, p]));
const byTitle = new Map(puzzles.filter((p) => p.size === 15).map((p) => [p.title, p]));

function need(map, key) {
  const p = map.get(key);
  if (!p) throw new Error(`export-home-grids: no puzzle "${key}" in ${fileURLToPath(SOURCE)}`);
  return p;
}

// The app's grid rows use '.' for a block and a letter for an open square.
// Thumbnails only need the shape: '#' block, '.' open.
const shape = (grid) => grid.map((row) => row.replace(/[^.]/g, 'o').replace(/\./g, '#').replace(/o/g, '.'));

const hero = need(byId, HERO_PUZZLE);
const heroClue = hero.clues.find((c) => c.answer === HERO_ANSWER);
if (!heroClue) throw new Error(`export-home-grids: ${HERO_PUZZLE} has no ${HERO_ANSWER} clue`);

const sunday = need(byId, SUNDAY_PUZZLE);
// One across entry is shown solved on the page, as if mid-puzzle.
const shown = sunday.clues.find((c) => c.answer === 'INTHEBEGINNING');

const out = {
  hero: {
    puzzle: hero.title,
    number: heroClue.number,
    direction: heroClue.direction,
    clue: heroClue.text,
    answer: heroClue.answer,
    verse: hero.verse,
    reference: hero.reference,
  },
  sunday: {
    title: sunday.title,
    size: sunday.size,
    clueCount: sunday.clues.length,
    grid: shape(sunday.grid),
    shown: { row: shown.row, col: shown.col, answer: shown.answer, clue: shown.text },
  },
  themes: THEMES.map(({ puzzle, ...t }) => ({ ...t, grid: shape(need(byTitle, puzzle).grid) })),
  counts: {
    sunday: puzzles.filter((p) => p.kind === 'sunday').length,
    mini: puzzles.filter((p) => p.kind === 'mini').length,
  },
};

writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n');
console.log(`export-home-grids: wrote ${fileURLToPath(OUT)}`);
