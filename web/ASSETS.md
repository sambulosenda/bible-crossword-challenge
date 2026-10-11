# Landing page assets

| File                     | Where it shows                                  |
|--------------------------|-------------------------------------------------|
| `shot-today.webp`        | Daily-ritual section — Today                    |
| `shot-complete.webp`     | Screens section, card 1 — Puzzle Completed      |
| `shot-puzzle.webp`       | Screens section, card 2 — grid mid-solve        |
| `shot-achievements.webp` | Screens section, card 3 — Achievements          |
| `shot-profile.webp`      | (spare) Profile — reads as an empty zero state  |
| `shot-archive.webp`      | (stale) the tab is called **Library** now       |
| `shot-*.png`             | Full-res sources; also the JSON-LD `screenshot` |
| `og-image.png`           | Social share preview — 1200×630 branded card    |
| `apple-touch-icon.png`   | iOS home-screen bookmark — 180×180 app mark     |

The page loads the `.webp`s; the `.png`s are kept as sources and are what
`SoftwareApplication.screenshot` points at in `src/pages/index.astro`.

## Refreshing the screenshots

Sources are full-bleed **1206×2622** — an iPhone 17 Pro at 3×. Any device with
those point dimensions (402×874) works; if you use a different one, every PNG in
the set must match or the cards will not line up.

Build and install the app, then set the simulator up so the chrome is clean and
the appearance matches the rest of the set (**light** — the app's warm paper
canvas, which is what the page's paper band is built around):

```sh
UDID=$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;print(next(d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v))')
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode notSupported --batteryState discharging --batteryLevel 100
```

Drive the app to each screen and capture:

```sh
xcrun simctl io "$UDID" screenshot shot-today.png
```

`--batteryState charged` renders a green charging battery — use `discharging`
at level 100 for a plain full one. Clear the override afterwards with
`xcrun simctl status_bar "$UDID" clear`.

Then regenerate the WebPs the page actually loads:

```sh
for f in shot-today shot-puzzle shot-achievements shot-profile; do
  magick "$f.png" -resize 720x -quality 82 "$f.webp"
done
```

That yields **720×1565**. If the source aspect ratio ever changes, update the
`width`/`height` on the `<img>` in `src/pages/index.astro` to match, or the
cards will shift as the images load.

## Keep the captions honest

`src/pages/index.astro` names what is on each screenshot — the visible clue, the
puzzle title, the screens on the tab bar. Update that copy in the same change,
or the alt text will describe an app that no longer exists.

`og-image.png` is a rendered brand card; regenerate only if the brand or
tagline changes.

`shot-complete` is cropped from the App Store marketing shot
`fastlane/screenshots/en-US/image6.jpg` (720 wide) rather than captured raw,
so it is not 1206×2622 like the rest; recapture it with the steps above when
the set is next refreshed — at a new filename, since `/assets` is immutable.
