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
                Color(.sRGB, red: 0.915, green: 0.930, blue: 0.948, opacity: 1),
                Color(.sRGB, red: 0.855, green: 0.878, blue: 0.905, opacity: 1)
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
                Color(.sRGB, red: 0.945, green: 0.955, blue: 0.970, opacity: 1),
                Color(.sRGB, red: 0.870, green: 0.890, blue: 0.915, opacity: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.045) : Color(.sRGB, red: 0.975, green: 0.980, blue: 0.988, opacity: 0.92)
    }

    static func elevatedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : Color(.sRGB, red: 0.990, green: 0.992, blue: 0.996, opacity: 0.96)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.24) : Color(.sRGB, red: 0.925, green: 0.938, blue: 0.955, opacity: 0.92)
    }

    static func subtleFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.065)
    }

    static func hoverFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.070) : Color.black.opacity(0.075)
    }

    static func stroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.090) : Color.black.opacity(0.135)
    }

    static func faintStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.060) : Color.black.opacity(0.095)
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.10) : Color.black.opacity(0.115)
    }

    /// Connect button fill (flat, matches cards).
    static func connectFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.accentColor.opacity(0.88) : Color.accentColor.opacity(0.92)
    }

    static func connectShadow(for scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .dark ? 0.35 : 0.22)
    }
}
