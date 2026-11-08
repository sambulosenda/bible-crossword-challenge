#!/bin/sh
# Xcode Cloud: runs before every xcodebuild action.
set -eu

# Test-without-building runs on a machine with no repository checkout.
[ "${CI_XCODEBUILD_ACTION:-}" = "test-without-building" ] && exit 0

# Bad packs.json / quests.json ship silently (the app drops what it can't
# decode), so fail the build here instead of in a player's hands.
python3 "$CI_PRIMARY_REPOSITORY_PATH/tools/validate_content.py"
