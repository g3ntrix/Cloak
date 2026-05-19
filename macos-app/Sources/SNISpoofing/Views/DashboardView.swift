import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var uptime: String = "0s"
    @State private var timer: Timer?
    @State private var lanIPv4: String?
    @State private var copiedLan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                meterCard
                if let lan = lanIPv4 {
                    HStack(alignment: .top, spacing: 14) {
                        lanCard(lan).frame(maxWidth: .infinity, alignment: .top)
                        SystemProxyCard().frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    SystemProxyCard()
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startTimer()
            refreshLanIP()
        }
        .onDisappear { stopTimer() }
        .onChange(of: app.startedAt) { _ in tick() }
    }

    // MARK: - Status card

    private var statusCard: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                StatusOrb(status: app.status)
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.status.label)
                        .font(.system(size: 19, weight: .semibold))
                        .lineLimit(1)
                    Text(secondaryLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    ipRow
                }
                Spacer(minLength: 8)
                PowerButton(isRunning: app.status.isRunning,
                            isBusy: app.status.isTransitioning) {
                    Task {
                        if app.status.isRunning { await app.stop() }
                        else { await app.start() }
                    }
                }
                .disabled(app.activeProfile == nil && !app.status.isRunning)
                .opacity(app.activeProfile == nil && !app.status.isRunning ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private var ipRow: some View {
        HStack(spacing: 8) {
            Image(systemName: app.status.isRunning ? "globe.americas.fill" : "network")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(app.status.isRunning ? .mint : .blue)
            if let ip = app.status.isRunning ? app.egressIP : app.directIP {
                Text(verbatim: ip)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                if let cc = app.status.isRunning ? app.egressCountry : app.directCountry, !cc.isEmpty {
                    Text(countryLine(code: cc))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if let msg = app.status.isRunning ? app.egressLookupMessage : app.directLookupMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Resolving…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Button {
                app.status.isRunning ? app.refreshEgressNow() : app.refreshDirectIP()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Refresh IP")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Compact bandwidth meter (one card, one row)

    private var meterCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Text(app.status.isRunning ? "This session" : "Activity")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if app.status.isRunning {
                        Text(uptime)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .center, spacing: 18) {
                    speedColumn(
                        icon: "arrow.down",
                        title: "Down",
                        speed: app.downloadBytesPerSec,
                        total: app.sessionBytesDown,
                        tint: .blue
                    )
                    Divider().frame(height: 36)
                    speedColumn(
                        icon: "arrow.up",
                        title: "Up",
                        speed: app.uploadBytesPerSec,
                        total: app.sessionBytesUp,
                        tint: .purple
                    )
                    Divider().frame(height: 36)
                    totalColumn
                }
                Sparkbar(value: app.downloadBytesPerSec, peak: peakHint, tint: .blue)
                    .frame(height: 4)
            }
        }
    }

    private func speedColumn(icon: String, title: String, speed: Double, total: UInt64, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(rate(speed))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("\(title) · \(formatBytes(total))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalColumn: some View {
        HStack(spacing: 8) {
            Image(systemName: "sum")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(formatBytes(app.sessionBytesDown + app.sessionBytesUp))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Total")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Roughly: where to anchor the sparkbar's "full" mark.
    private var peakHint: Double {
        max(app.downloadBytesPerSec, app.uploadBytesPerSec, 64 * 1024)  // ~512 kbps floor so we don't draw a full bar at idle
    }

    // MARK: - LAN IP

    private func lanCard(_ ip: String) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 17))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LAN address")
                        .font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(ip):\(app.settings.listenPort)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Text(bindsAllInterfaces
                         ? "Other devices on your network can use this SOCKS endpoint."
                         : "Enable LAN in Settings to share the proxy with other devices.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString("\(ip):\(app.settings.listenPort)", forType: .string)
                    withAnimation { copiedLan = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copiedLan = false }
                    }
                } label: {
                    Image(systemName: copiedLan ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy address")
            }
        }
    }

    private var bindsAllInterfaces: Bool {
        let h = app.settings.listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return h == "0.0.0.0" || h == "*"
    }

    // MARK: - Helpers

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
        tick()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let started = app.startedAt else {
            uptime = "0s"
            return
        }
        let dt = Int(Date().timeIntervalSince(started))
        let h = dt / 3600, m = (dt % 3600) / 60, s = dt % 60
        uptime = h > 0 ? String(format: "%dh %02dm", h, m)
              : m > 0 ? String(format: "%dm %02ds", m, s)
                      : String(format: "%ds", s)
    }

    private func refreshLanIP() {
        lanIPv4 = LanAddress.primaryIPv4String()
    }

    private var secondaryLabel: String {
        switch app.status {
        case .stopped:
            return app.activeProfile == nil
                ? "No profile selected. Import or pick one from Profiles."
                : "Profile: \(app.activeProfile?.name ?? "none")"
        case .running:
            return "Profile: \(app.activeProfile?.name ?? "none")"
        case .starting: return "Bringing up the bridge and Xray…"
        case .stopping: return "Tearing down."
        case .error(let msg): return msg
        }
    }

    private func countryLine(code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 2 else { return trimmed }
        return trimmed.uppercased()
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

// MARK: - Building blocks

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cardFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 14, y: 6)
            )
    }
}

struct StatusOrb: View {
    let status: AppState.Status
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.22)).frame(width: 46, height: 46)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(status.isRunning ? 1 : 0.5)
                .animation(status.isRunning
                           ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                           : .default, value: pulse)
            Circle().fill(color).frame(width: 15, height: 15)
                .shadow(color: color.opacity(0.6), radius: 8)
        }
        .onAppear { pulse = true }
    }
    private var color: Color {
        switch status {
        case .stopped: return .gray
        case .starting, .stopping: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }
}

struct PowerButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let isRunning: Bool
    let isBusy: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(isRunning ? .white : .primary)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "power")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(isRunning ? "Disconnect" : "Connect")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isRunning ? .white : Color.primary.opacity(0.9))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isRunning
                          ? Color.red.opacity(0.88)
                          : AppTheme.connectFill(for: colorScheme))
                    .shadow(color: isRunning
                            ? Color.red.opacity(hover ? 0.35 : 0.2)
                            : AppTheme.connectShadow(for: colorScheme),
                            radius: hover ? 10 : 6, y: 3)
            )
            .scaleEffect(hover ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hover = $0 }
    }
}

/// Single-line activity bar that fills proportionally to current vs peak.
private struct Sparkbar: View {
    @Environment(\.colorScheme) private var colorScheme
    let value: Double
    let peak: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.subtleFill(for: colorScheme))
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(geo.size.width, geo.size.width * filled)))
                    .animation(.easeOut(duration: 0.4), value: filled)
            }
        }
    }

    private var filled: CGFloat {
        guard peak > 0 else { return 0 }
        return CGFloat(min(1.0, value / peak))
    }
}

struct SystemProxyCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "switch.2")
                    .font(.system(size: 17))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("System proxy")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { app.settings.useSystemProxy },
                            set: {
                                app.settings.useSystemProxy = $0
                                app.saveSettings()
                                Task { await app.reconnectIfRunning() }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    Text(app.settings.useSystemProxy
                         ? "On Connect, macOS routes all apps through Cloak's local SOCKS listener."
                         : "Off. Apps must point at the local SOCKS endpoint manually.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
