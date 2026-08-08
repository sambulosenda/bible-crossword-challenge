#!/usr/bin/env python3
"""Scripture-reference coverage across the puzzle library.

Two files carry references and they answer different questions:

  tools/puzzle_specs.json   what has been *authored* — the work queue
  Resources/puzzles.json    what actually *ships* — what a player can tap

They never match. The generator drops spec words it can't place in a grid, so
an authored reference on a dropped word is written but invisible. Coverage is
reported against both so that gap stays legible.

Ordering is by the daily rotation, not by id. `PuzzleProvider` cycles the pool
one puzzle per day from a 2026-07-01 epoch, so "which puzzles matter next" has
a literal answer: the next N days of the cycle. That is the batch order.

    python3 tools/audit_references.py [--days 30]
"""

import argparse
import datetime
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Bible Crossword Challenge" / "Resources"
SPECS = ROOT / "tools" / "puzzle_specs.json"

# Mirrors PuzzleProvider.init: day-index 0 maps to the first puzzle in a pool.
EPOCH = datetime.date(2026, 7, 1)


def load(path):
    with open(path) as f:
        return json.load(f)


def pools(puzzles):
    """The three pools PuzzleProvider splits the library into.

    Pack exclusives are held out of the daily rotation deliberately — keeping
    them there would shift every existing player's rotation index.
    """
    minis = [p for p in puzzles if p["id"].startswith("mini")]
    packs = [p for p in puzzles if p["id"].startswith("pack-")]
    dailies = [p for p in puzzles if p not in minis and p not in packs]
    return dailies, minis, packs


def coverage(puzzle):
    clues = puzzle["clues"]
    return sum(1 for c in clues if c.get("reference")), len(clues)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30,
                    help="how far ahead in the rotation to list (default 30)")
    ap.add_argument("--on", default=None, help="date to treat as today (YYYY-MM-DD)")
    args = ap.parse_args()

    today = (datetime.date.fromisoformat(args.on) if args.on
             else datetime.date.today())

    puzzles = load(RESOURCES / "puzzles.json")
    specs = load(SPECS)
    packs = load(RESOURCES / "packs.json")

    pack_of = {}
    for pack in packs:
        for pid in pack.get("puzzleIDs") or []:
            pack_of.setdefault(pid, pack["id"])

    dailies, minis, exclusives = pools(puzzles)

    print("SHIPPED (Resources/puzzles.json) — what a player can tap")
    total = referenced = 0
    for name, pool in (("daily", dailies), ("mini", minis),
                       ("pack-exclusive", exclusives)):
        r = sum(coverage(p)[0] for p in pool)
        n = sum(coverage(p)[1] for p in pool)
        total += n
        referenced += r
        print(f"  {name:<16} {r:>5}/{n:<5} ({r / n * 100:5.1f}%)  {len(pool)} puzzles")
    print(f"  {'TOTAL':<16} {referenced:>5}/{total:<5} "
          f"({referenced / total * 100:5.1f}%)  {total - referenced} clues remaining")

    print("\nAUTHORED (tools/puzzle_specs.json) — the work queue")
    words = [(s["id"], w) for s in specs for w in s["words"]]
    authored = sum(1 for _, w in words if w.get("reference"))
    print(f"  {authored}/{len(words)} spec words "
          f"({len(words) - authored} to write)")
    print(f"  {authored - referenced} authored reference(s) sit on words the "
          f"generator could not place, so they never ship")

    partial = [(p["id"], *coverage(p)) for p in puzzles
               if 0 < coverage(p)[0] < coverage(p)[1]]
    if partial:
        print("\nPARTIAL — a referenced puzzle with holes reads as inconsistent")
        for pid, r, n in partial:
            missing = [c["answer"] for c in next(
                p for p in puzzles if p["id"] == pid)["clues"]
                if not c.get("reference")]
            print(f"  {pid:<16} {r}/{n}  missing: {', '.join(missing)}")

    print(f"\nROTATION — next {args.days} days from {today}")
    day_index = (today - EPOCH).days
    for offset in range(args.days):
        date = today + datetime.timedelta(days=offset)
        daily = dailies[(day_index + offset) % len(dailies)]
        mini = minis[(day_index + offset) % len(minis)]
        dr, dn = coverage(daily)
        mr, mn = coverage(mini)
        flag = " " if dr == dn and mr == mn else "·"
        print(f" {flag}{date}  {daily['id']:<10} {dr:>2}/{dn:<2} "
              f"{daily['title'][:28]:<30} mini {mini['id']:<9} {mr}/{mn}")

    print("\nPACKS")
    for pack in packs:
        ids = pack.get("puzzleIDs") or []
        rows = [coverage(p) for p in puzzles if p["id"] in ids]
        r = sum(x[0] for x in rows)
        n = sum(x[1] for x in rows)
        gate = "premium" if pack.get("isPremium") else "free"
        pct = f"{r / n * 100:5.1f}%" if n else "    —"
        print(f"  {pack['id']:<18} {gate:<8} {r:>3}/{n:<4} ({pct})")


if __name__ == "__main__":
    main()
