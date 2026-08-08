//
//  ChallengeHistoryView.swift
//  Bible Crossword Challenge
//
//  Every challenge this device has played or sent, newest first. Pushed from
//  Profile, where the same rows appear as a short preview.
//
//  Nothing here is synced or verified — it's the local record of a loop that
//  runs on links and the honour system (see `ChallengeService`), so the screen
//  claims no more than "this is what happened on this phone".
//

import SwiftUI

struct ChallengeHistoryView: View {
    @Bindable var profile: PlayerProfile

    @Environment(\.challengeHistory) private var challengeHistory
    @Environment(\.challengeService) private var challengeService
    @Environment(\.puzzleProvider) private var puzzleProvider
    @Environment(\.analytics) private var analytics
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    /// The row whose action sheet is open.
    @State private var selected: ChallengeHistory.Entry?
    @State private var share: ChallengeShareItem?
    /// A challenge waiting on a display name, stashed across the prompt.
    @State private var pendingNameEntry: ChallengeHistory.Entry?
    @State private var showNamePrompt = false
    @State private var draftName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if challengeHistory.entries.isEmpty {
                    emptyState
                } else {
                    ChallengeHistoryList(entries: challengeHistory.entries) { entry in
                        selected = entry
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            selected?.puzzleTitle ?? "",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible,
            presenting: selected
        ) { entry in
            if puzzleProvider.puzzle(id: entry.puzzleID) != nil {
                Button("Play Again") { playAgain(entry) }
            }
            Button("Challenge Again") { sendChallenge(for: entry) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.caption, item.url]) { completed in
                guard completed else { return }
                challengeHistory.markRematchSent(
                    puzzleID: item.puzzleID,
                    puzzleTitle: item.puzzleTitle,
                    mySeconds: item.seconds
                )
            }
        }
        .alert("What should we call you?", isPresented: $showNamePrompt) {
            TextField("Your name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Save") { saveNameAndSend() }
            Button("Cancel", role: .cancel) { pendingNameEntry = nil }
        } message: {
            Text("We'll show this name to friends you challenge.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("No challenges yet")
                .font(.headline)
            Text("Solve a puzzle, then tap Challenge a Friend to send them the same grid.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .elevatedCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    /// Replay the grid. The solve is already recorded, so `CrosswordGameView`
    /// won't double-count it — and the shared time below still comes from the
    /// original solve, not this replay.
    private func playAgain(_ entry: ChallengeHistory.Entry) {
        guard let url = URL(string: "biblecrossword://puzzle?id=\(entry.puzzleID)") else { return }
        openURL(url)
        dismiss()
    }

    /// Re-send this puzzle carrying the time already on the row. A history row
    /// can't produce a fresh time, and inventing one would be the one dishonesty
    /// a brag sheet can't survive.
    private func sendChallenge(for entry: ChallengeHistory.Entry) {
        guard hasChosenName else {
            pendingNameEntry = entry
            draftName = ""
            afterDialogDismissal { showNamePrompt = true }
            return
        }
        guard let url = challengeService.challengeWebURL(
            puzzleID: entry.puzzleID, seconds: entry.mySeconds, name: profile.username
        ) else { return }
        let item = ChallengeShareItem(
            url: url,
            caption: "Can you beat me? I solved \"\(entry.puzzleTitle)\" in \(TimeFormat.clock(entry.mySeconds)) — Bible Crossword",
            puzzleID: entry.puzzleID,
            puzzleTitle: entry.puzzleTitle,
            seconds: entry.mySeconds
        )
        analytics.log(.challengeRematchSent(puzzleID: entry.puzzleID))
        afterDialogDismissal { share = item }
    }

    /// Run a presentation once the row's confirmation dialog has finished
    /// leaving.
    ///
    /// iOS presents one thing at a time: asking for the share sheet (or the name
    /// alert) from a dialog button, while that dialog is still dismissing, drops
    /// the request silently — and because the ask already mutated our state, the
    /// second tap changes nothing and so does nothing either. The dialog's exit
    /// is an animation with no completion handler to hang this off, so it's a
    /// wait, and the wait is generous rather than tuned.
    private func afterDialogDismissal(_ work: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            work()
        }
    }

    /// True once the player has set a display name (the default counts as unset).
    private var hasChosenName: Bool {
        let name = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != ChallengeService.placeholderName
    }

    private func saveNameAndSend() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let entry = pendingNameEntry else { return }
        profile.username = String(name.prefix(20))
        pendingNameEntry = nil
        sendChallenge(for: entry)
    }
}

/// An outgoing challenge handed to the share sheet. Identifiable so it can drive
/// `.sheet(item:)`; a fresh id each time forces re-presentation.
struct ChallengeShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let caption: String
    let puzzleID: String
    let puzzleTitle: String
    let seconds: Int
}

// MARK: - Rows

/// The card of rows, shared between the full screen and Profile's preview.
struct ChallengeHistoryList: View {
    let entries: [ChallengeHistory.Entry]
    let onSelect: (ChallengeHistory.Entry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // One view per element: the hairline is an overlay on the row rather
            // than a sibling, so the row count stays constant per entry.
            ForEach(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    ChallengeHistoryRow(entry: entry)
                        .overlay(alignment: .top) {
                            if entry.id != entries.first?.id {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 1)
                                    .padding(.leading, 52)
                            }
                        }
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .elevatedCard()
    }
}

struct ChallengeHistoryRow: View {
    let entry: ChallengeHistory.Entry

    @ScaledMetric(relativeTo: .body) private var chipSize: CGFloat = 30

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: chipSize, height: chipSize)
                .background(tint, in: .rect(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.puzzleTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(headline)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows options to play again or send another challenge")
    }

    private var symbol: String {
        switch entry.outcome {
        case .won: "crown.fill"
        case .lost: "flag.checkered"
        case .tied: "equal"
        case .none: "paperplane.fill"
        }
    }

    /// Green for a win; everything else stays neutral. A loss painted red would
    /// make the list read as a scoreboard of failures — the point is that the
    /// matchup happened.
    private var tint: Color {
        entry.outcome == .won ? .green : .secondary
    }

    private var headline: String {
        switch entry.outcome {
        case .won: "Won"
        case .lost: "Lost"
        case .tied: "Tied"
        case .none: entry.rematchSentAt == nil ? "Sent" : "Rematch"
        }
    }

    private var detail: String {
        guard let name = entry.opponentName, let theirs = entry.opponentSeconds else {
            return "Your time \(TimeFormat.clock(entry.mySeconds))"
        }
        var line = "You \(TimeFormat.clock(entry.mySeconds)) · \(name) \(TimeFormat.clock(theirs))"
        if entry.rematchSentAt != nil { line += " · rematch sent" }
        return line
    }

    private var accessibilityText: String {
        let date = entry.date.formatted(.dateTime.month(.wide).day())
        guard let name = entry.opponentName, let theirs = entry.opponentSeconds else {
            return "\(entry.puzzleTitle). Challenge sent \(date), your time \(TimeFormat.clock(entry.mySeconds))."
        }
        let verdict = switch entry.outcome {
        case .won: "You won"
        case .lost: "\(name) won"
        default: "Tied"
        }
        return "\(entry.puzzleTitle). \(verdict). You \(TimeFormat.clock(entry.mySeconds)), \(name) \(TimeFormat.clock(theirs)). \(date)."
    }
}
