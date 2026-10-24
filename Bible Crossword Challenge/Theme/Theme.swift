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

    /// Feature cards — the one solid-colour card a screen leads with (Today's
    /// puzzle, a Journey, memory practice). Rounder than list cards so the two
    /// kinds read as different objects, not one card at two sizes.
    static let featureCornerRadius: CGFloat = 28

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
        // `@Sendable`, so not main-actor isolated: SwiftUI resolves colours on
        // its async render thread too, and under Swift 6 an isolated provider
        // trapped there (EXC_BREAKPOINT in `dispatch_assert_queue`). It only
        // reads its captured `UIColor`s, which are Sendable.
        Color(uiColor: UIColor { @Sendable trait in
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

    /// The warm wash at the top of the Premium page, fading into the paper —
    /// the chip's gold, let down far enough to sit behind type.
    static let premiumWash = adaptive(
        light: UIColor(red: 0.953, green: 0.906, blue: 0.784, alpha: 1),          // #F3E7C8
        lightHighContrast: UIColor(red: 0.953, green: 0.906, blue: 0.784, alpha: 1),
        dark: UIColor(red: 0.169, green: 0.141, blue: 0.078, alpha: 1),           // #2B2414
        darkHighContrast: UIColor(red: 0.169, green: 0.141, blue: 0.078, alpha: 1)
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

    // MARK: Crossword grid

    /// The game screen's ground: the system's grouped grey, not the warm
    /// paper the rest of the app sits on. On paper, with beige rules and black
    /// blocks, the board read as a newspaper page rather than an app
    /// (2026-10-24); on the system grey the white squares read as tiles.
    static let gameCanvas = Color(.systemGroupedBackground)

    /// A block: a soft grey tile among the white ones (2026-10-24 design),
    /// where a printed crossword prints black. The board's shape still reads
    /// — a block is a tile of its own, a step down from the squares — without
    /// half the board being solid black. Increased contrast deepens it; in
    /// dark it sinks below the squares toward the black ground.
    static let gridBlock = adaptive(
        light: rgb(0xE1E1E6),
        lightHighContrast: rgb(0xAEAEB2),
        dark: rgb(0x141416),
        darkHighContrast: .black
    )

    // MARK: Game keyboard

    /// The bed the game's clue strip and keys sit on: a warm grey, so the
    /// entry area reads as the device's keyboard and the board above it as
    /// the page. Tried as the system keyboard's grey on 2026-10-24 and put
    /// back the same day at Sambulo's request.
    static let keyboardBed = adaptive(
        light: rgb(0xDCD8D2),
        lightHighContrast: rgb(0xC9C4BC),
        dark: rgb(0x1A1918),
        darkHighContrast: rgb(0x121110)
    )

    /// A letter key on the bed.
    static let keyFace = adaptive(
        light: .white,
        lightHighContrast: .white,
        dark: rgb(0x3A3836),
        darkHighContrast: rgb(0x4A4845)
    )

    /// The pencil and delete keys: a step off the letters, as the system
    /// keyboard sets its function keys.
    static let keyFaceAlt = adaptive(
        light: rgb(0xB8B2AA),
        lightHighContrast: rgb(0xA39C93),
        dark: rgb(0x2A2826),
        darkHighContrast: rgb(0x34322F)
    )

    // MARK: Feature-card fills
    //
    // Solid fills that carry white text: the puzzle leading Today, in its
    // billing's colour. Each is a darker cut of its `FeatureTint` so 15pt
    // white clears 4.5:1 — the system colours don't (blue 4.0:1, teal 2.6:1,
    // orange 2.2:1), and the hero's meta line is 15pt. Increased contrast
    // darkens them further. Light and dark match closely: the card is a lit
    // object on either paper, not a surface that should sink into the dark.

    /// The daily puzzle's hero — the brand blue, deepened.
    static let heroDaily = adaptive(
        light: rgb(0x0A6CD6),
        lightHighContrast: rgb(0x0757B0),
        dark: rgb(0x1C5FBF),
        darkHighContrast: rgb(0x154C99)
    )

    /// The Mini's hero — teal, deepened.
    static let heroMini = adaptive(
        light: rgb(0x1E7F90),
        lightHighContrast: rgb(0x166674),
        dark: rgb(0x1A6E7D),
        darkHighContrast: rgb(0x145863)
    )

    /// The Sunday Special's hero — orange, deepened to a rust.
    static let heroSunday = adaptive(
        light: rgb(0xB5560E),
        lightHighContrast: rgb(0x964609),
        dark: rgb(0xA24C0C),
        darkHighContrast: rgb(0x873F0A)
    )

    /// The completion screen's hero — a deeper blue than the daily's, so the
    /// solve reads as the same family as Today's card without repeating it.
    static let heroSolved = adaptive(
        light: rgb(0x0A4FA8),
        lightHighContrast: rgb(0x083E86),
        dark: rgb(0x0B3F86),
        darkHighContrast: rgb(0x08306A)
    )

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
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

    @Environment(\.isInCardGroup) private var isInCardGroup

    func body(content: Content) -> some View {
        // Inside a `CardGroup` the row gives its card up to the group's one,
        // keeping a rectangle to tap across — without a fill, the empty
        // space beside the text stops taking touches.
        if isInCardGroup {
            content.contentShape(.rect)
        } else {
            // White card on warm paper, separated by the fill alone — the way
            // the system's own grouped content sits flat on iOS 26, where the
            // floating Liquid Glass bars are the one layer that lifts. A 5%
            // shadow used to ride under every card; thirty of them side by side
            // on a wide window read as haze.
            content
                .background(fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

extension EnvironmentValues {
    /// True for a row inside a `CardGroup`, whose `.elevatedCard()` then
    /// draws nothing: the group draws one card around all its rows.
    @Entry var isInCardGroup = false
}

/// The padding of an icon-title-chevron row. On its own the row is a card and
/// keeps a card's 24pt; inside a `CardGroup` it's a list row, and 24pt above
/// and below made each one ~96pt tall — three cards fused together rather
/// than a list. 16pt brings a row to 76pt.
private struct CardRowPadding: ViewModifier {
    @Environment(\.isInCardGroup) private var isInCardGroup

    func body(content: Content) -> some View {
        // Inside a group, the system list's measure: a 16pt margin and 12pt
        // above and below, so a 36pt icon row lands near 60pt. It was 24 and
        // 16 — rows ran ~80pt and read as stacked cards, not a list.
        content
            .padding(.horizontal, isInCardGroup ? Theme.Spacing.m : Theme.Spacing.l)
            .padding(.vertical, isInCardGroup ? 12 : Theme.Spacing.l)
    }
}

extension View {
    /// See `CardRowPadding`.
    func cardRowPadding() -> some View {
        modifier(CardRowPadding())
    }
}

/// Rows that each draw their own card, shown as one card with dividers — the
/// inset-grouped list shape, for things that are one list rather than
/// separate headlines. Rows that render nothing take no divider with them.
struct CardGroup<Content: View>: View {
    /// The inset for rows led by a `RowIcon`: past the margin, the icon and
    /// the gap, so dividers start under the text as a system list's do.
    static var iconRowInset: CGFloat { Theme.Spacing.m + RowIcon.side + Theme.Spacing.m }

    /// Where the dividers start: under the row's text rather than its icon.
    var dividerInset: CGFloat = Theme.Spacing.l
    @ViewBuilder let content: Content

    var body: some View {
        // The flag goes on the content before it's split into rows. Set on
        // each resolved row instead, it reached rows inside a button or link
        // (whose labels resolve late) but not a plain row — a Journey's
        // not-yet-open steps kept their standalone 24pt padding.
        Group(subviews: content.environment(\.isInCardGroup, true)) { rows in
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, dividerInset)
                        }
                        row
                    }
                }
                // Outside the flag, so the group's own card is drawn.
                .elevatedCard()
            }
        }
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
/// actions. The `onColor` pair is the same two weights for a feature card's
/// solid fill, where ink would sink into the colour: a white pill, and a
/// translucent white one. Same press behaviour as `PressableCardStyle`.
struct PillButtonStyle: ButtonStyle {
    enum Emphasis { case primary, tonal, onColor, onColorTonal }
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
            .foregroundStyle(foreground)
            .padding(.vertical, 15)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(maxWidth: .infinity)
            .background(fill, in: .capsule)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(configuration.isPressed ? nil : .spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch emphasis {
        case .primary: Theme.onInk
        case .tonal: .primary
        // Fixed near-black, not `ink`: the pill is white in both appearances,
        // so its label must not flip to white in dark mode.
        case .onColor: Color(white: 0.07)
        case .onColorTonal: .white
        }
    }

    private var fill: Color {
        switch emphasis {
        case .primary: Theme.ink
        case .tonal: Color.primary.opacity(0.08)
        case .onColor: .white
        case .onColorTonal: .white.opacity(0.2)
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillProminent: PillButtonStyle { PillButtonStyle(emphasis: .primary) }
    static var pillTonal: PillButtonStyle { PillButtonStyle(emphasis: .tonal) }
    /// The loud action on a feature card's solid fill.
    static var pillOnColor: PillButtonStyle { PillButtonStyle(emphasis: .onColor) }
    /// The quiet action on a feature card's solid fill.
    static var pillOnColorTonal: PillButtonStyle { PillButtonStyle(emphasis: .onColorTonal) }
}

extension View {
    /// Applies the standard card treatment: a rounded grouped-background fill.
    func elevatedCard(fill: Color = Theme.surface, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(ElevatedCard(fill: fill, cornerRadius: cornerRadius))
    }

    /// A section's title on a feed screen — "Keep going", "Packs ›": bold,
    /// sentence case, full ink, the way iOS 26's own shelves (App Store,
    /// Music) title theirs. The uppercase tracked kicker is for labels inside
    /// a card, not for naming a stretch of the page.
    func sectionHeader() -> some View {
        self
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
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
    /// An empty square. One step up in dark (the tertiary grouped grey):
    /// on the secondary grey, a square beside a near-black block was too
    /// close in value for the board's shape to read.
    static let empty = Color(uiColor: UIColor { @Sendable trait in  // nonisolated: see `Theme.adaptive`
        (trait.userInterfaceStyle == .dark
            ? UIColor.tertiarySystemGroupedBackground
            : UIColor.secondarySystemGroupedBackground
        ).resolvedColor(with: trait)
    })

    /// Active-word tint. Stronger in dark mode, where an 0.18 accent wash over
    /// near-black cells is barely distinguishable from the empty fill.
    private static let inWord = Color(uiColor: UIColor { @Sendable trait in  // nonisolated: see `Theme.adaptive`
        .tintColor.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.30 : 0.18)
    })

    /// A wrong square's wash, over its normal fill, with the letter in
    /// `error` (2026-10-24). On tiles the square is the unit, so the square
    /// carries the state, as blue carries the word; the red rule under each
    /// letter it replaced read as form-field errors across the board. Light
    /// enough not to be a red block: an earlier pink fill, on the flat printed
    /// board and as the only cue, was dropped as the loudest thing on screen.
    static let errorWash = Color(uiColor: UIColor { @Sendable trait in  // nonisolated: see `Theme.adaptive`
        .systemRed.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.24 : 0.12)
    })

    /// Selected-cell tint: a deeper step of the active-word wash, not a solid
    /// block. At 0.85 the cell was the loudest thing on the screen and turned
    /// its letter white; the 2pt border in CellView now carries the focus.
    private static let selected = Color(uiColor: UIColor { @Sendable trait in  // nonisolated: see `Theme.adaptive`
        .tintColor.withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.55 : 0.38)
    })

    /// A wrong letter and its underline. The system red, which deepens under
    /// Increase Contrast and lightens for dark.
    static let error = Color(.systemRed)

    static func fill(isSelected: Bool, isInWord: Bool, isCorrect: Bool) -> Color {
        if isSelected { return selected }
        if isCorrect { return Color.green.opacity(0.18) }
        if isInWord { return inWord }
        return empty
    }

    /// Letters stay ink on every fill, the selected cell included, now that
    /// its tint is light enough to read black on.
    static func textColor(isPencil: Bool = false) -> Color {
        isPencil ? .secondary : .primary
    }
}
