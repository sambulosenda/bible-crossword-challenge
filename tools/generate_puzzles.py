#!/usr/bin/env python3
"""Build the bundled puzzles.json from authored content specs.

Input  (argv[1]): specs.json — array of {title, difficulty, verse, reference, words:[{answer,clue}]}
Output (argv[2]): puzzles.json — array of Puzzle objects the Swift app decodes.

Grids are generated with the verified no-accidental-words constraint, then
padded+centered to the nearest PRD size (10/12/15) so all shipped puzzles use a
PRD-valid grid size.
"""
import json, random, re, sys

ALLOWED_SIZES = [10, 12, 15]
CANVAS = 15

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

def pad_center(grid):
    h, w = len(grid), len(grid[0])
    need = max(h, w)
    target = next((s for s in ALLOWED_SIZES if s >= need), need)
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

def clean_words(words):
    seen = set(); out = []
    for w in words:
        ans = re.sub(r'[^A-Z]', '', (w.get('answer') or '').upper())
        clue = (w.get('clue') or '').strip()
        if len(ans) < 3 or len(ans) > 9 or not clue: continue
        if ans in seen: continue
        seen.add(ans)
        out.append((ans, clue))
    return out

def build(spec, min_words=10):
    entries = clean_words(spec.get('words', []))
    clue_map = {a: c for (a, c) in entries}
    words = [a for (a, c) in entries]
    if len(words) < min_words:
        return None, f"only {len(words)} clean words"
    best = None
    for seed in range(2500):
        g, placed = generate(words, CANVAS, seed)
        pw = [p[0] for p in placed]
        if not (min_words <= len(pw) <= 20): continue
        grid, size = pad_center(tight(g))
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
        clues.append({
            "number": number, "direction": direction,
            "row": r, "col": c, "text": clue_map[answer], "answer": answer,
        })
    return {
        "title": spec["title"],
        "difficulty": spec["difficulty"],
        "verse": spec["verse"].strip().strip('"').strip('"').strip('"'),
        "reference": spec["reference"].strip(),
        "size": size,
        "grid": ["".join(row) for row in grid],
        "clues": clues,
    }, None

def main():
    specs = json.load(open(sys.argv[1]))
    out = []
    fails = []
    idx = 0
    # deterministic order by difficulty then title for stable daily rotation
    order = {"easy": 0, "medium": 1, "hard": 2}
    specs.sort(key=lambda s: (order.get(s.get("difficulty"), 1), s.get("title", "")))
    for spec in specs:
        puzzle, err = build(spec)
        if err:
            fails.append((spec.get("title"), err))
            continue
        idx += 1
        puzzle["id"] = f"daily-{idx:03d}"
        # publishDate sequential from 2026-07-01
        import datetime
        d = datetime.date(2026, 7, 1) + datetime.timedelta(days=idx - 1)
        puzzle["publishDate"] = d.isoformat()
        # reorder keys for readability
        out.append({
            "id": puzzle["id"], "title": puzzle["title"], "difficulty": puzzle["difficulty"],
            "verse": puzzle["verse"], "reference": puzzle["reference"],
            "publishDate": puzzle["publishDate"], "size": puzzle["size"],
            "grid": puzzle["grid"], "clues": puzzle["clues"],
        })
    json.dump(out, open(sys.argv[2], "w"), indent=2)
    sizes = {}
    diffs = {}
    for p in out:
        sizes[p["size"]] = sizes.get(p["size"], 0) + 1
        diffs[p["difficulty"]] = diffs.get(p["difficulty"], 0) + 1
    print(f"Built {len(out)} puzzles. Sizes: {sizes}. Difficulty: {diffs}", file=sys.stderr)
    print(f"Clue counts: min={min(len(p['clues']) for p in out)}, max={max(len(p['clues']) for p in out)}", file=sys.stderr)
    if fails:
        print(f"Dropped {len(fails)}:", file=sys.stderr)
        for t, e in fails: print(f"  - {t}: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
