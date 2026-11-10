//
//  SoundEffectsTests.swift
//  Bible Crossword ChallengeTests
//
//  A sound that isn't in the bundle fails silently by design (no crash, no
//  noise), which also means nobody would notice it was gone. These pin the
//  files to the app and the Settings switch to its default.
//

import Testing
import Foundation
@testable import Bible_Crossword_Challenge

@MainActor
struct SoundEffectsTests {
    let defaults = UserDefaults(suiteName: "sound-tests-\(UUID().uuidString)")!

    @Test func everySoundShipsInTheApp() {
        let sounds = SoundEffects(defaults: defaults, bundle: .main)
        for effect in SoundEffect.allCases {
            #expect(sounds.url(for: effect) != nil, "\(effect.rawValue).wav is missing from the app bundle")
        }
    }

    @Test func onByDefault() {
        #expect(SoundEffects(defaults: defaults).isEnabled)
    }

    @Test func settingsSwitchTurnsThemOff() {
        defaults.set(false, forKey: SoundEffects.enabledKey)
        #expect(!SoundEffects(defaults: defaults).isEnabled)
    }
}
