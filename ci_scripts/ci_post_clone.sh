#!/bin/sh
# Xcode Cloud: runs once after the repo is cloned, before packages resolve.
set -eu

# Packages here ship no macros or build plugins today; this keeps a future one
# from failing the build on the "trust this package" prompt CI can't answer.
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
