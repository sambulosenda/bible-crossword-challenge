// Build-time printable PDF generation.
//
// For every theme page in src/content/puzzles/, finds the matching puzzle in
// the app bundle (../Bible Crossword Challenge/Resources/puzzles.json) and
// writes a 3-page printable to public/printables/<slug>.pdf:
//   page 1 — empty numbered grid + verse + app QR
//   page 2 — across/down clues
//   page 3 — answer key
//
// The build fails if any theme page has no matching app puzzle, so a new
// theme page always ships with its printable (add an ALIASES entry if the
// web slug and app title differ).
//
// PDFs live under /printables/, NOT /assets/ — /assets/* is edge-cached
// immutable for a year and must never be regenerated in place.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WEB = path.join(__dirname, '..');
const CONTENT = path.join(WEB, 'src/content/puzzles');
const OUT = path.join(WEB, 'public/printables');
const APP_PUZZLES = path.join(WEB, '../Bible Crossword Challenge/Resources/puzzles.json');

const SITE = 'https://biblecrosswordchallenge.com';
// /go?s=printable → App Store with ct=printable, so installs from PDFs show
// up under Acquisition → Campaigns like every other channel.
const QR_URL = `${SITE}/go?s=printable`;

// Web slugs whose app puzzle title doesn't slugify to the same string.
const ALIASES = {
  'christmas': 'daily-019',           // The Christmas Story
  'easter': 'daily-009',              // He Is Risen
  'noahs-ark': 'daily-014',           // Noah and the Flood
  'psalm-23': 'mini-024',             // The Shepherd's Psalm (7×7 mini)
  'books-of-the-bible': 'daily-065',  // Books of the Old Testament
  'armour-of-god': 'mini-026',        // The Whole Armor (title went US-spelling 2026-09-04)
};

const slugify = (t) =>
  t.toLowerCase()
    .replace(/&/g, 'and')
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^the-/, '')
    .replace(/^-+|-+$/g, '');

const puzzles = JSON.parse(fs.readFileSync(APP_PUZZLES, 'utf8'));
const byId = new Map(puzzles.map((p) => [p.id, p]));
const bySlug = new Map();
for (const p of puzzles) {
  const s = slugify(p.title);
  const prev = bySlug.get(s);
  // Prefer full-size dailies over minis/packs when titles collide.
  if (!prev || (p.id.startsWith('daily-') && !prev.id.startsWith('daily-'))) bySlug.set(s, p);
}

const themeSlugs = fs.readdirSync(CONTENT)
  .filter((f) => f.endsWith('.json'))
  .map((f) => f.slice(0, -5));

const unmatched = themeSlugs.filter((s) => !(s in ALIASES) && !bySlug.has(s) && !bySlug.has(s.replace(/^the-/, '')));
if (unmatched.length) {
  console.error(`generate-printables: no app puzzle for theme page(s): ${unmatched.join(', ')}`);
  console.error('Add an ALIASES entry in web/scripts/generate-printables.mjs.');
  process.exit(1);
}

const PAGE = { w: 612, h: 792, margin: 54 }; // US Letter
const INK = '#1c1917';
const FAINT = '#78716c';
const RULE = '#d6d3d1';

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

function numberGrid(p) {
  // Map "row,col" → clue number for cells where an entry starts.
  const nums = new Map();
  for (const c of p.clues) nums.set(`${c.row},${c.col}`, c.number);
  return nums;
}

function drawGrid(doc, p, { x, y, size, letters }) {
  const cell = size / p.size;
  const nums = numberGrid(p);
  for (let r = 0; r < p.size; r++) {
    for (let c = 0; c < p.size; c++) {
      const ch = p.grid[r][c];
      const cx = x + c * cell;
      const cy = y + r * cell;
      if (ch === '.') {
        doc.rect(cx, cy, cell, cell).fill('#000000');
        continue;
      }
      doc.rect(cx, cy, cell, cell).lineWidth(0.6).stroke('#000000');
      const n = nums.get(`${r},${c}`);
      if (n !== undefined) {
        doc.font('Helvetica').fontSize(cell * 0.26).fillColor(INK)
          .text(String(n), cx + 1.5, cy + 1.5, { lineBreak: false });
      }
      if (letters) {
        doc.font('Helvetica-Bold').fontSize(cell * 0.52).fillColor(INK)
          .text(ch, cx, cy + cell * 0.3, { width: cell, align: 'center', lineBreak: false });
      }
    }
  }
}

function header(doc, p) {
  doc.font('Times-Bold').fontSize(21).fillColor(INK)
    .text(p.title, PAGE.margin, PAGE.margin, { width: PAGE.w - PAGE.margin * 2, align: 'center' });
  doc.moveDown(0.25);
  doc.font('Helvetica').fontSize(9.5).fillColor(FAINT)
    .text(`${p.reference}  ·  ${p.size}×${p.size}  ·  ${cap(p.difficulty)}  ·  Bible Crossword Challenge`,
      { width: PAGE.w - PAGE.margin * 2, align: 'center' });
}

