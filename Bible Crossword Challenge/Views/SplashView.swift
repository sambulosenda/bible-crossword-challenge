//
//  SplashView.swift
//  Bible Crossword Challenge
//
//  Animated launch splash shown once per cold start. It opens on exactly the
//  flat blue of LaunchScreen.storyboard, so the OS → app handoff is seamless,
//  then tells the icon's story in about a second and a half: a lattice of empty
//  cells settles in, five of them snap together into a cross, light breaks
//  through from behind it, and the wordmark arrives. The splash then scales up
//  and fades, opening into the app rather than blinking away.
//
//  Everything here is drawn in SwiftUI so the mark shares the app's own tile
//  language (the same rounded squares as MiniCrossword and the real grid).
//

import SwiftUI

struct SplashView: View {
    /// Called after the exit fade completes so the host can remove the splash.
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // One flag per beat of the sequence; `run()` trips them in order.
    @State private var bloom = false      // background depth + faint lattice
    @State private var tiles = false      // the five white cells of the cross
    @State private var light = false      // gold burst behind the cross
    @State private var wordmark = false   // name lockup
    @State private var sweep = false      // specular shine across the cells
    @State private var leaving = false

    // MARK: Brand

    /// Must stay identical to LaunchScreen.storyboard's fill, or the handoff
    /// from the OS launch image to this view flashes.
    private static let base = Color(red: 0.21, green: 0.36, blue: 0.87)
    private static let highlight = Color(red: 0.36, green: 0.53, blue: 1.0)
    private static let deep = Color(red: 0.08, green: 0.16, blue: 0.55)
    private static let gold = Color(red: 0.99, green: 0.80, blue: 0.30)

    // MARK: Grid geometry

    private static let side: CGFloat = 44
    private static let gap: CGFloat = 7
    private static let span = 5                    // 5×5 lattice
    private static let pitch = side + gap
    private static let extent = CGFloat(span) * side + CGFloat(span - 1) * gap

    /// The cross, as cells of the lattice — the app icon's motif.
    /// Keyed by cell, valued by reveal order: centre first, then the upright,
    /// then the arms, so it draws as a cross rather than popping as a blob.
    private static let cross: [Cell: Int] = [
        Cell(2, 2): 0, Cell(2, 1): 1, Cell(2, 3): 2, Cell(1, 2): 3, Cell(3, 2): 4,
    ]

    private struct Cell: Hashable {
        let row: Int, col: Int
        init(_ row: Int, _ col: Int) { self.row = row; self.col = col }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            background
            VStack(spacing: 40) {
                mark
                wordmarkLockup
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        // Keeps the exit fade from letting the additive light layers escape the
        // group and flash against the app underneath.
        .compositingGroup()
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving && !reduceMotion ? 1.08 : 1)
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bible Crossword Challenge")
    }

    // MARK: Background

