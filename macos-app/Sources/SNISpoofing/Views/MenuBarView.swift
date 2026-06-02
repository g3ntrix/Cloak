import SwiftUI
import AppKit

/// Compact popover shown when the user clicks Cloak's menu-bar icon.
/// Mirrors the dashboard's core controls: status, connect/disconnect, profile
/// switch, live throughput, plus shortcuts to open the main window or quit.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    private let width: CGFloat = 280

    var body: some View {
        VStack(spacing: 8) {
            header
            connectionPanel
            if app.status.isRunning {
                speedRow
            }
            actionsRow
        }
        .padding(10)
        .frame(width: width)
        .background(
            AppTheme.sidebarBackground(for: colorScheme)
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            CloakBrandImage(size: 24, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cloak")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                Text(app.settings.connectionMode.rawValue.capitalized)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(shortStatus)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(statusColor.opacity(0.16)))
        .foregroundStyle(statusColor)
    }

    private var connectionPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            profileControl
            Button {
                Task {
                    if app.status.isRunning { await app.stop() }
                    else { await app.start() }
                }
            } label: {
                HStack(spacing: 6) {
                    if app.status.isTransitioning {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Image(systemName: app.status.isRunning ? "stop.fill" : "power")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(app.status.isRunning ? "Stop" : "Connect")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(width: 92, height: 32)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(app.status.isRunning
                              ? Color.red.opacity(0.88)
                              : AppTheme.connectFill(for: colorScheme))
                        .shadow(color: app.status.isRunning
                                ? Color.red.opacity(0.20)
                                : AppTheme.connectShadow(for: colorScheme),
                                radius: 6, y: 3)
                )
            }
            .buttonStyle(.plain)
            .disabled(app.status.isTransitioning || (app.activeProfile == nil && !app.status.isRunning))
            .opacity((app.activeProfile == nil && !app.status.isRunning) ? 0.45 : 1)
        }
        .padding(10)
        .background(panelBackground)
    }

    @ViewBuilder
    private var profileControl: some View {
        if app.profiles.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("None")
                        .font(.system(size: 12.5, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(app.activeProfile?.name ?? "Select profile")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                Menu {
                    ForEach(app.profiles) { p in
                        Button {
                            app.setActive(p.id)
                            Task { await app.reconnectIfRunning() }
                        } label: {
                            HStack {
                                Text(p.name)
                                if app.settings.activeProfileID == p.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppTheme.controlFill(for: colorScheme))
                        )
                }
                .menuStyle(.borderlessButton)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var speedRow: some View {
        HStack(spacing: 6) {
            speedTag(title: "Down", symbol: "arrow.down", value: app.downloadBytesPerSec, color: .blue)
            speedTag(title: "Up", symbol: "arrow.up", value: app.uploadBytesPerSec, color: .purple)
            speedTag(title: "Total", symbol: "sum", value: Double(app.sessionBytesDown + app.sessionBytesUp), color: .mint, isTotal: true)
        }
    }

    private func speedTag(title: String, symbol: String, value: Double, color: Color, isTotal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(isTotal ? formatBytes(UInt64(value)) : rate(value))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(panelBackground)
    }

    private var actionsRow: some View {
        HStack(spacing: 0) {
            footerRow(label: "Open App", icon: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                let mainWindows = NSApp.windows.filter { $0.canBecomeMain && !$0.isExcludedFromWindowsMenu }
                if let existing = mainWindows.first {
                    existing.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: SNISpoofingApp.mainWindowID)
                }
            }
            Divider().frame(height: 14)
            footerRow(label: "Quit", icon: "power", tint: .red) {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 1)
        .background(panelBackground)
    }

    private func footerRow(label: String, icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        HoverableFooterButton(label: label, icon: icon, tint: tint, action: action)
    }

    // MARK: - Helpers

    private var shortStatus: String {
        switch app.status {
        case .stopped: return "Off"
        case .starting: return "…"
        case .running: return "On"
        case .stopping: return "…"
        case .error: return "Error"
        }
    }

    private var statusColor: Color {
        switch app.status {
        case .stopped: return .gray
        case .starting, .stopping: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppTheme.elevatedFill(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.faintStroke(for: colorScheme))
            )
    }

    private func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1_000 { return "0 KB/s" }
        if bytesPerSec < 1_000_000 { return String(format: "%.0f KB/s", bytesPerSec / 1_000) }
        if bytesPerSec < 1_000_000_000 { return String(format: "%.1f MB/s", bytesPerSec / 1_000_000) }
        return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
    }

    private func formatBytes(_ n: UInt64) -> String {
        let d = Double(n)
        if d < 1_000 { return "\(n) B" }
        if d < 1_000_000 { return String(format: "%.1f KB", d / 1_000) }
        if d < 1_000_000_000 { return String(format: "%.2f MB", d / 1_000_000) }
        return String(format: "%.2f GB", d / 1_000_000_000)
    }
}

private struct HoverableFooterButton: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isHovered ? tint : (tint == .primary ? .secondary : tint))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
