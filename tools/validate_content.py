#!/usr/bin/env python3
"""Check the shipped content is internally consistent before it goes out.

The generator already refuses to build a bad grid or a bad scripture reference.
What it cannot see is the *other* half of the content: `packs.json` is
hand-authored, references puzzles by id, and is decoded by an app that silently
drops what it can't resolve. A pack pointing at a puzzle that isn't there, a
seasonal window with a typo in it, or a pack-exclusive puzzle that leaked into
the daily rotation all ship quietly and are found by a player, not a build.

Usage:
    python3 tools/validate_content.py

Exits non-zero on any error. Warnings are printed and do not fail.
"""

import json
import os
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUZZLES = os.path.join(ROOT, "Bible Crossword Challenge/Resources/puzzles.json")
PACKS = os.path.join(ROOT, "Bible Crossword Challenge/Resources/packs.json")
SPECS = os.path.join(ROOT, "tools/puzzle_specs.json")

# Kept in step with `PackSeason` in Models/PuzzlePack.swift. A kind the app
# doesn't know throws at decode and takes every pack down with it, so an unknown
# one here is an error rather than a warning.
SEASON_KINDS = {"dates", "annual", "easter"}

# Two puzzles in one pack sharing this many answers reads as padding rather than
# a collection — a warning, since a themed pack legitimately repeats key names.
OVERLAP_WARN = 6

errors = []
warnings = []


def error(message):
    errors.append(message)


def warn(message):
    warnings.append(message)


# --- Puzzle pool -------------------------------------------------------------

def check_puzzles(puzzles):
    """Ids are the only link to a player's saved progress — they have to be
    unique, and their prefix decides which pool a puzzle lands in."""
    counts = Counter(p["id"] for p in puzzles)
    for pid, n in counts.items():
        if n > 1:
            error(f"puzzles.json: duplicate id {pid} ({n} copies)")

    for p in puzzles:
        pid = p["id"]
        if not pid.startswith(("daily-", "mini-", "pack-", "sunday-")):
            error(f"puzzles.json: {pid} has no recognised prefix "
                  "(daily- / mini- / pack- / sunday-)")
        # `kind: mini` and a `mini-` id have to agree: the app splits the pools
        # on the prefix but renders on the kind.
        if pid.startswith("mini-") and p.get("kind") != "mini":
            error(f"puzzles.json: {pid} is in the mini pool but isn't kind=mini")
        if p.get("kind") == "mini" and not pid.startswith("mini-"):
            error(f"puzzles.json: {pid} is kind=mini but isn't a mini- id")
        # Same agreement for the weekly pool: `kind: sunday` and a `sunday-` id.
        if pid.startswith("sunday-") and p.get("kind") != "sunday":
            error(f"puzzles.json: {pid} is in the sunday pool but isn't kind=sunday")
        if p.get("kind") == "sunday" and not pid.startswith("sunday-"):
            error(f"puzzles.json: {pid} is kind=sunday but isn't a sunday- id")


def check_grids(puzzles):
    """Every clue's answer must be the letters actually in the solution grid.

    The generator enforces this when it builds, but nothing re-checks what
    shipped, and the app's tests run against a synthetic puzzle rather than the
    bundle. A grid that disagrees with its clue is unsolvable — the player types
    the right word and the app tells them they're wrong."""
    for p in puzzles:
        pid, size, grid = p["id"], p["size"], p["grid"]
        if len(grid) != size or any(len(row) != size for row in grid):
            error(f"{pid}: grid is not {size}x{size}")
            continue
        for clue in p["clues"]:
            row, col, answer = clue["row"], clue["col"], clue["answer"]
            dr, dc = (1, 0) if clue["direction"] == "down" else (0, 1)
            if not (0 <= row < size and 0 <= col < size):
                error(f"{pid}/{answer}: starts outside the grid")
                continue
            end_r, end_c = row + dr * (len(answer) - 1), col + dc * (len(answer) - 1)
            if not (0 <= end_r < size and 0 <= end_c < size):
                error(f"{pid}/{answer}: runs off the edge of the grid")
                continue
            actual = "".join(
                grid[row + dr * i][col + dc * i] for i in range(len(answer))
            )
            if actual != answer:
                error(f"{pid}/{answer}: grid reads {actual!r} at "
                      f"({row},{col}) {clue['direction']}")
        # A filled cell no clue covers can never be typed into.
        covered = set()
        for clue in p["clues"]:
            dr, dc = (1, 0) if clue["direction"] == "down" else (0, 1)
            for i in range(len(clue["answer"])):
                covered.add((clue["row"] + dr * i, clue["col"] + dc * i))
        for r, rowtext in enumerate(grid):
            for c, ch in enumerate(rowtext):
                if ch != "." and (r, c) not in covered:
                    error(f"{pid}: letter {ch!r} at ({r},{c}) belongs to no clue")