function footer(doc, qrPng, withQr) {
  const y = PAGE.h - PAGE.margin - 26;
  doc.moveTo(PAGE.margin, y - 8).lineTo(PAGE.w - PAGE.margin, y - 8).lineWidth(0.5).stroke(RULE);
  doc.font('Helvetica').fontSize(8.5).fillColor(FAINT)
    .text('Free to print for church, Sunday school, and home use.', PAGE.margin, y, { lineBreak: false })
    .text('Play a new Bible crossword every day — free on iPhone & iPad', PAGE.margin, y + 11, { lineBreak: false });
  doc.font('Helvetica-Bold').fontSize(8.5).fillColor(INK)
    .text('biblecrosswordchallenge.com', PAGE.margin, y + 22, { lineBreak: false });
  if (withQr) doc.image(qrPng, PAGE.w - PAGE.margin - 40, y - 4, { width: 40 });
}

function clueColumn(doc, title, clues, x, width, y0) {
  doc.font('Times-Bold').fontSize(13).fillColor(INK).text(title, x, y0, { width });
  let y = y0 + 22;
  for (const c of clues) {
    const line = `${c.number}. ${c.text} (${c.answer.length})`;
    const h = doc.font('Helvetica').fontSize(9.5).heightOfString(line, { width });
    doc.fillColor(INK).text(line, x, y, { width });
    y += h + 6;
  }
  return y;
}

async function render(slug, p, qrPng) {
  const doc = new PDFDocument({ size: 'LETTER', margins: { top: 0, bottom: 0, left: 0, right: 0 }, autoFirstPage: false });
  doc.info.Title = `${p.title} — printable Bible crossword`;
  doc.info.Author = 'Bible Crossword Challenge';
  const out = fs.createWriteStream(path.join(OUT, `${slug}.pdf`));
  doc.pipe(out);

  // Page 1 — puzzle
  doc.addPage();
  header(doc, p);
  const gridSize = 396;
  const gx = (PAGE.w - gridSize) / 2;
  drawGrid(doc, p, { x: gx, y: 130, size: gridSize, letters: false });
  doc.font('Times-Italic').fontSize(10.5).fillColor(INK)
    .text(`“${p.verse}”  — ${p.reference}`, PAGE.margin + 20, 130 + gridSize + 22,
      { width: PAGE.w - (PAGE.margin + 20) * 2, align: 'center' });
  footer(doc, qrPng, true);

  // Page 2 — clues
  doc.addPage();
  header(doc, p);
  const across = p.clues.filter((c) => c.direction === 'across').sort((a, b) => a.number - b.number);
  const down = p.clues.filter((c) => c.direction === 'down').sort((a, b) => a.number - b.number);
  const colW = (PAGE.w - PAGE.margin * 2 - 30) / 2;
  clueColumn(doc, 'Across', across, PAGE.margin, colW, 130);
  clueColumn(doc, 'Down', down, PAGE.margin + colW + 30, colW, 130);
  const hasRefs = p.clues.some((c) => c.reference);
  doc.font('Helvetica').fontSize(9).fillColor(FAINT)
    .text(hasRefs
      ? 'Every answer comes from Scripture — the verse reference for each clue is in the answer key.'
      : 'Every answer comes from Scripture — the full answer key is on the last page.',
      PAGE.margin, PAGE.h - PAGE.margin - 62, { width: PAGE.w - PAGE.margin * 2 });
  footer(doc, qrPng, false);

  // Page 3 — answer key
  doc.addPage();
  doc.font('Times-Bold').fontSize(16).fillColor(INK)
    .text(`Answer key — ${p.title}`, PAGE.margin, PAGE.margin, { width: PAGE.w - PAGE.margin * 2, align: 'center' });
  const keySize = 300;
  drawGrid(doc, p, { x: (PAGE.w - keySize) / 2, y: 96, size: keySize, letters: true });
  // Answers with references, three columns.
  const refs = [...across.map((c) => ({ ...c, dir: 'A' })), ...down.map((c) => ({ ...c, dir: 'D' }))];
  const refW = (PAGE.w - PAGE.margin * 2 - 40) / 3;
  const perCol = Math.ceil(refs.length / 3);
  refs.forEach((c, i) => {
    const col = Math.floor(i / perCol);
    const row = i % perCol;
    doc.font('Helvetica').fontSize(7.8).fillColor(INK)
      .text(`${c.number}${c.dir}. ${c.answer}${c.reference ? ` — ${c.reference}` : ''}`,
        PAGE.margin + col * (refW + 20), 96 + keySize + 24 + row * 12,
        { width: refW, height: 11, ellipsis: true, lineBreak: false });
  });
  footer(doc, qrPng, true);

  doc.end();
  await new Promise((res, rej) => { out.on('finish', res); out.on('error', rej); });
}

