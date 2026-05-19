import SwiftUI

enum AppTheme {
    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.055, green: 0.065, blue: 0.085, opacity: 1),
                    Color(.sRGB, red: 0.075, green: 0.080, blue: 0.110, opacity: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.965, green: 0.975, blue: 0.985, opacity: 1),
                Color(.sRGB, red: 0.925, green: 0.945, blue: 0.965, opacity: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func sidebarBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.090, green: 0.100, blue: 0.125, opacity: 1),
                    Color(.sRGB, red: 0.055, green: 0.060, blue: 0.085, opacity: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.985, green: 0.990, blue: 0.995, opacity: 1),
                Color(.sRGB, red: 0.925, green: 0.940, blue: 0.960, opacity: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.82)
    }

    static func elevatedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.94)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.70)
    }

    static func subtleFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    static func hoverFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.070) : Color.black.opacity(0.055)
    }

    static func stroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.090) : Color.black.opacity(0.085)
    }

    static func faintStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.060) : Color.black.opacity(0.060)
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.07)
    }

    /// Connect button fill (flat, matches cards).
    static func connectFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.accentColor.opacity(0.88) : Color.accentColor
    }

    static func connectShadow(for scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .dark ? 0.35 : 0.22)
    }
}
