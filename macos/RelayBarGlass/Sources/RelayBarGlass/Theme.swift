import SwiftUI

// MARK: - Color helpers

private extension Color {
    /// Create a Color from 8-bit sRGB components (0–255) with optional opacity.
    init(r255: Double, g255: Double, b255: Double, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: r255 / 255.0,
            green: g255 / 255.0,
            blue: b255 / 255.0,
            opacity: opacity
        )
    }

    /// Create a Color from a 6-digit hex string (e.g. "#20202d").
    init(hex: String, opacity: Double = 1) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt64(s, radix: 16) ?? 0
        let r = Double((value & 0xFF0000) >> 16)
        let g = Double((value & 0x00FF00) >> 8)
        let b = Double(value & 0x0000FF)
        self.init(r255: r, g255: g, b255: b, opacity: opacity)
    }
}

// MARK: - Design tokens

/// Dark frosted-glass design system for the menu bar popover. The card is
/// recolored per-provider by an accent color (see `model.selected.accent`);
/// these tokens are the neutral chrome the accent sits on top of.
enum GlassTheme {

    // Palette — dark glass. Text is white at decreasing opacities; lines/tracks
    // are barely-there white washes over the dark panel.
    static let ink: Color       = Color.white                          // --ink (primary text)
    static let muted: Color     = Color.white.opacity(0.55)            // --muted (secondary text)
    static let textFaint: Color = Color.white.opacity(0.40)           // fainter captions
    static let line: Color      = Color.white.opacity(0.10)           // --line (hairline dividers)
    static let selected: Color  = Color.white                          // --selected (generic active)
    static let teal: Color      = Color(hex: "#53bfa7")                // --teal (unused here)
    static let orange: Color    = Color(hex: "#d1875c")                // --orange (unused here)
    static let track: Color     = Color.white.opacity(0.08)           // --track (bar backgrounds)
    static let track2: Color    = Color.white.opacity(0.14)           // --track-2
    static let panel: Color     = Color(r255: 24, g255: 26, b255: 31, opacity: 0.78) // --panel
    static let spend: Color     = Color(hex: "#4a90e8")                // spend accent (fallback)

    // Typography.
    static let h1: Font           = .system(size: 20,   weight: .semibold)
    static let sectionTitle: Font = .system(size: 15,   weight: .bold)
    static let label: Font        = .system(size: 14,   weight: .semibold)
    static let body: Font         = .system(size: 12.5, weight: .regular)
    static let caption: Font      = .system(size: 11,   weight: .regular)
    static let mono: Font         = .system(size: 12,   weight: .regular).monospacedDigit()
}

// MARK: - Popover background

/// Dark frosted glass for the whole popover: real `.ultraThinMaterial` (dark)
/// vibrancy under a dark vertical gradient tint, an inset top white highlight,
/// a faint white hairline rim, and a big soft drop shadow so the panel floats
/// above the desktop. Matches the reference:
/// `linear-gradient(180deg, rgba(30,32,38,.72), rgba(20,22,27,.78))`,
/// `backdrop-filter: blur(40px) saturate(160%)`, radius 22.
struct GlassBackground: View {
    private let cornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            // Base translucent material — the real backdrop blur (dark vibrancy).
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            // Dark vertical gradient tint that gives the glass its charcoal body.
            LinearGradient(
                colors: [
                    Color(r255: 30, g255: 32, b255: 38, opacity: 0.72),
                    Color(r255: 20, g255: 22, b255: 27, opacity: 0.78),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Inset top highlight — a soft white sheen along the upper edge.
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        // Fill the whole window edge-to-edge (square). The MenuBarExtra window
        // applies its own rounded mask, so we must NOT round/clip here — a
        // smaller inner rounding leaves the window's square dark corner poking out.
        .ignoresSafeArea()
    }
}

// MARK: - Glass card

/// A dark translucent "glass card" tile matching the reference `.glass-card` style:
/// a very faint white fill over the dark panel with a thin white hairline border.
private struct GlassCardModifier: ViewModifier {
    private let cornerRadius: CGFloat = 13

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            // 1px white hairline border.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Dark glass tile: fill white .06, 1px border white .08, cornerRadius ~13,
    /// ~14pt padding. Must be callable as `.glassCard()`.
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
