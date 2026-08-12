# SEO Strategy — Bible Crossword Challenge (web)

Date: 2026-08-12 · Domain age: ~7 weeks · Goal: organic search → app installs (web-to-app funnel via App Store buttons + `/go?s=` attribution)

## 1. Situation

- Site: Astro on Cloudflare Pages, apex domain. 79 playable theme pages (`/puzzles/[slug]`), `/challenge`, `/how-to-play`, `/go`, sitemap, llms.txt.
- Constraint (established earlier, do not re-audit): invisibility = domain age + **zero backlinks**, not markup. Technical SEO is fine.
- Theme pages already have unique prose, verse text, related links — good uniqueness; well under the 30-page location-page warning class (they're topical, not doorway).
- Business type: hybrid publisher / app-marketing. Publisher template applies for content + E-E-A-T; conversion KPI is installs, not pageviews.

## 2. Competitive landscape (top-ranking sites, Aug 2026)

| Competitor | Strength | Weakness we exploit |
|---|---|---|
| crosswalk.com/crossword | Huge DA, daily online puzzle | Generic daily puzzle, no themed depth, ad-heavy |
| biblepuzzles.com | Dedicated niche site, online + print | Dated UX, weak mobile experience |
| christianbiblereference.org | Weekly newspaper-style puzzle, trusted | One puzzle/week, no topical coverage |
| superstarworksheets.com | Owns "printable" intent (7 free PDFs) | Kids-only, tiny puzzle count |
| teachsundayschool.com | Per-book-of-Bible puzzles, teacher audience | Email-gated, print-only |

**Gap:** nobody pairs (a) modern playable web puzzles, (b) themed depth (79 topics), and (c) free printable PDFs per theme. Printable intent ("printable bible crossword", "sunday school crossword pdf") is large, teacher/homeschool-driven, and served by dated pages — it is also the natural **link magnet** this domain needs.

## 3. Keyword strategy

- **Head (later, needs authority):** bible crossword, bible crossword puzzles, free bible crossword puzzles online.
- **Long-tail (win now):** "[theme] crossword puzzle" — fruit of the spirit, david and goliath, books of the bible, easter/christmas bible crossword, etc. Maps 1:1 to existing 79 pages.
- **Printable modifiers:** "[theme] crossword printable / pdf / with answers" — currently unserved by us.
- **Audience terms:** sunday school crossword puzzles, youth group bible games, bible puzzles for adults/seniors.
- Seasonal: christmas + easter pages should be interlinked and refreshed ahead of season (Nov / Feb).

## 4. Architecture additions

Keep URL scheme; add hubs (each new theme page still needs its THEME_PAGE entry):

```
/puzzles/                       (exists — upgrade to categorized hub)
/puzzles/printable/             NEW: printable index (link magnet)
/puzzles/[slug]                 (exists — add "Print this puzzle" PDF + answers)
/topics/old-testament, /new-testament, /holidays, /kids   NEW: CollectionPage hubs
/for-sunday-school/             NEW: teacher landing page (audience hub)
```

- Internal linking: hub → themes → related themes (exists) → hub back-links; every page keeps App Store CTA.
- Schema: CollectionPage + ItemList on hubs; Article + Quiz/Game on theme pages; Organization + WebSite on home. No FAQPage for SERP benefit (retired May 2026); no HowTo.

## 5. Content plan

| Priority | Item | Why |
|---|---|---|
| P0 | Printable PDF per theme (auto-generate from puzzle JSON at build; new asset paths — assets are immutable, never overwrite) | Unlocks printable keyword class + outreach hook |
| P0 | 4 topic hubs + printable index | Crawl paths, head-term relevance |
| P1 | Sunday-school teacher page + "how to use crosswords in a lesson" guide | Audience terms, outreach landing target |
| P1 | 2 new theme pages/month toward 100 (seasonal first: Thanksgiving, Advent, Palm Sunday) | Long-tail growth |
| P2 | "Answers" sections/toggles on theme pages | Captures "with answers" modifier |
| P2 | About/author page with real byline | E-E-A-T floor for a puzzle publisher |

Cadence: light — this is a solo-dev side of an app business. ~2 pages + 1 outreach batch per month is sustainable.

## 6. Backlinks (the actual bottleneck)

1. **Directory/resource-list outreach:** Christian homeschool blogs, Sunday-school resource roundups, church ministry link pages — pitch the free printable pack. Target 5 pitches/week; expect ~10–15 links by month 3.
2. **Free printable pack** (zip of 10 best PDFs, no email gate) as the pitchable asset — undercuts teachsundayschool's gate.
3. **App cross-links:** App Store listing, social bios (`/go?s=` per channel), Product Hunt–style Christian app directories.
4. Skip: paid links, guest-post farms, mass directory spam.

## 7. Roadmap

- **Weeks 1–4 (Foundation):** GSC property verified + sitemap submitted; printable PDF generation; printable index; topic hubs; hub schema.
- **Weeks 5–12 (Expansion):** teacher page + lesson guide; answers toggles; seasonal pages for Q4; first 20 outreach pitches.
- **Weeks 13–24 (Scale):** sustained outreach; 90+ themes; Christmas content live by early Nov; monitor AI citations (llms.txt already in place).
- **Months 7–12 (Authority):** digital-PR angle (e.g. "most-searched Bible topics" data piece from app analytics); refresh top performers; head-term push.

## 8. KPIs

North star: **app installs from web**. Everything else below is a leading indicator for it — a tactic that grows clicks but not installs gets cut.

| Metric | Now | 3 mo | 6 mo | 12 mo |
|---|---|---|---|---|
| Referring domains | 0 | 10 | 25 | 60 |
| Indexed pages | ~85 | 100 | 115 | 130 |
| Organic clicks/mo (GSC) | ~0 | 300 | 1,500 | 6,000 |
| Long-tail themes in top 10 | 0 | 10 | 30 | 60 |
| Installs from web (`/go` + ASC web referrer) | ~0 | 30/mo | 150/mo | 500/mo |

Falsifiability: if by month 3 with 10+ referring domains the theme pages still get zero impressions in GSC, the age/backlink thesis is wrong — re-open technical/indexation investigation then (and only then).
Leading indicators (no re-audit needed): GSC impressions on 3 tracked theme queries weekly; referring-domain count monthly.

## 9. Risks

- Printable PDFs cannibalize app installs → mitigate: PDF footer carries app QR/link; treat printable users as a separate (teacher) audience feeding word-of-mouth.
- Seasonal pages built too late miss the window → Christmas content must be indexed by mid-Nov.
- Outreach time cost → cap at 1 hr/week; the asset does the selling.
