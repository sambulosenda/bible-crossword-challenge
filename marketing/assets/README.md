# Landing page assets

| File                    | Where it shows           | Source                          |
|-------------------------|--------------------------|---------------------------------|
| `shot-today.png`        | Source of `.webp` + JSON-LD screenshot | Today / Daily Puzzle |
| `shot-puzzle.png`       | Source of `.webp` + JSON-LD screenshot | Crossword grid       |
| `shot-profile.png`      | Source of `.webp` + JSON-LD screenshot | Profile / Achievements |
| `shot-archive.png`      | (spare)                  | Archive list                    |
| `shot-*.webp`           | The `<img>`s on the page | Generated from PNGs (see below) |
| `og-image.png`          | Social share preview     | 1200×630 branded card           |
| `apple-touch-icon.png`  | iOS home-screen bookmark | 180×180 app mark                |

## Refreshing screenshots

Drop new full-bleed PNGs (~1206×2622) here, then regenerate the WebP versions
the page actually loads:

```sh
for f in shot-today shot-puzzle shot-profile shot-archive; do
  magick "$f.png" -resize 720x -quality 82 "$f.webp"
done
```

`og-image.png` is a rendered brand card (1200×630) — regenerate only if the
brand/tagline changes.