    /// Flat brand blue at rest; a light source blooms behind the mark and the
    /// corners sink, giving the icon's depth without a cut on the first frame.
    private var background: some View {
        ZStack {
            Self.base
            RadialGradient(colors: [Self.highlight.opacity(0.95), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 30, endRadius: 460)
                .opacity(bloom ? 1 : 0)
            RadialGradient(colors: [.clear, Self.deep.opacity(0.9)],
                           center: .center, startRadius: 210, endRadius: 640)
                .opacity(bloom ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    // MARK: Mark

    private var mark: some View {
        ZStack {
            radiance
            lattice
            crossTiles
        }
        .frame(width: Self.extent, height: Self.extent)
        .overlay { shine }
    }

    /// The empty cells the cross sits in, dissolved at the edges so the mark has
    /// no hard square border.
    private var lattice: some View {
        grid { cell in
            if Self.cross[cell] == nil {
                tile
                    .fill(.white.opacity(0.13))
                    .opacity(bloom ? 1 : 0)
                    .animation(reduceMotion
                               ? .easeOut(duration: 0.25)
                               : .easeOut(duration: 0.5).delay(Double(distance(cell)) * 0.05),
                               value: bloom)
            }
        }
        .mask {
            RadialGradient(colors: [.white, .white.opacity(0.15), .clear],
                           center: .center, startRadius: 30, endRadius: Self.extent * 0.62)
        }
    }

    /// The five solid cells. Each springs in on its own beat.
    private var crossTiles: some View {
        grid { cell in
            if let order = Self.cross[cell] {
                tile
                    // Not flat white: the tiles are shaded just enough to have a
                    // lit edge and a shadowed one, which also gives the shine
                    // below something to brighten — light on pure white is a
                    // no-op.
                    .fill(LinearGradient(colors: [.white, .white.opacity(0.86)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Self.deep.opacity(0.35), radius: 8, y: 3)
                    .opacity(tiles ? 1 : 0)
                    .scaleEffect(tiles || reduceMotion ? 1 : 0.4)
                    .animation(reduceMotion
                               ? .easeOut(duration: 0.25)
                               : .spring(duration: 0.5, bounce: 0.35).delay(Double(order) * 0.065),
                               value: tiles)
            }
        }
    }

    /// Gold burst behind the cross — the icon's rays, unrolled from the centre.
    /// Painted normally rather than additively: adding gold to brand blue just
    /// clips to white, and the whole point is that the light is warm. Rays stop
    /// short of the lattice edge so nothing spears the wordmark.
    private var radiance: some View {
        ZStack {
            // Wide, airy bloom. Additive out here on purpose: thinned-out gold
            // painted normally over blue goes tan, which reads as dirt.
            RadialGradient(colors: [Self.gold.opacity(0.40), Self.gold.opacity(0.10), .clear],
                           center: .center, startRadius: 20, endRadius: 165)
                .blendMode(.plusLighter)
                .blur(radius: 10)
            ForEach(0..<20, id: \.self) { i in
                ray(long: i.isMultiple(of: 2))
                    .rotationEffect(.degrees(Double(i) / 20 * 360))
            }
            .blur(radius: 2)
            // Warm core, kept tight around the cross so the tiles stay crisp.
            RadialGradient(colors: [.white.opacity(0.95), Self.gold.opacity(0.9),
                                    Self.gold.opacity(0.22), .clear],
                           center: .center, startRadius: 2, endRadius: 86)
                .blur(radius: 5)
        }
        .opacity(light ? 1 : 0)
        .scaleEffect(light || reduceMotion ? 1 : 0.55)
        .rotationEffect(.degrees(light || reduceMotion ? 0 : -14))
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.65), value: light)
    }

    private func ray(long: Bool) -> some View {
        let length: CGFloat = long ? 118 : 76
        return Capsule()
            .fill(LinearGradient(colors: [Self.gold.opacity(0), Self.gold.opacity(0.85)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: long ? 3.5 : 2.5, height: length)
            .offset(y: -length / 2)
    }

    /// A single pass of specular light across the white cells — the polish that
    /// makes them read as physical tiles rather than flat rectangles.
    @ViewBuilder private var shine: some View {
        if !reduceMotion {
            LinearGradient(colors: [.clear, .white.opacity(0.8), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 70, height: Self.extent * 2)
                .rotationEffect(.degrees(20))
                .offset(x: sweep ? Self.extent : -Self.extent)
                .blendMode(.plusLighter)
                .mask { grid { cell in if Self.cross[cell] != nil { tile.fill(.white) } } }
                .allowsHitTesting(false)
        }
    }

    // MARK: Wordmark

    private var wordmarkLockup: some View {
        VStack(spacing: 8) {
            Text("Bible Crossword")
                .font(.scripture(.title, weight: .bold))
                .foregroundStyle(.white)
            // Wider tracking than the app's standard kicker: a name lockup can
            // carry letterspacing that a screen label can't.
            Text("Challenge")
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .tracking(4)
                .foregroundStyle(.white.opacity(0.65))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .opacity(wordmark ? 1 : 0)
        .offset(y: wordmark || reduceMotion ? 0 : 14)
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.5), value: wordmark)
    }

    // MARK: Grid plumbing

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    /// Lays the 5×5 lattice out and hands each coordinate to `content`.
    private func grid<Content: View>(@ViewBuilder content: @escaping (Cell) -> Content) -> some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<Self.span, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<Self.span, id: \.self) { col in
                        content(Cell(row, col))
                            .frame(width: Self.side, height: Self.side)
                    }
                }
            }
        }
    }

    /// Chebyshev distance from the centre cell, for the lattice's outward fade.
    private func distance(_ cell: Cell) -> Int {
        max(abs(cell.row - 2), abs(cell.col - 2))
    }

    // MARK: Sequence

    private func run() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) {
                bloom = true; tiles = true; light = true; wordmark = true
            }
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.easeIn(duration: 0.3)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(300))
            onFinished()
            return
        }

        withAnimation(.easeOut(duration: 0.7)) { bloom = true }
        try? await Task.sleep(for: .milliseconds(120))
        tiles = true                                   // per-tile springs stagger themselves
        try? await Task.sleep(for: .milliseconds(280))
        light = true
        try? await Task.sleep(for: .milliseconds(140))
        wordmark = true
        withAnimation(.easeInOut(duration: 0.9)) { sweep = true }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeIn(duration: 0.42)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(420))
        onFinished()
    }
}

#Preview {
    SplashView(onFinished: {})
}
