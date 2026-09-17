//
//  Theme.swift
//  Bible Crossword Challenge
//
//  Shared design system, inspired by YouVersion's component language: a warm
//  paper canvas with white cards, solid "ink" pill CTAs, and serif type
//  reserved for scripture and hero titles — on the app's own blue accent.
//  Hierarchy (not colour) still carries emphasis.
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

    static let cornerRadius: CGFloat = 20

    /// The system accent (blue) — kept as the brand colour; the YouVersion
    /// influence lives in the components (paper canvas, ink pills, serif
    /// scripture, streak week row), not the hue.
    static let accent = Color.accentColor

    /// Resolves one colour across every context the system can ask for: light
    /// and dark, each at default and increased contrast, and — in dark only —
    /// each at the base and elevated interface levels.
    ///
    /// Every custom colour goes through here so none of them can ship with half
    /// its contexts filled in again. They used to answer only to light and
    /// dark, which meant Increase Contrast moved the system colours around them
    /// — the accent, the tints, the bars — while the canvas, the cards and the
    /// ink pills stayed exactly where they were. The setting's whole job on
    /// this app's screens is telling a white card from the paper behind it, and
    /// that was the one pair that did not respond.
    ///
    /// Elevation is the same story one layer up. In dark, the system lifts a
    /// background when its view comes to the front — a sheet, a popover — so
    /// the layer reads as being on top of the screen rather than replacing it.
    /// A custom background opts out of that, and this app sets one on every
    /// screen: the clue list over the grid was the same near-black as the grid,
    /// with a corner radius as the only clue that anything had been presented.
    /// Light has no base/elevated split — the system's own backgrounds resolve
    /// identically there — so only dark carries elevated values, and only the
    /// colours with a reason to lift pass them.
    private static func adaptive(
        light: UIColor,
        lightHighContrast: UIColor,
        dark: UIColor,
        darkHighContrast: UIColor,
        darkElevated: UIColor? = nil,
        darkElevatedHighContrast: UIColor? = nil
    ) -> Color {
        Color(uiColor: UIColor { trait in
            let high = trait.accessibilityContrast == .high
            guard trait.userInterfaceStyle == .dark else {
                return high ? lightHighContrast : light
            }
            guard trait.userInterfaceLevel == .elevated else {
                return high ? darkHighContrast : dark
            }
            return high
                ? (darkElevatedHighContrast ?? darkHighContrast)
                : (darkElevated ?? dark)
        })
    }

    /// The rim on celebration badges (solve, achievement, freeze). One token so
    /// the three badges can't drift apart, and darker on paper so the gold still
    /// reads against a light background.
    static let badgeRim = adaptive(
        light: UIColor(red: 0.804, green: 0.596, blue: 0.106, alpha: 1),          // #CD981B
        lightHighContrast: UIColor(red: 0.671, green: 0.478, blue: 0.055, alpha: 1),
        dark: UIColor(red: 0.976, green: 0.800, blue: 0.298, alpha: 1),           // #F9CC4C
        darkHighContrast: UIColor(red: 1.0, green: 0.867, blue: 0.451, alpha: 1)
    )

    // MARK: - Surfaces

    /// Warm paper canvas instead of the cool system grey.
    ///
    /// Increased contrast pulls the paper down and away from the white card on
    /// top of it, which is the same move the system makes with its own grouped
    /// backgrounds. The warmth is kept: this is a darker paper, not a grey one.
    static let background = adaptive(
        light: UIColor(red: 0.969, green: 0.961, blue: 0.949, alpha: 1),          // paper #F7F5F2
        lightHighContrast: UIColor(red: 0.906, green: 0.894, blue: 0.875, alpha: 1),
        dark: UIColor(red: 0.055, green: 0.051, blue: 0.047, alpha: 1),           // warm near-black
        darkHighContrast: UIColor(red: 0.027, green: 0.024, blue: 0.022, alpha: 1),
        darkElevated: UIColor(red: 0.098, green: 0.094, blue: 0.090, alpha: 1),
        darkElevatedHighContrast: UIColor(red: 0.075, green: 0.071, blue: 0.067, alpha: 1)
    )

    /// Card surface: white on paper in light; a warm elevated grey in dark.
    ///
    /// White has nowhere to go in light, so there the separation is won by the
    /// canvas above. In dark the card lifts instead — the canvas is already
    /// close to black.
    ///
    /// It lifts with the canvas when elevated, by the same step, so a card
    /// inside a sheet keeps exactly the separation it has on a screen. Lifting
    /// the canvas alone would have closed the gap and swallowed the cards.
    static let surface = adaptive(
        light: .white,
        lightHighContrast: .white,
        dark: UIColor(red: 0.110, green: 0.106, blue: 0.102, alpha: 1),           // #1C1B1A
        darkHighContrast: UIColor(red: 0.157, green: 0.153, blue: 0.149, alpha: 1),
        darkElevated: UIColor(red: 0.153, green: 0.149, blue: 0.145, alpha: 1),
        darkElevatedHighContrast: UIColor(red: 0.200, green: 0.196, blue: 0.192, alpha: 1)
    )

    /// "Ink" — the solid fill behind the one loud pill CTA per screen
    /// (black-on-light, white-on-dark, YouVersion's primary-button move).
    /// Increased contrast takes it the rest of the way to black and white.
    static let ink = adaptive(
        light: UIColor(white: 0.07, alpha: 1),
        lightHighContrast: .black,
        dark: .white,
        darkHighContrast: .white
    )

    /// Text/icon colour on an `ink` fill. Mirrors `ink` so the pair always
    /// resolves to opposite ends of the same axis.
    static let onInk = adaptive(
        light: .white,
        lightHighContrast: .white,
        dark: UIColor(white: 0.07, alpha: 1),
        darkHighContrast: .black
    )
}

