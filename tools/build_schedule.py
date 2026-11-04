#!/usr/bin/env python3
"""Build the dated puzzle schedule: which puzzle each calendar day serves.

Why a schedule: the app used to serve `days_since_epoch % pool.count`, so the
pools wrapped (dailies ~2026-10-01, minis ~2026-10-06) and adding a puzzle
shifted every date to a different puzzle. A schedule pins each date to an id,
so content can grow without moving history.

Rules:
- Dates already in the schedule up to today + LOCK_DAYS never change. A phone
  holding an older feed must still agree with everyone else on those days
  (challenges, leaderboards, "solved today").
- A date with no entry yet, up to today, is filled with the legacy modulo
  formula the shipped builds used, so history matches what players saw.
- Future dates past the lock are (re)planned: never-scheduled puzzles first,
  in pool order, then the least recently served.

Pools mirror PuzzleProvider: file order of puzzles.json; dailies = no kind and
not a `pack-` id; minis = kind "mini"; Sundays = kind "sunday", keyed by the
date of their week's Sunday.

Usage:
  python3 tools/build_schedule.py              # write Resources/schedule.json
  python3 tools/build_schedule.py --check      # exit 1 if a write would change it
  python3 tools/build_schedule.py --today 2026-11-04
"""

import argparse
import datetime as dt
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Bible Crossword Challenge", "Resources")
PUZZLES = os.path.join(RESOURCES, "puzzles.json")
SCHEDULE = os.path.join(RESOURCES, "schedule.json")

EPOCH = dt.date(2026, 7, 1)
# PuzzleProvider.sundayRotationOffset at the time the schedule took over.
LEGACY_SUNDAY_OFFSET = 5
LOCK_DAYS = 7
HORIZON_DAYS = 56


def pools(puzzles):
    daily = [p["id"] for p in puzzles if p.get("kind") is None and not p["id"].startswith("pack-")]
    mini = [p["id"] for p in puzzles if p.get("kind") == "mini"]
    sunday = [p["id"] for p in puzzles if p.get("kind") == "sunday"]
    return daily, mini, sunday


def week_sunday(d):
    """The Sunday that starts `d`'s week (Sunday-first, locale-independent)."""
    return d - dt.timedelta(days=d.isoweekday() % 7)


def legacy_day(pool, d):
    return pool[(d - EPOCH).days % len(pool)]


def legacy_sunday(pool, sunday):
    # Swift: weekIndex = floor(dayIndex(sunday) / 7), then (week - offset) % count.
    week = (sunday - EPOCH).days // 7
    return pool[(week - LEGACY_SUNDAY_OFFSET) % len(pool)]


def build(today):
    puzzles = json.load(open(PUZZLES))
    daily, mini, sunday = pools(puzzles)
    existing = json.load(open(SCHEDULE)) if os.path.exists(SCHEDULE) else {}

    lock = (today + dt.timedelta(days=LOCK_DAYS)).isoformat()
    end = today + dt.timedelta(days=HORIZON_DAYS)
    days = [(EPOCH + dt.timedelta(days=i)).isoformat() for i in range((end - EPOCH).days + 1)]

    def first_sunday_keys():
        s = week_sunday(EPOCH)
        keys = []
        while s <= end:
            keys.append(s.isoformat())
            s += dt.timedelta(days=7)
        return keys

    def as_date(k):
        return dt.date.fromisoformat(k)

    # Locked entries that exist are kept even when they fall in [today, lock];
    # missing ones in that range are planned like the future, except dates up
    # to today, which must be legacy.
    def plan_pool(pool, key, keys, legacy):
        ex = existing.get(key, {})
        # Missing entries up to today → legacy; existing up to lock → kept.
        out = {}
        last = {}
        future = []
        for k in keys:
            if k in ex and k <= lock:
                out[k] = ex[k]
            elif k <= today.isoformat():
                out[k] = legacy(as_date(k))
            else:
                future.append(k)
                continue
            last[out[k]] = k
        for k, v in ex.items():
            if k <= lock and k not in out:
                out[k] = v
                last[v] = max(last.get(v, k), k)
        order = {pid: i for i, pid in enumerate(pool)}
        for k in future:
            choice = min(pool, key=lambda pid: (pid in last, last.get(pid, ""), order[pid]))
            out[k] = choice
            last[choice] = k
        return dict(sorted(out.items()))

    return {
        "version": 1,
        "epoch": EPOCH.isoformat(),
        "daily": plan_pool(daily, "daily", days, lambda d: legacy_day(daily, d)),
        "mini": plan_pool(mini, "mini", days, lambda d: legacy_day(mini, d)),
        "sunday": plan_pool(sunday, "sunday", first_sunday_keys(), lambda s: legacy_sunday(sunday, s)),
    }, existing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 if the schedule would change")
    ap.add_argument("--today", help="YYYY-MM-DD (default: local today)")
    args = ap.parse_args()
    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()

    schedule, existing = build(today)

    # Guard: no locked entry may ever change.
    lock = (today + dt.timedelta(days=LOCK_DAYS)).isoformat()
    for key in ("daily", "mini", "sunday"):
        for k, v in existing.get(key, {}).items():
            if k <= lock and schedule[key].get(k) != v:
                print(f"error: locked {key} {k} would change {v} -> {schedule[key].get(k)}")
                sys.exit(1)

    text = json.dumps(schedule, indent=1) + "\n"
    if args.check:
        need = (today + dt.timedelta(days=LOCK_DAYS)).isoformat()
        for key in ("daily", "mini"):
            if max(existing.get(key, {"": ""})) < need:
                print(f"error: {key} schedule ends before {need} — run tools/build_schedule.py")
                sys.exit(1)
        print("schedule.json ok: locked entries unchanged, covers the lock window")
        return
    open(SCHEDULE, "w").write(text)
    for key in ("daily", "mini", "sunday"):
        entries = schedule[key]
        print(f"{key}: {len(entries)} entries, {min(entries)} → {max(entries)}")


if __name__ == "__main__":
    main()
