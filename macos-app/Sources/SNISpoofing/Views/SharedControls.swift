import SwiftUI

/// Segmented Local vs LAN binding for the SOCKS listener host.
struct ListenScopeToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var exposesToLAN: Bool

    var body: some View {
        HStack(spacing: 0) {
            scopeSegment(
                title: "Local",
                subtitle: "This Mac",
                icon: "laptopcomputer",
                selected: !exposesToLAN
            ) { exposesToLAN = false }

            scopeSegment(
                title: "LAN",
                subtitle: "All devices",
                icon: "wifi.router",
                selected: exposesToLAN
            ) { exposesToLAN = true }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.subtleFill(for: colorScheme))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1))
        )
    }

    private func scopeSegment(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16) : .clear)
            )
            .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// System / Light / Dark picker that matches Cloak's card styling.
struct AppearancePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var mode: AppSettings.AppearanceMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppSettings.AppearanceMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: mode == option ? .semibold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(mode == option
                                      ? Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.14)
                                      : AppTheme.subtleFill(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(mode == option ? Color.accentColor.opacity(0.5) : AppTheme.faintStroke(for: colorScheme),
                                        lineWidth: 1)
                        )
                        .foregroundStyle(mode == option ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
