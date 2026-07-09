//
//  Theme.swift
//  Bible Crossword Challenge
//
//  Shared design system. Colours stay on the app's native language — the system
//  accent (blue) plus grouped-background greys. Cards lean on continuous-corner
//  squircles and soft elevation; hierarchy (not colour) carries emphasis.
//

import SwiftUI
import UIKit

enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let cornerRadius: CGFloat = 18

    /// The system accent (blue), used app-wide for the grid, links, and accents.
    static let accent = Color.accentColor

    // MARK: - Surfaces (match the rest of the app)

    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
}

// MARK: - Appearance preference

/// User-selectable app appearance, persisted via `@AppStorage("appTheme")` and
/// applied with `.preferredColorScheme` at the app root.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means follow the device setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Elevated card surface

private struct ElevatedCard: ViewModifier {
    var fill: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // Native inset-grouped style: just a rounded fill. No shadow or border —
        // separation comes from the fill contrasting the grouped background,
        // exactly like a system grouped List.
        content.background(fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Press feedback for whole-card tap targets (navigation cards, upsell rows).
/// `.plain` leaves them dead on touch — Apple's first fluid-interface rule is to
/// respond on pointer-down, so a card should subtly depress and dim the instant
/// a finger lands, not only navigate on release. Scale is dropped under Reduce
/// Motion; the dim stays as a non-vestibular press cue.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableCardBody(configuration: configuration)
    }
}

private struct PressableCardBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .opacity(configuration.isPressed ? 0.9 : 1)
            // Asymmetric: depress lands instantly (nil on press-in), release
            // settles over a short bounce-free spring — decisive, not springy.
            .animation(configuration.isPressed ? nil : .spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}

extension View {
    /// Applies the standard card treatment: a rounded grouped-background fill.
    func elevatedCard(fill: Color = Theme.surface, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(ElevatedCard(fill: fill, cornerRadius: cornerRadius))
    }

    /// The shared eyebrow/kicker label style used above every card heading.
    func kicker(_ color: Color = Theme.accent) -> some View {
        self
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(1.0)
            .foregroundStyle(color)
    }
}

enum CellPalette {
    static let empty = Color(.secondarySystemGroupedBackground)
    static let border = Color(.separator)

    /// Active-word tint. Stronger in dark mode, where an 0.18 accent wash over
    /// near-black cells is barely distinguishable from the empty fill.
    private static let inWord = Color(uiColor: UIColor { trait in
        .tintColor.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.30 : 0.18)
    })

    static func fill(isSelected: Bool, isInWord: Bool, showError: Bool, isCorrect: Bool) -> Color {
        if isSelected { return Theme.accent.opacity(0.85) }
        if showError { return Color.red.opacity(0.28) }
        if isCorrect { return Color.green.opacity(0.18) }
        if isInWord { return inWord }
        return empty
    }

    static func textColor(isSelected: Bool) -> Color {
        isSelected ? .white : .primary
    }
}
