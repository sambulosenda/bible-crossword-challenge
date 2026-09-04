#!/usr/bin/env python3
"""Normalise clue and title spelling to American English.

The bank was authored over months by different hands and mixes colour/color,
honour/honor, traveller/traveler. The verse under every clue is the BSB, which
is American English, and the store is US-first — so clues follow the verse.

Edits only `clue` and `title` text, in puzzle_specs.json and the shipped
puzzles.json alike, so grids, ids and order are untouched (the numstat on
puzzles.json shows equal adds and deletes, all clue/title lines). Verse text is
never touched: it is the BSB verbatim.

Usage: python3 tools/americanize_clues.py   (prints every change; --check
only reports, exit 1 if anything would change)
"""
import json, re, sys

HERE = __file__.rsplit("/", 1)[0]
SPECS = f"{HERE}/puzzle_specs.json"
SHIPPED = f"{HERE}/../Bible Crossword Challenge/Resources/puzzles.json"

# stem -> replacement, applied to whole words with any of the listed suffixes.
RULES = [
    (r"colour", "color"), (r"honour", "honor"), (r"favour", "favor"),
    (r"armour", "armor"), (r"saviour", "savior"), (r"neighbour", "neighbor"),
    (r"splendour", "splendor"), (r"savour", "savor"), (r"labour", "labor"),
    (r"harbour", "harbor"), (r"vigour", "vigor"), (r"valour", "valor"),
    (r"humour", "humor"), (r"odour", "odor"), (r"rumour", "rumor"),
    (r"fervour", "fervor"), (r"behaviour", "behavior"), (r"endeavour", "endeavor"),
    (r"flavour", "flavor"), (r"clamour", "clamor"),
    (r"mould", "mold"), (r"grey", "gray"), (r"plough", "plow"),
    (r"sceptre", "scepter"), (r"centre", "center"), (r"theatre", "theater"),
    (r"defence", "defense"), (r"offence", "offense"), (r"pretence", "pretense"),
    (r"judgement", "judgment"), (r"artefact", "artifact"), (r"sulphur", "sulfur"),
    (r"marvellous", "marvelous"), (r"jewellery", "jewelry"), (r"counsellor", "counselor"),
    (r"travell", "travel"), (r"quarrell", "quarrel"), (r"marvell", "marvel"),
    (r"levell", "level"), (r"labell", "label"), (r"modell", "model"),
    (r"signall", "signal"), (r"cancell", "cancel"), (r"fuell", "fuel"),
    (r"counsell", "counsel"), (r"jewell", "jewel"), (r"revell", "revel"),
    (r"baptis(e|ed|es|ing)\b", None), (r"(organ|recogn|real|apolog|emphas|critic|symbol|bapt|civil|memor|author|prophes)is(e|ed|es|ing)\b", None),
    (r"\bfulfil\b", "fulfill"), (r"\benrol\b", "enroll"), (r"\binstal\b", "install"),
    (r"skilful", "skillful"), (r"wilful", "willful"), (r"ageing", "aging"),
    (r"\blearnt\b", "learned"), (r"\bspelt\b", "spelled"), (r"\bdreamt\b", "dreamed"),
    (r"\bleapt\b", "leaped"), (r"\bsmelt\b", "smelled"), (r"\bspoilt\b", "spoiled"),
    (r"\bwhilst\b", "while"), (r"\bamongst\b", "among"),
    (r"practis", "practic"), (r"licence", "license"),
]

def _case(src, repl):
    if src.isupper(): return repl.upper()
    if src[0].isupper(): return repl[0].upper() + repl[1:]
    return repl

def americanize(text):
    for stem, repl in RULES:
        if repl is None:
            # -ise → -ize families: keep the captured suffix.
            def ize(m):
                s = m.group(0)
                return _case(s, s[:-len(m.group(m.lastindex))-2] + "iz" + m.group(m.lastindex)) if False else _case(s, re.sub(r"is(e|ed|es|ing)$", r"iz\1", s.lower()))
            text = re.sub(stem, ize, text, flags=re.I)
            continue
        pattern = stem if stem.startswith(r"\b") else r"\b" + stem
        text = re.sub(pattern + r"(\w*)", lambda m: _case(m.group(0), repl + (m.group(m.lastindex) if m.lastindex else "").lower()) if not stem.startswith(r"\b") else _case(m.group(0), repl), text, flags=re.I)
    return text

# Titles that quote the KJV keep its spelling.
KEEP_TITLES = {"Hail, Thou That Art Highly Favoured"}

def walk(puzzles, key_words):
    changes = []
    for p in puzzles:
        new = p["title"] if p["title"] in KEEP_TITLES else americanize(p["title"])
        if new != p["title"]:
            changes.append((p.get("id", p["title"]), "title", p["title"], new)); p["title"] = new
        for w in p[key_words]:
            k = "clue" if "clue" in w else "text"
            new = americanize(w[k])
            if new != w[k]:
                changes.append((p.get("id", p["title"]), w["answer"], w[k], new)); w[k] = new
    return changes

def main():
    check = "--check" in sys.argv
    total = 0
    for path, key in ((SPECS, "words"), (SHIPPED, "clues")):
        with open(path) as f: data = json.load(f)
        changes = walk(data, key)
        total += len(changes)
        for pid, where, old, new in changes:
            print(f"{path.rsplit('/',1)[1]} {pid} / {where}:\n   {old}\n → {new}")
        if changes and not check:
            # Match each file's existing serialisation so the diff is only the
            # text that changed: the generator writes puzzles.json with
            # ensure_ascii (\u201c quotes) and no trailing newline; the specs
            # are kept human-readable.
            shipped = path == SHIPPED
            with open(path, "w") as f:
                json.dump(data, f, indent=2, ensure_ascii=shipped)
                if not shipped: f.write("\n")
    print(f"{total} change(s){' (not written)' if check else ''}")
    sys.exit(1 if check and total else 0)

if __name__ == "__main__":
    main()
