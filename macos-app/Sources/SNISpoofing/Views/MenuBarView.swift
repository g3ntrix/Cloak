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
        VStack(spacing: 12) {
            header
            statusRow
            if app.status.isRunning {
                speedRow
                Divider().opacity(0.4)
            }
            profilePicker
            Divider().opacity(0.4)
            actionsRow
        }
        .padding(14)
        .frame(width: width)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(.sRGB, red: 0.08, green: 0.09, blue: 0.13, opacity: 1),
                       Color(.sRGB, red: 0.05, green: 0.06, blue: 0.09, opacity: 1)]
                    : [Color(.sRGB, red: 0.985, green: 0.990, blue: 0.998, opacity: 1),
                       Color(.sRGB, red: 0.94, green: 0.95, blue: 0.97, opacity: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            CloakBrandImage(size: 26, cornerRadius: 7)
            Text("Cloak")
                .font(.system(size: 14, weight: .bold, design: .rounded))
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

    private var statusRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.activeProfile?.name ?? "No profile")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
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
                .foregroundColor(app.status.isRunning ? .white : Color.primary.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(app.status.isRunning
                                   ? Color.red.opacity(0.88)
                                   : AppTheme.connectFill(for: colorScheme))
                )
            }
            .buttonStyle(.plain)
            .disabled(app.status.isTransitioning || (app.activeProfile == nil && !app.status.isRunning))
            .opacity((app.activeProfile == nil && !app.status.isRunning) ? 0.45 : 1)
        }
    }

    private var speedRow: some View {
        HStack(spacing: 12) {
            speedTag(symbol: "arrow.down", value: app.downloadBytesPerSec, color: .blue)
            speedTag(symbol: "arrow.up",   value: app.uploadBytesPerSec,   color: .purple)
            Spacer()
            Text(formatBytes(app.sessionBytesDown + app.sessionBytesUp))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func speedTag(symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(rate(value))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var profilePicker: some View {
        if app.profiles.isEmpty {
            Text("No profiles imported. Open Cloak to add one.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Text("Profile")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
                    HStack(spacing: 4) {
                        Text(app.activeProfile?.name ?? "Select…")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                let mainWindows = NSApp.windows.filter { $0.canBecomeMain && !$0.isExcludedFromWindowsMenu }
                if let existing = mainWindows.first {
                    existing.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: SNISpoofingApp.mainWindowID)
                }
            } label: {
                Label("Open", systemImage: "macwindow")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
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

    private var subtitle: String {
        switch app.status {
        case .running:
            if let ip = app.egressIP { return "via \(ip)" }
            return "Connected"
        case .stopped:
            return "Click Connect to route through Cloak."
        case .starting: return "Bringing up the bridge…"
        case .stopping: return "Tearing down…"
        case .error(let msg): return msg
        }
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
