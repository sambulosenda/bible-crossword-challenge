fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios push_metadata

```sh
[bundle exec] fastlane ios push_metadata
```

Push title/subtitle/keywords for all locales. Shows an HTML preview and asks for confirmation before uploading. No binary, no screenshots, no submission. Pass version:X.Y to create/select that editable version in App Store Connect.

### ios upload_build

```sh
[bundle exec] fastlane ios upload_build
```

Archive the app and upload the binary to App Store Connect. No metadata, no screenshots, no submission — the build lands in ASC for manual selection. Signing is cloud-managed through the ASC API key, so no local distribution certificate is required.

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload App Store screenshots for all locales (no metadata, no binary, no submission). Overwrites the existing screenshot set for the editable version.

### ios upload_ipa

```sh
[bundle exec] fastlane ios upload_ipa
```

Upload an already-built .ipa without re-archiving. Use when upload_build produced build/*.ipa but the upload leg failed — saves the ~25 minute archive.

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit an editable version for App Store review: pushes metadata for every locale, selects the build, answers export compliance and IDFA, and submits. Pass version:X.Y and build:N. Never uploads a binary or screenshots — the screenshot set already on the version is left untouched. Add auto_release:true to go live the moment Apple approves; the default holds it for a manual release. Run upload_build first and let the build finish processing.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
