//
//  SoundEffects.swift
//  Bible Crossword Challenge
//
//  The game's small sound palette: a soft key tap, a two-note handbell chime
//  for a finished word and a handbell arpeggio over a quiet pad for a
//  finished puzzle. Every file is synthesised by `tools/sounds/make_sounds.py`
//  (no samples), so all of it is ours to ship.
//
//  The session is `.ambient`: sounds stop at the ring/silent switch, mix
//  under whatever the player is listening to instead of pausing it, and never
//  claim the audio route. The switch in Settings (`soundEffectsEnabled`,
//  on by default) silences them entirely. Haptics are separate and unchanged.
//

import AVFoundation

enum SoundEffect: String, CaseIterable {
    case keyTap = "key_tap"
    case keyDelete = "key_delete"
    case wordComplete = "word_complete"
    case puzzleComplete = "puzzle_complete"

    static let fileExtension = "wav"

    /// Player volume on top of each file's own level. The taps sit well under
    /// the chimes: they play on every key, and a tap you notice is too loud.
    var volume: Float {
        switch self {
        case .keyTap, .keyDelete: 0.35
        case .wordComplete: 0.6
        case .puzzleComplete: 0.75
        }
    }

    /// Players per sound. Taps can arrive faster than one finishes, so they
    /// round-robin instead of cutting themselves off mid-tick.
    var voices: Int {
        switch self {
        case .keyTap, .keyDelete: 3
        case .wordComplete, .puzzleComplete: 1
        }
    }
}

@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    /// `@AppStorage` key for the Settings switch. Absent means on.
    static let enabledKey = "soundEffectsEnabled"

    private let defaults: UserDefaults
    private let bundle: Bundle
    private var pools: [SoundEffect: [AVAudioPlayer]] = [:]
    private var nextVoice: [SoundEffect: Int] = [:]
    private var sessionConfigured = false

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Load and prime every player, so the first key tap isn't late. Cheap
    /// after the first call; safe to call from any screen that shows the pad.
    func prepare() {
        guard isEnabled else { return }
        configureSessionIfNeeded()
        for effect in SoundEffect.allCases { _ = pool(for: effect) }
    }

    func play(_ effect: SoundEffect) {
        guard isEnabled else { return }
        configureSessionIfNeeded()
        let players = pool(for: effect)
        guard !players.isEmpty else { return }
        let index = nextVoice[effect, default: 0] % players.count
        nextVoice[effect] = index + 1
        let player = players[index]
        player.currentTime = 0
        player.play()
    }

    /// The file a sound plays from. Synchronised folders copy resources to the
    /// bundle root; the subdirectory lookup covers a folder reference.
    func url(for effect: SoundEffect) -> URL? {
        bundle.url(forResource: effect.rawValue, withExtension: SoundEffect.fileExtension)
            ?? bundle.url(forResource: effect.rawValue, withExtension: SoundEffect.fileExtension,
                          subdirectory: "Sounds")
    }

    private func pool(for effect: SoundEffect) -> [AVAudioPlayer] {
        if let players = pools[effect] { return players }
        guard let url = url(for: effect) else {
            pools[effect] = []
            return []
        }
        let players: [AVAudioPlayer] = (0..<effect.voices).compactMap { _ in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.volume = effect.volume
            player.prepareToPlay()
            return player
        }
        pools[effect] = players
        return players
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        // Ambient: respects the silent switch and mixes with other audio.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }
}