// MARK: - Scripture type

extension Font {
    /// Scripture and hero titles are set in a serif (New York), matching how
    /// YouVersion renders verse content; UI chrome stays on the default sans.
    static func scripture(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
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
        // White card on warm paper, lifted by a whisper of shadow (YouVersion
        // separates cards with soft elevation, not borders). The shadow is
        // near-invisible in dark mode, where the lighter fill does the work.
        content
            .background(fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
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

// MARK: - Pill CTA

/// YouVersion-style capsule CTA. `.primary` is the single loud action on a
/// screen (solid ink fill); `.tonal` is its quiet sibling for replay/secondary
/// actions. Same press behaviour as `PressableCardStyle`.
struct PillButtonStyle: ButtonStyle {
    enum Emphasis { case primary, tonal }
    var emphasis: Emphasis = .primary

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, emphasis: emphasis)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let emphasis: PillButtonStyle.Emphasis
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(emphasis == .primary ? Theme.onInk : .primary)
            .padding(.vertical, 15)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(maxWidth: .infinity)
            .background(fill, in: .capsule)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(configuration.isPressed ? nil : .spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }

    private var fill: Color {
        emphasis == .primary ? Theme.ink : Color.primary.opacity(0.08)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillProminent: PillButtonStyle { PillButtonStyle(emphasis: .primary) }
    static var pillTonal: PillButtonStyle { PillButtonStyle(emphasis: .tonal) }
}

extension View {
    /// Applies the standard card treatment: a rounded grouped-background fill.
    func elevatedCard(fill: Color = Theme.surface, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(ElevatedCard(fill: fill, cornerRadius: cornerRadius))
    }

    /// The shared eyebrow/kicker label style used above every card heading.
    /// Muted grey by default (as on YouVersion's "VERSE OF THE DAY" label) so
    /// the scarlet stays reserved for interactive and identity moments.
    func kicker(_ color: Color = Color.secondary) -> some View {
        modifier(Kicker(color: color))
    }
}

/// Letterspaced uppercase eyebrow. The letterspacing is deliberate — it is what
/// makes a 12pt uppercase run read as a label rather than shouting — but it is
/// set as a scaled metric rather than a flat point value: `tracking` takes
/// absolute points, so a fixed 1.0 stayed 1.0 while the caption grew to 30pt
/// and the letterspacing quietly tightened away to nothing at the sizes that
/// need it most.
private struct Kicker: ViewModifier {
    let color: Color

    @ScaledMetric(relativeTo: .caption) private var tracking: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(tracking)
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

    static func textColor(isSelected: Bool, isPencil: Bool = false) -> Color {
        if isPencil { return isSelected ? .white.opacity(0.8) : .secondary }
        return isSelected ? .white : .primary
    }
}