def check_pool_isolation(puzzles, packs):
    """Pack-exclusive puzzles must not reach the daily or mini rotation.

    The rotation index is `daysSinceEpoch % pool.count`, so a single extra
    puzzle in either pool shifts what every existing player is served — see
    `PuzzleProvider`. The app enforces this by prefix; this checks the content
    can't put it in the position of having to."""
    owned = {pid for pack in packs for pid in pack["puzzleIDs"]}
    for p in puzzles:
        pid = p["id"]
        if not pid.startswith("pack-"):
            continue
        if pid not in owned:
            error(f"puzzles.json: {pid} is pack-exclusive but no pack lists it — "
                  "it is unreachable in the app")
        # pack-<slug>-NNN must sit in the pack called <slug>.
        slugs = [pack["id"] for pack in packs if pid in pack["puzzleIDs"]]
        if slugs and not any(pid.startswith(f"pack-{slug}-") for slug in slugs):
            error(f"puzzles.json: {pid} is listed by {slugs} but its id names a "
                  "different pack")


# --- Packs -------------------------------------------------------------------

def check_packs(packs, puzzles):
    by_id = {p["id"]: p for p in puzzles}

    slugs = Counter(pack["id"] for pack in packs)
    for slug, n in slugs.items():
        if n > 1:
            error(f"packs.json: duplicate pack id {slug}")

    free = [pack["id"] for pack in packs if not pack.get("isPremium", True)]
    if len(free) != 1:
        error(f"packs.json: expected exactly one free pack, found {free or 'none'} "
              "(PacksTests asserts this)")

    for pack in packs:
        slug = pack["id"]
        ids = pack.get("puzzleIDs") or []
        if not ids:
            error(f"packs.json: {slug} is empty")
        for pid in ids:
            if pid not in by_id:
                error(f"packs.json: {slug} references missing puzzle {pid}")
        dupes = [pid for pid, n in Counter(ids).items() if n > 1]
        if dupes:
            error(f"packs.json: {slug} lists {dupes} more than once")
        for field in ("title", "blurb", "coverSymbol"):
            if not pack.get(field):
                error(f"packs.json: {slug} is missing {field}")
        check_season(slug, pack.get("season"))


def check_season(slug, season):
    """A season that doesn't parse resolves to no window at all, which presents
    as a pack that simply never appears — the failure mode with no symptom."""
    if season is None:
        return
    kind = season.get("kind")
    if kind not in SEASON_KINDS:
        error(f"packs.json: {slug} has unknown season kind {kind!r} "
              f"(expected one of {sorted(SEASON_KINDS)})")
        return

    if kind == "easter":
        start, end = season.get("from"), season.get("to")
        if not isinstance(start, int) or not isinstance(end, int):
            error(f"packs.json: {slug} easter offsets must be whole numbers")
        elif start > end:
            error(f"packs.json: {slug} easter window runs backwards ({start} > {end})")
        elif start < -90 or end > 90:
            warn(f"packs.json: {slug} easter window is over three months from "
                 "the feast — is that deliberate?")
        return

    parts = 3 if kind == "dates" else 2
    for bound in ("from", "to"):
        value = season.get(bound)
        if not isinstance(value, str) or len(value.split("-")) != parts:
            error(f"packs.json: {slug} season {bound}={value!r} is not a "
                  f"{parts}-part date for kind {kind}")
            continue
        numbers = [int(n) for n in value.split("-") if n.lstrip("-").isdigit()]
        if len(numbers) != parts:
            error(f"packs.json: {slug} season {bound}={value!r} is not numeric")
            continue
        month, day = numbers[-2], numbers[-1]
        if not 1 <= month <= 12 or not 1 <= day <= 31:
            error(f"packs.json: {slug} season {bound}={value!r} is not a real date")

    # An annual window that wraps is legal (12-26 → 01-06); a `dates` one is not.
    if kind == "dates" and season.get("from", "") > season.get("to", ""):
        error(f"packs.json: {slug} one-off window runs backwards")


