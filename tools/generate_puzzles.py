#!/usr/bin/env python3
"""Build the bundled puzzles.json from authored content specs.

Input  (argv[1]): specs.json — array of {title, difficulty, verse, reference, words:[{answer,clue}]}
Output (argv[2]): puzzles.json — array of Puzzle objects the Swift app decodes.

Grids are generated with the verified no-accidental-words constraint, then
padded+centered to the nearest PRD size (10/12/15) so all shipped puzzles use a
PRD-valid grid size.

Specs with "kind": "mini" build 7x7 quick puzzles (words 3-7 letters, 5+
placed) with ids "mini-NNN" and their own publishDate sequence. Daily specs
are processed exactly as before, so growing the mini bank never perturbs the
daily output.

A word may carry a "reference" ("Genesis 1:3") naming the passage its answer
comes from. It is copied onto that clue and shown in-app only after the clue is
solved. Every one is validated against the bundled bsb.json before any puzzle is
built, and the key is omitted rather than nulled when a word has none.

Specs with "pack": "<slug>" build full-size puzzles that live only inside that
themed pack: ids "pack-<slug>-NNN", numbered per slug. The app excludes any
"pack-" prefixed id from the daily rotation and Archive pool, so pack content
never perturbs the daily index. Pack specs are processed after dailies and
minis, keeping both of those outputs byte-identical as packs grow.
"""
import json, os, random, re, sys

ALLOWED_SIZES = [10, 12, 15]
CANVAS = 15

MINI_SIZES = [7]
MINI_CANVAS = 7

# --- Scripture references -----------------------------------------------
#
# A clue may name the passage its answer comes from. The app shows it only
# after the clue is solved, and opens it in the bundled reader — so a citation
# that doesn't resolve there is worse than none at all. Every reference is
# checked against bsb.json itself: right book spelling, chapter and verse that
# actually exist.

BSB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "Bible Crossword Challenge", "Resources", "bsb.json")

_bible = None

def bible():
    """{book name: {chapter number: verse count}}, loaded once."""
    global _bible
    if _bible is None:
        with open(BSB) as f:
            data = json.load(f)
        _bible = {b["name"]: {c["number"]: len(c["verses"]) for c in b["chapters"]}
                  for b in data["books"]}
    return _bible

def parse_ref(raw):
    """Mirrors ScriptureRef.init? in Swift: 'Book C', 'Book C:V', 'Book C:V-W'.
    The book is everything before the last space, so '1 Samuel 9:1' and 'Song of
    Solomon 2:1' parse. Returns (book, chapter, verse|None) or None."""
    s = (raw or "").strip()
    if " " not in s: return None
    book, cv = s.rsplit(" ", 1)
    book = book.strip()
    parts = cv.split(":", 1)
    if not book or not parts[0].isdigit(): return None
    chapter = int(parts[0])
    verse = None
    if len(parts) > 1:
        start = re.split(r"[-–]", parts[1])[0]
        if not start.isdigit(): return None
        verse = int(start)
    return book, chapter, verse

def ref_error(raw):
    """None if the reference opens in the reader, else why it doesn't."""
    parsed = parse_ref(raw)
    if not parsed: return f"unparseable reference {raw!r}"
    book, chapter, verse = parsed
    chapters = bible().get(book)
    if chapters is None:
        return f"no book named {book!r} in bsb.json (references use 'Psalm', not 'Psalms')"
    if chapter not in chapters:
        return f"{book} has no chapter {chapter}"
    if verse is not None and not (1 <= verse <= chapters[chapter]):
        return f"{book} {chapter} has {chapters[chapter]} verses, not {verse}"
    return None

def theme_books(theme):
    """Book names a spec's theme commits to, e.g. 'The Creation (Genesis 1-2)'
    -> {'Genesis'}. Empty for themes like 'Prayer', which range freely."""
    return {name for name in bible() if name in (theme or "")}

def check_references(specs):
    """Hard errors for citations the reader can't open, warnings for ones that
    wander outside a spec's own theme. Returns (errors, warnings)."""
    errors, warnings = [], []
    for spec in specs:
        where = spec.get("id") or spec.get("title")
        books = theme_books(spec.get("theme"))
        for w in spec.get("words", []):
            raw = (w.get("reference") or "").strip()
            if not raw: continue  # absent is valid — never guess one to fill the field
            err = ref_error(raw)
            if err:
                errors.append(f"{where} / {w.get('answer')}: {err}")
                continue
            book = parse_ref(raw)[0]
            if books and book not in books:
                warnings.append(f"{where} / {w.get('answer')}: {raw} is outside the theme ({', '.join(sorted(books))})")
    return errors, warnings

