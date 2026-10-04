//
//  MemoryVerseListView.swift
//  Bible Crossword Challenge
//
//  The memory-verse shelf: what's due for review, what's still being learned,
//  what's mastered, and the verses met in solved puzzles that could be next.
//  "Seen" is derived on demand from completed records — the BibleJourney
//  pattern, no stored history.
//

import SwiftUI
import SwiftData

/// Navigation value pushing the verse list from Today.
struct MemoryRoute: Hashable {}

struct MemoryVerseListView: View {
    /// Which surface pushed it — `home_card` from Today, `read_tab` from Read.
    var source: String = "home_card"

    @Environment(\.memoryVerses) private var memoryVerses
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.analytics) private var analytics
    @Environment(\.scripture) private var scripture
    @Environment(StoreService.self) private var store
    @Query private var records: [PuzzleRecord]

    /// Well-known verses offered when the player's puzzles haven't given them
    /// any yet. Read from the bundled Bible once it has loaded, so the text
    /// matches the reader's word for word.
    @State private var starters: [MemoryVerseStore.Candidate] = []

    /// Short, widely memorized, and each within `MemoryCloze`'s length limit
    /// — anything that fails it is dropped rather than shown. Not Psalm 23:1:
    /// this translation opens it with the heading "A Psalm of David."
    private static let starterReferences = [
        "John 3:16", "Matthew 11:28", "Philippians 4:13", "Proverbs 3:5",
        "Joshua 1:9", "Psalm 119:105", "Romans 8:28", "Isaiah 40:31",
    ]

    /// A just-started candidate, pushed via a local destination because the
    /// start is gated — a plain `NavigationLink` couldn't check the shelf first.
    @State private var startedKey: String?

    private var candidates: [MemoryVerseStore.Candidate] {
        let completed = Set(records.filter(\.isCompleted).map(\.puzzleID))
        return memoryVerses.candidates(completedPuzzleIDs: completed, puzzles: puzzleProvider.allPuzzles)
    }

    private var due: [MemoryVerseStore.Entry] { memoryVerses.entries.filter { memoryVerses.isDue($0) } }
    private var learning: [MemoryVerseStore.Entry] {
        memoryVerses.entries.filter { !memoryVerses.isDue($0) && !$0.isMastered }
    }
    private var mastered: [MemoryVerseStore.Entry] {
        memoryVerses.entries.filter { !memoryVerses.isDue($0) && $0.isMastered }
    }

    /// A free player holding `freeVerseLimit` unmastered verses. The cap stays;
    /// what it opened changed. It used to open the paywall — 70 times from 10
    /// players in the 30 days to 2026-10-03, with no taps — so now the list
    /// says how to make room instead, before anyone taps.
    private var shelfFull: Bool { !memoryVerses.canStartNewVerse(isPremium: store.isPremium) }

    var body: some View {
        Group {
            // Empty only until the starters load: "Choose a verse" on the
            // Verses tab used to land a player with no solved puzzles on a
            // screen with nothing to choose.
            if memoryVerses.entries.isEmpty && candidates.isEmpty && unheldStarters.isEmpty {
                emptyState
            } else {
                verseList
            }
        }
        .navigationTitle("Memory Verses")
        .navigationBarTitleDisplayMode(.large)
        .background(Theme.background)
        .onAppear { analytics.log(.memoryListOpened(source: source)) }
        .task {
            await scripture.preload()
            starters = Self.starterReferences.compactMap { reference in
                guard let ref = ScriptureRef(reference), let verse = ref.verse,
                      let text = scripture.chapter(ref)?.chapter.verses.first(where: { $0.number == verse })?.text,
                      MemoryCloze.isEligible(verseText: text) else { return nil }
                return MemoryVerseStore.Candidate(reference: reference, verseText: text)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { startedKey != nil },
            set: { if !$0 { startedKey = nil } }
        )) {
            if let startedKey {
                MemoryPracticeView(referenceKey: startedKey, source: "list")
            }
        }
    }

    private var verseList: some View {
        List {
            if !due.isEmpty {
                Section("Due for review") {
                    ForEach(due.sorted { dueSort($0, $1) }) { entryRow($0, isDue: true) }
                }
            }
            if !learning.isEmpty {
                Section("Learning") {
                    ForEach(learning.sorted { canonSort($0.reference, $1.reference) }) { entryRow($0, isDue: false) }
                }
            }
            if !mastered.isEmpty {
                Section("Mastered") {
                    ForEach(mastered.sorted { canonSort($0.reference, $1.reference) }) { entryRow($0, isDue: false) }
                }
            }
            if !candidates.isEmpty {
                Section {
                    // First in the section, not the footer: the footer sits
                    // under every candidate, and a list this long hides it
                    // below the rows it explains.
                    if shelfFull { shelfFullNote }
                    ForEach(candidates.sorted { canonSort($0.reference, $1.reference) }) { candidateRow($0) }
                } header: {
                    Text("From your solved puzzles")
                } footer: {
                    Text("Every puzzle you solve adds its verse here.")
                }
            }
            // Only while the puzzles have offered nothing to start: once they
            // have, those verses are the point of the list.
            if candidates.isEmpty && !unheldStarters.isEmpty {
                Section {
                    if shelfFull { shelfFullNote }
                    ForEach(unheldStarters) { candidateRow($0, source: "starter") }
                } header: {
                    Text("Verses to start with")
                } footer: {
                    Text("Every puzzle you solve adds its verse here too.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        // Readable column on iPad, matching LibraryView's lists.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rows

    private func entryRow(_ entry: MemoryVerseStore.Entry, isDue: Bool) -> some View {
        NavigationLink(value: MemoryPracticeRoute(referenceKey: entry.referenceKey)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(entry.reference)
                        .font(.headline)
                    if isDue {
                        Text("Review")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.14), in: .capsule)
                            .foregroundStyle(Theme.accent)
                    } else if entry.isMastered {
                        Image(systemName: "medal.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else if let at = memoryVerses.levelUpAvailableAt(entry) {
                        // The anti-grind wait, said out loud: a flawless round
                        // inside it practices but doesn't level.
                        Text("Level up in \(TimeFormat.countdown(at.timeIntervalSinceNow))")
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    MasteryDots(level: entry.level)
                }
                Text(entry.verseText)
                    .font(.scripture(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                memoryVerses.remove(referenceKey: entry.referenceKey)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entryAccessibilityLabel(entry, isDue: isDue))
    }

    private func candidateRow(_ candidate: MemoryVerseStore.Candidate, source: String = "list") -> some View {
        Button {
            startCandidate(candidate, source: source)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(candidate.reference)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(candidate.verseText)
                        .font(.scripture(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Start")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.ink, in: .capsule)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        // Plain, or the row's .primary/.secondary hierarchy resolves against
        // the button tint and the whole row reads accent-blue.
        .buttonStyle(.plain)
        .disabled(shelfFull)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Start memorizing \(candidate.reference). \(candidate.verseText)")
    }

    private var shelfFullNote: some View {
        Label(
            "You can learn \(MemoryVerseStore.freeVerseLimit) verses at a time. Master one to make room for the next.",
            systemImage: "brain"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// Starters the player hasn't already begun.
    private var unheldStarters: [MemoryVerseStore.Candidate] {
        starters.filter { memoryVerses.entry(for: $0.id) == nil }
    }

    private func startCandidate(_ candidate: MemoryVerseStore.Candidate, source: String = "list") {
        guard !shelfFull else { return }
        let entry = memoryVerses.start(reference: candidate.reference, verseText: candidate.verseText)
        analytics.log(.memoryVerseAdded(reference: candidate.reference, source: source))
        startedKey = entry.referenceKey
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No verses yet", systemImage: "text.book.closed")
        } description: {
            Text("Verses you meet in puzzles collect here. Solve today's puzzle to add its verse.")
        }
    }

    // MARK: - Ordering

    /// Due section: most overdue first.
    private func dueSort(_ a: MemoryVerseStore.Entry, _ b: MemoryVerseStore.Entry) -> Bool {
        let aDue = memoryVerses.dueDate(a) ?? .distantPast
        let bDue = memoryVerses.dueDate(b) ?? .distantPast
        return aDue < bDue
    }

    /// Everything else reads in canon order, like the Journey map.
    private func canonSort(_ a: String, _ b: String) -> Bool {
        let aPos = canonPosition(a)
        let bPos = canonPosition(b)
        if aPos != bPos { return aPos < bPos }
        return a < b
    }

    private func canonPosition(_ reference: String) -> Int {
        guard let ref = ScriptureRef(reference) else { return Int.max }
        return BibleCanon.position(of: ref.book)
    }

    private func entryAccessibilityLabel(_ entry: MemoryVerseStore.Entry, isDue: Bool) -> String {
        var parts = [entry.reference]
        if entry.isMastered {
            parts.append("Mastered")
        } else {
            parts.append("Level \(entry.level) of \(MemoryVerseStore.masteredLevel)")
        }
        if isDue { parts.append("Due for review") }
        if let at = memoryVerses.levelUpAvailableAt(entry) {
            parts.append("Next level-up in \(TimeFormat.countdown(at.timeIntervalSinceNow))")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Home card

/// The Today-screen doorway into the mode. Quietly informational, one line —
/// this sits below the achievement card and must not out-shout the daily.
struct MemoryVerseCard: View {
    let dueCount: Int
    let activeCount: Int
    /// Off on Today, where the "Keep going" header above names the group.
    var showsKicker = true

    var body: some View {
        NavigationLink(value: MemoryRoute()) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "brain.fill")
                    .font(.title2)
                    // The disc is a fixed 44pt, so the glyph stops growing
                    // where the disc does instead of spilling out of it.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    if showsKicker {
                        Label("MEMORY VERSES", systemImage: "text.book.closed").kicker()
                    }
                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    // Caption, like the Journey and badge rows it sits with.
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elevatedCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Memory verses. \(headline). \(subtitle)")
    }

    private var headline: String {
        if dueCount > 0 { return dueCount == 1 ? "1 verse due for review" : "\(dueCount) verses due for review" }
        // Without the kicker the headline has to say what the card is.
        if activeCount > 0 { return showsKicker ? "Keep your verses fresh" : "Memory verses" }
        return "Learn a verse by heart"
    }

    private var subtitle: String {
        if activeCount > 0 {
            return "Blanks grow as you master each verse."
        }
        return "Turn a verse from a solved puzzle into memory."
    }
}