def check_overlap(packs, puzzles):
    """Answer overlap inside a pack — a soft signal that two puzzles are the
    same puzzle wearing a different title."""
    by_id = {p["id"]: p for p in puzzles}
    for pack in packs:
        answers = {}
        for pid in pack["puzzleIDs"]:
            puzzle = by_id.get(pid)
            if not puzzle:
                continue
            answers[pid] = {c["answer"] for c in puzzle["clues"]}
        seen = list(answers.items())
        for i, (a_id, a) in enumerate(seen):
            for b_id, b in seen[i + 1:]:
                shared = a & b
                if len(shared) >= OVERLAP_WARN:
                    warn(f"{pack['id']}: {a_id} and {b_id} share {len(shared)} "
                         f"answers ({', '.join(sorted(shared)[:5])}…)")


# --- Specs -------------------------------------------------------------------

def check_specs(specs, puzzles):
    """Every shipped id must be written back into its spec.

    The generator only auto-assigns ids to specs that lack one. A shipped
    puzzle whose spec has no id gets renumbered the next time the bank is
    reordered, which silently reassigns players' completions — see
    tools/README.md."""
    spec_ids = {s["id"] for s in specs if s.get("id")}
    missing = [p["id"] for p in puzzles if p["id"] not in spec_ids]
    if missing:
        error(f"{len(missing)} shipped puzzle(s) have no id in puzzle_specs.json — "
              f"they will be renumbered: {', '.join(sorted(missing)[:8])}"
              f"{'…' if len(missing) > 8 else ''}")

    dupes = [i for i, n in Counter(
        s["id"] for s in specs if s.get("id")).items() if n > 1]
    if dupes:
        error(f"puzzle_specs.json: duplicate ids {dupes}")

    # A spec tagged for a pack whose slug has no entry in packs.json builds
    # puzzles nothing can reach.
    by_slug = defaultdict(int)
    for s in specs:
        if s.get("pack"):
            by_slug[s["pack"]] += 1
    return by_slug


def check_spec_packs(spec_slugs, packs):
    known = {pack["id"] for pack in packs}
    for slug, count in sorted(spec_slugs.items()):
        if slug not in known:
            error(f"puzzle_specs.json: {count} spec(s) tagged pack={slug!r}, "
                  "which has no entry in packs.json")


# --- Entry point -------------------------------------------------------------

def main():
    puzzles = json.load(open(PUZZLES))
    packs = json.load(open(PACKS))
    specs = json.load(open(SPECS))

    check_puzzles(puzzles)
    check_grids(puzzles)
    check_packs(packs, puzzles)
    check_pool_isolation(puzzles, packs)
    check_overlap(packs, puzzles)
    spec_slugs = check_specs(specs, puzzles)
    check_spec_packs(spec_slugs, packs)

    dailies = sum(1 for p in puzzles if p["id"].startswith("daily-"))
    minis = sum(1 for p in puzzles if p["id"].startswith("mini-"))
    exclusive = sum(1 for p in puzzles if p["id"].startswith("pack-"))
    sundays = sum(1 for p in puzzles if p["id"].startswith("sunday-"))
    print(f"{len(puzzles)} puzzles: {dailies} daily, {minis} mini, "
          f"{sundays} sunday, {exclusive} pack-exclusive. {len(packs)} packs.")
    print(f"Rotation: dailies wrap every {dailies} days, minis every {minis}, "
          f"sundays every {sundays} weeks.")

    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    if errors:
        print(f"\n{len(errors)} error(s):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
