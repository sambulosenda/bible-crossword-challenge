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

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload App Store screenshots for all locales (no metadata, no binary, no submission). Overwrites the existing screenshot set for the editable version.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