class Grid:
    def __init__(self, n):
        self.n = n
        self.cells = {}
    def get(self, r, c): return self.cells.get((r, c))
    def in_bounds(self, r, c): return 0 <= r < self.n and 0 <= c < self.n

def can_place(g, word, r, c, d):
    dr, dc = (0, 1) if d == 'A' else (1, 0)
    br, bc = r - dr, c - dc
    er, ec = r + dr * len(word), c + dc * len(word)
    if g.in_bounds(br, bc) and g.get(br, bc) is not None: return False, 0
    if g.in_bounds(er, ec) and g.get(er, ec) is not None: return False, 0
    crossings = 0
    for i, ch in enumerate(word):
        rr, cc = r + dr * i, c + dc * i
        if not g.in_bounds(rr, cc): return False, 0
        existing = g.get(rr, cc)
        if existing is not None:
            if existing != ch: return False, 0
            crossings += 1
        else:
            if d == 'A':
                for nr in (rr - 1, rr + 1):
                    if g.in_bounds(nr, cc) and g.get(nr, cc) is not None: return False, 0
            else:
                for nc in (cc - 1, cc + 1):
                    if g.in_bounds(rr, nc) and g.get(rr, nc) is not None: return False, 0
    return True, crossings

def place(g, word, r, c, d):
    dr, dc = (0, 1) if d == 'A' else (1, 0)
    for i, ch in enumerate(word):
        g.cells[(r + dr * i, c + dc * i)] = ch

