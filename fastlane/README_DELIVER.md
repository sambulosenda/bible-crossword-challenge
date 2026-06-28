# Pushing App Store metadata with fastlane deliver

Metadata for each App Store locale lives in `fastlane/metadata/<locale>/`:

- `name.txt` — app title (max 30 chars)
- `subtitle.txt` — subtitle (max 30 chars)
- `keywords.txt` — comma-separated keyword field (max 100 chars, no spaces after commas)

Locales present: `en-US`, `en-GB`, `en-AU`, `en-CA`.

Only title / subtitle / keywords are managed here. Description, screenshots, and
the build are intentionally left untouched (`skip_screenshots`, `skip_binary_upload`).

## One-time auth: App Store Connect API key (dotenv)

1. App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys.
2. Create a key with role **App Manager**, download the `.p8` (once only), keep it OUTSIDE the repo.
3. `cp fastlane/.env.example fastlane/.env` and fill in `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.
   `fastlane/.env` is git-ignored and loaded automatically on every run.

## Push metadata (preview first, then confirm)

```bash
fastlane push_metadata
```

The `push_metadata` lane (see Fastfile) shows an HTML preview and asks for confirmation
before uploading. It only touches title/subtitle/keywords — `skip_binary_upload`,
`skip_screenshots`, and `submit_for_review(false)` are set in the Deliverfile, so nothing
goes live or gets submitted automatically. Description/screenshots have no files here, so
deliver leaves them untouched.

## Optional: pull current live metadata first

```bash
fastlane deliver download_metadata --api_key_path <api_key.json>
```

Not required with this setup (we manage only 3 fields), but handy if you want the full
listing mirrored locally.