// The starter pack: one downloadable bundle for outreach — bloggers link a
// single PDF far more readily than a directory of eighty. Two warm-up minis,
// then six full grids across the best-known stories; every answer key at the
// back so a teacher can print pages 2–17 for the class and keep the rest.
// The id list is curated, not derived: pack membership is an editorial call.
const PACK_IDS = [
  'mini-024',  // The Shepherd's Psalm (7×7 warm-up)
  'mini-009',  // He Is Risen (7×7 warm-up)
  'daily-004', // David and Goliath
  'daily-014', // Noah and the Flood
  'daily-023', // The Lord's Prayer
  'daily-025', // The Ten Commandments
  'daily-037', // Miracles of Jesus
  'daily-053', // The Fruit of the Spirit
];
const PACK_FILE = 'bible-crossword-starter-pack.pdf';

async function renderPack(qrPng) {
  const missing = PACK_IDS.filter((id) => !byId.has(id));
  if (missing.length) {
    console.error(`generate-printables: pack puzzle id(s) missing from app bundle: ${missing.join(', ')}`);
    process.exit(1);
  }
  const pack = PACK_IDS.map((id) => byId.get(id));

  const doc = new PDFDocument({ size: 'LETTER', margins: { top: 0, bottom: 0, left: 0, right: 0 }, autoFirstPage: false });
  doc.info.Title = 'Bible Crossword Starter Pack — 8 printable puzzles with answers';
  doc.info.Author = 'Bible Crossword Challenge';
  const out = fs.createWriteStream(path.join(OUT, PACK_FILE));
  doc.pipe(out);

  // Cover
  doc.addPage();
  doc.font('Times-Bold').fontSize(34).fillColor(INK)
    .text('The Bible Crossword\nStarter Pack', PAGE.margin, 170, { width: PAGE.w - PAGE.margin * 2, align: 'center' });
  doc.moveDown(0.6);
  doc.font('Helvetica').fontSize(12).fillColor(FAINT)
    .text('8 printable crosswords · every answer from Scripture · full answer keys',
      { width: PAGE.w - PAGE.margin * 2, align: 'center' });
  doc.moveDown(1.6);
  doc.font('Times-Roman').fontSize(11.5).fillColor(INK);
  pack.forEach((p, i) => {
    doc.text(`${i + 1}.  ${p.title}  ·  ${p.size}×${p.size}${p.id.startsWith('mini') ? '  (quick warm-up)' : ''}`,
      PAGE.margin + 130, doc.y, { lineBreak: true });
    doc.moveDown(0.35);
  });
  doc.moveDown(1.2);
  doc.font('Helvetica').fontSize(9.5).fillColor(FAINT)
    .text('Free to print and copy for church, Sunday school, homeschool, and home use.',
      PAGE.margin, doc.y, { width: PAGE.w - PAGE.margin * 2, align: 'center' });
  footer(doc, qrPng, true);

  // Puzzle + clue pages (answer keys all together at the back).
  for (const p of pack) {
    doc.addPage();
    header(doc, p);
    const gridSize = p.size <= 7 ? 300 : 396;
    drawGrid(doc, p, { x: (PAGE.w - gridSize) / 2, y: 130, size: gridSize, letters: false });
    doc.font('Times-Italic').fontSize(10.5).fillColor(INK)
      .text(`“${p.verse}”  — ${p.reference}`, PAGE.margin + 20, 130 + gridSize + 22,
        { width: PAGE.w - (PAGE.margin + 20) * 2, align: 'center' });
    footer(doc, qrPng, false);

    doc.addPage();
    header(doc, p);
    const across = p.clues.filter((c) => c.direction === 'across').sort((a, b) => a.number - b.number);
    const down = p.clues.filter((c) => c.direction === 'down').sort((a, b) => a.number - b.number);
    const colW = (PAGE.w - PAGE.margin * 2 - 30) / 2;
    clueColumn(doc, 'Across', across, PAGE.margin, colW, 130);
    clueColumn(doc, 'Down', down, PAGE.margin + colW + 30, colW, 130);
    footer(doc, qrPng, false);
  }

  // Answer keys, two per page.
  pack.forEach((p, i) => {
    const top = i % 2 === 0;
    if (top) doc.addPage();
    const y0 = top ? PAGE.margin : PAGE.h / 2 + 10;
    doc.font('Times-Bold').fontSize(13).fillColor(INK)
      .text(`Answer key — ${p.title}`, PAGE.margin, y0, { width: PAGE.w - PAGE.margin * 2, align: 'center' });
    const keySize = 250;
    drawGrid(doc, p, { x: (PAGE.w - keySize) / 2, y: y0 + 26, size: keySize, letters: true });
  });
  footer(doc, qrPng, true);

  doc.end();
  await new Promise((res, rej) => { out.on('finish', res); out.on('error', rej); });
}

fs.mkdirSync(OUT, { recursive: true });
const qrPng = await QRCode.toBuffer(QR_URL, { margin: 0, width: 160, color: { dark: '#1c1917' } });

let n = 0;
for (const slug of themeSlugs) {
  const p = ALIASES[slug] ? byId.get(ALIASES[slug]) : (bySlug.get(slug) ?? bySlug.get(slug.replace(/^the-/, '')));
  await render(slug, p, qrPng);
  n++;
}
await renderPack(qrPng);
console.log(`generate-printables: wrote ${n} PDFs + ${PACK_FILE} to public/printables/`);