def generate(words, n, seed):
    rng = random.Random(seed)
    g = Grid(n)
    order = sorted(words, key=len, reverse=True)
    first = order[0]
    place(g, first, n // 2, max(0, (n - len(first)) // 2), 'A')
    placed = [(first, n // 2, max(0, (n - len(first)) // 2), 'A')]
    remaining = order[1:]
    rng.shuffle(remaining)
    progress = True
    while remaining and progress:
        progress = False
        for word in list(remaining):
            best = None
            for (pw, pr, pc, pd) in placed:
                dr, dc = (0, 1) if pd == 'A' else (1, 0)
                for i in range(len(pw)):
                    rr, cc = pr + dr * i, pc + dc * i
                    ch = pw[i]
                    for j, wch in enumerate(word):
                        if wch != ch: continue
                        nd = 'D' if pd == 'A' else 'A'
                        ndr, ndc = (0, 1) if nd == 'A' else (1, 0)
                        sr, sc = rr - ndr * j, cc - ndc * j
                        ok, cross = can_place(g, word, sr, sc, nd)
                        if ok and cross >= 1:
                            if best is None or cross > best[0]:
                                best = (cross, sr, sc, nd)
            if best:
                _, sr, sc, nd = best
                place(g, word, sr, sc, nd)
                placed.append((word, sr, sc, nd))
                remaining.remove(word)
                progress = True
    return g, placed

def tight(g):
    rs = [r for (r, c) in g.cells]; cs = [c for (r, c) in g.cells]
    minr, maxr, minc, maxc = min(rs), max(rs), min(cs), max(cs)
    h, w = maxr - minr + 1, maxc - minc + 1
    grid = [['.'] * w for _ in range(h)]
    for (r, c), ch in g.cells.items():
        grid[r - minr][c - minc] = ch
    return grid

def pad_center(grid, allowed_sizes=ALLOWED_SIZES):
    h, w = len(grid), len(grid[0])
    need = max(h, w)
    target = next((s for s in allowed_sizes if s >= need), need)
    out = [['.'] * target for _ in range(target)]
    roff, coff = (target - h) // 2, (target - w) // 2
    for r in range(h):
        for c in range(w):
            out[r + roff][c + coff] = grid[r][c]
    return out, target

def number_and_slots(grid, size):
    num = 0
    slots = []
    for r in range(size):
        for c in range(size):
            if grid[r][c] == '.': continue
            sa = (c == 0 or grid[r][c-1] == '.') and (c + 1 < size and grid[r][c+1] != '.')
            sd = (r == 0 or grid[r-1][c] == '.') and (r + 1 < size and grid[r+1][c] != '.')
            if sa or sd: num += 1
            if sa:
                w = ''; cc = c
                while cc < size and grid[r][cc] != '.': w += grid[r][cc]; cc += 1
                slots.append((num, 'across', r, c, w))
            if sd:
                w = ''; rr = r
                while rr < size and grid[rr][c] != '.': w += grid[rr][c]; rr += 1
                slots.append((num, 'down', r, c, w))
    return slots

def accidents(grid, size, intended):
    runs = []
    for r in range(size):
        run = ''
        for c in range(size):
            if grid[r][c] != '.': run += grid[r][c]
            else:
                if len(run) >= 2: runs.append(run)
                run = ''
        if len(run) >= 2: runs.append(run)
    for c in range(size):
        run = ''
        for r in range(size):
            if grid[r][c] != '.': run += grid[r][c]
            else:
                if len(run) >= 2: runs.append(run)
                run = ''
        if len(run) >= 2: runs.append(run)
    return [w for w in runs if w not in intended]

def clean_words(words, max_len=9):
    seen = set(); out = []
    for w in words:
        ans = re.sub(r'[^A-Z]', '', (w.get('answer') or '').upper())
        clue = (w.get('clue') or '').strip()
        ref = (w.get('reference') or '').strip() or None
        if len(ans) < 3 or len(ans) > max_len or not clue: continue
        if ans in seen: continue
        seen.add(ans)
        out.append((ans, clue, ref))
    return out

def build(spec, min_words=10, max_words=20, canvas=CANVAS, allowed_sizes=ALLOWED_SIZES, max_word_len=9):
    entries = clean_words(spec.get('words', []), max_len=max_word_len)
    clue_map = {a: c for (a, c, r) in entries}
    ref_map = {a: r for (a, c, r) in entries if r}
    words = [a for (a, c, r) in entries]
    if len(words) < min_words:
        return None, f"only {len(words)} clean words"
    best = None
    for seed in range(2500):
        g, placed = generate(words, canvas, seed)
        pw = [p[0] for p in placed]
        if not (min_words <= len(pw) <= max_words): continue
        grid, size = pad_center(tight(g), allowed_sizes)
        if size > max(allowed_sizes): continue
        if accidents(grid, size, set(words)): continue
        slots = number_and_slots(grid, size)
        if len(slots) != len(pw): continue
        if any(s[4] not in clue_map for s in slots): continue
        if best is None or len(pw) > best[0]:
            best = (len(pw), grid, size, slots)
        if len(pw) == len(words): break
    if not best:
        return None, "no valid layout found"
    _, grid, size, slots = best
    clues = []
    for (number, direction, r, c, answer) in sorted(slots, key=lambda s: (s[0], 0 if s[1] == 'across' else 1)):
        clue = {
            "number": number, "direction": direction,
            "row": r, "col": c, "text": clue_map[answer], "answer": answer,
        }
        # Omitted rather than null when a clue isn't drawn from one passage —
        # the Swift side decodes the absent key as nil, and the puzzles.json
        # diff stays limited to clues that gained a citation.
        if answer in ref_map:
            clue["reference"] = ref_map[answer]
        clues.append(clue)
    return {
        "title": spec["title"],
        "difficulty": spec["difficulty"],
        "verse": spec["verse"].strip().strip('"').strip('"').strip('"'),
        "reference": spec["reference"].strip(),
        "size": size,
        "grid": ["".join(row) for row in grid],
        "clues": clues,
    }, None

def id_num(pid, prefix="daily"):
    m = re.match(rf"{prefix}-(\d+)$", pid or "")
    return int(m.group(1)) if m else 0

def load_shipped_order(path):
    """`id` -> position in the puzzles.json that is already shipping.

    The rotation is positional, so the file that shipped is the record of what
    every existing player is being served on any given day. Regenerating must
    reproduce it exactly and append to it, never reorder it. Missing or
    unreadable (a first build) means there is nothing to preserve yet."""
    try:
        with open(path) as f:
            return {p["id"]: i for i, p in enumerate(json.load(f))}
    except (OSError, ValueError, KeyError, TypeError):
        return {}


def process(specs, out, fails, prefix, build_kwargs, shipped_order, extra_fields=None):
    """Builds one kind of puzzle. IDs are content-stable: a spec's explicit
    "id" is the permanent link to a user's saved PuzzleRecord, so it must NOT
    change when the bank grows. Specs without an id (newly authored) get the
    next free {prefix}-NNN above the current maximum, never renumbering
    existing puzzles."""
    import datetime
    # Deterministic order, and — more importantly — an *append-only* one.
    #
    # The daily is served by position, not by id: `index = daysSinceEpoch %
    # pool.count` indexes this array. Sorting every spec by (difficulty, title)
    # was stable only while the bank never grew: one new easy puzzle whose title
    # sorts early landed at index 0 and shifted the whole pool down, changing
    # which puzzle every existing player is served on every future day, and
    # decoupling the rotation from what they had already played.
    #
    # Anything already shipped keeps the position it already ships in; anything
    # new is appended after it, ordered by difficulty then title.
    #
    # The daily is served by position, not by id — `index = daysSinceEpoch %
    # pool.count` indexes this array — so the order here *is* the rotation.
    # Sorting every spec by (difficulty, title) was stable only while the bank
    # never grew: one new easy puzzle with an early title landed at index 0 and
    # shifted the whole pool down, changing which puzzle every existing player
    # is served on every future day and decoupling the rotation from what they
    # had already played.
    #
    # `shipped_order` comes from the previous puzzles.json rather than from the
    # ids, because the two disagree: the dailies happen to sit in id order, the
    # minis do not (mini-031 ships first). Reading the real order is the only
    # rule that holds for both, and it keeps holding after the ids are written
    # back into the specs, which is when a "does it have an id yet" test would
    # quietly stop working.
    order = {"easy": 0, "medium": 1, "hard": 2}
    specs.sort(key=lambda s: (
        (0, shipped_order[s["id"]], "")
        if s.get("id") in shipped_order
        else (1, order.get(s.get("difficulty"), 1), s.get("title", ""))
    ))

    reserved = {s["id"] for s in specs if s.get("id")}
    next_free = max((id_num(i, prefix) for i in reserved), default=0) + 1

    idx = 0
    for spec in specs:
        puzzle, err = build(spec, **build_kwargs)
        if err:
            fails.append((spec.get("title"), err))
            continue
        idx += 1
        pid = spec.get("id")
        if not pid:
            while f"{prefix}-{next_free:03d}" in reserved:
                next_free += 1
            pid = f"{prefix}-{next_free:03d}"
            reserved.add(pid)
            next_free += 1
        puzzle["id"] = pid
        # publishDate sequential from 2026-07-01 by output position (cosmetic).
        d = datetime.date(2026, 7, 1) + datetime.timedelta(days=idx - 1)
        puzzle["publishDate"] = d.isoformat()
        # reorder keys for readability
        entry = {
            "id": puzzle["id"], "title": puzzle["title"], "difficulty": puzzle["difficulty"],
            "verse": puzzle["verse"], "reference": puzzle["reference"],
            "publishDate": puzzle["publishDate"], "size": puzzle["size"],
            "grid": puzzle["grid"], "clues": puzzle["clues"],
        }
        if extra_fields:
            entry.update(extra_fields)
        out.append(entry)

def main():
    specs = json.load(open(sys.argv[1]))

    # Checked before anything is built: a wrong citation in a Bible app is a
    # credibility problem, not a typo, so nothing ships until they all resolve.
    errors, warnings = check_references(specs)
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    if errors:
        print(f"{len(errors)} bad scripture reference(s):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    out = []
    fails = []
    # Dailies are processed first with unchanged parameters so their output is
    # byte-identical however many minis and pack puzzles are added after them.
    dailies = [s for s in specs if s.get("kind") != "mini" and not s.get("pack")]
    minis = [s for s in specs if s.get("kind") == "mini"]
    packed = [s for s in specs if s.get("pack") and s.get("kind") != "mini"]
    # Read before writing: the file about to be overwritten is the record of the
    # order every existing player's rotation follows.
    shipped_order = load_shipped_order(sys.argv[2])
    process(dailies, out, fails, "daily", {}, shipped_order)
    process(minis, out, fails, "mini", {
        "min_words": 5, "max_words": 10,
        "canvas": MINI_CANVAS, "allowed_sizes": MINI_SIZES, "max_word_len": 7,
    }, shipped_order, extra_fields={"kind": "mini"})
    # Pack-exclusive puzzles: full-size build, ids numbered per pack slug so
    # each pack grows independently. Slugs sorted for deterministic output.
    by_slug = {}
    for s in packed:
        by_slug.setdefault(s["pack"], []).append(s)
    for slug in sorted(by_slug):
        process(by_slug[slug], out, fails, f"pack-{slug}", {}, shipped_order)
    json.dump(out, open(sys.argv[2], "w"), indent=2)
    sizes = {}
    diffs = {}
    for p in out:
        sizes[p["size"]] = sizes.get(p["size"], 0) + 1
        diffs[p["difficulty"]] = diffs.get(p["difficulty"], 0) + 1
    print(f"Built {len(out)} puzzles ({len(minis) and sum(1 for p in out if p.get('kind') == 'mini')} minis). Sizes: {sizes}. Difficulty: {diffs}", file=sys.stderr)
    print(f"Clue counts: min={min(len(p['clues']) for p in out)}, max={max(len(p['clues']) for p in out)}", file=sys.stderr)
    if fails:
        print(f"Dropped {len(fails)}:", file=sys.stderr)
        for t, e in fails: print(f"  - {t}: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
