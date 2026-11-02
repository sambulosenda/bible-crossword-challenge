# Beginner path

Your First Seven is a free journey (`first-week`) containing seven easy Gospel
minis, ordered from five clues toward seven. It appears as Today's lead card
while a player has fewer than seven completed puzzles, or has already completed
at least one path puzzle. Completion removes the card. Experienced players can
find it under Journeys in Packs without having their Today screen replaced.

Progress comes from existing puzzle records, including solves from the daily
rotation. The first unfinished puzzle is always the next step. There is no daily
lock, new account requirement, or separate progress counter. All seven remain
free outside the rolling archive window. Existing Beginnings access is retained.

The path retains beginner stall thresholds and starter-word assistance through
its final puzzle. Its first stall points to the active clue's Bible verse when
available. The completion screen retains the solved puzzle's verse and reader,
offers Next Mini, and does not show the Premium completion offer. After all seven
are solved, the journey completion card celebrates the finished path.

## Measurement

Use existing events, joined by user and puzzle ID:

- `daily_puzzle_started`, `source = beginner_path`: starts and resumes from Today.
- `puzzle_abandoned`: early exits; group by these seven puzzle IDs and fill level.
- `quest_step_completed`, `quest_id = first-week`: first completion per step.
- `quest_completed`, `quest_id = first-week`: completed paths.
- `completion_chain_tapped`: immediate next-step choices (from/to puzzle IDs).
- `stall_nudge_shown` / `stall_nudge_tapped`, `kind = verse`: scripture help.

Compare first-step start-to-completion, continuation to step two, and next-day
and seven-day return rates for players starting the path. Returning after a
break should resume the first unfinished puzzle; steps do not reset at midnight.
