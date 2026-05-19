import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var uptime: String = "0s"
    @State private var timer: Timer?
    @State private var lanIPv4: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    HStack(spacing: 14) {
                        StatusOrb(status: app.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.status.label)
                                .font(.system(size: 18, weight: .semibold))
                                .lineLimit(1)
                            Text(secondaryLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
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

                if app.status.isRunning {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Cloak traffic", systemImage: "waveform.path.ecg")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.cyan)
                                Spacer()
                                Text("Xray inbounds only")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [.init(.flexible(), spacing: 10),
                                                .init(.flexible(), spacing: 10),
                                                .init(.flexible(), spacing: 10)], spacing: 10) {
                                StatTile(icon: "arrow.down.circle", title: "Down now", value: rate(app.downloadBytesPerSec), tint: .blue)
                                StatTile(icon: "arrow.up.circle", title: "Up now", value: rate(app.uploadBytesPerSec), tint: .purple)
                                StatTile(icon: "clock", title: "Connected", value: uptime, tint: .green)
                                StatTile(icon: "arrow.down.to.line", title: "Downloaded", value: formatBytes(app.sessionBytesDown), tint: .cyan)
                                StatTile(icon: "arrow.up.to.line", title: "Uploaded", value: formatBytes(app.sessionBytesUp), tint: .orange)
                                StatTile(icon: "sum", title: "Total", value: formatBytes(app.sessionBytesDown + app.sessionBytesUp), tint: .mint)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "network")
                                .font(.system(size: 17))
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Proxy endpoint")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(verbatim: "\(app.settings.listenHost):\(app.settings.listenPort)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)
                                if bindsAllInterfaces, let lan = lanIPv4 {
                                    Text(verbatim: "\(lan):\(app.settings.listenPort) on this LAN")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.cyan)
                                        .textSelection(.enabled)
                                }
                                Text(proxyHint)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: app.status.isRunning ? "globe" : "wifi")
                                .font(.system(size: 17))
                                .foregroundStyle(app.status.isRunning ? .mint : .blue)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(app.status.isRunning ? "VPN egress" : "Direct internet")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Button { app.status.isRunning ? app.refreshEgressNow() : app.refreshDirectIP() } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Refresh")
                                }
                                if let ip = app.status.isRunning ? app.egressIP : app.directIP {
                                    Text(verbatim: ip)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                } else if let msg = app.status.isRunning ? app.egressLookupMessage : app.directLookupMessage {
                                    Text(msg)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                } else {
                                    Text(verbatim: "—").foregroundStyle(.secondary)
                                }
                                if let cc = app.status.isRunning ? app.egressCountry : app.directCountry, !cc.isEmpty {
                                    Text(countryLine(code: cc))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                HStack(alignment: .top, spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            if let p = app.activeProfile {
                                Label("Active profile", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.green)
                                Text(p.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                Text(verbatim: "\(p.kind.display) · \(p.server):\(p.serverPort)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Label("No active profile", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.yellow)
                                Text("Import a profile in Profiles, then come back here to connect.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    SystemProxyCard()
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startTimer()
            refreshLanIP()
        }
        .onChange(of: app.settings.listenHost) { _ in refreshLanIP() }
        .onDisappear { timer?.invalidate() }
    }

    private var bindsAllInterfaces: Bool {
        let h = app.settings.listenHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return h == "0.0.0.0" || h == "*"
    }

    private func refreshLanIP() {
        lanIPv4 = LanAddress.primaryIPv4String()
    }

    private var proxyHint: String {
        app.status.isRunning
            ? "Apps using this proxy are routed through Cloak."
            : "Set your browser or system proxy here before connecting."
    }

    private var secondaryLabel: String {
        if case .running = app.status, let started = app.startedAt {
            return "Up for \(format(interval: Date().timeIntervalSince(started)))"
        }
        if app.activeProfile == nil { return "Import a profile in the Profiles tab to get started." }
        return "Ready to connect."
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if let s = app.startedAt {
                    uptime = format(interval: Date().timeIntervalSince(s))
                }
            }
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

    private func format(interval: TimeInterval) -> String {
        let t = Int(interval)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.cardFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 14, y: 6)
            )
    }
}

private struct StatTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.subtleFill(for: colorScheme))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.faintStroke(for: colorScheme)))
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
    var color: Color {
        switch status {
        case .running: return .green
        case .starting, .stopping: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }
}

struct PowerButton: View {
    let isRunning: Bool
    let isBusy: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(isRunning ? "Stop" : "Start")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isRunning
                                ? [Color.red.opacity(0.85), Color.pink.opacity(0.85)]
                                : [Color.accentColor, .purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: (isRunning ? Color.red : Color.accentColor).opacity(hover ? 0.5 : 0.25),
                            radius: hover ? 14 : 8, y: 4)
            )
            .scaleEffect(hover ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hover = $0 }
    }
}

struct SystemProxyCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
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
                         ? "Cloak flips the macOS SOCKS proxy to its local listener on connect, so every app routes through it automatically."
                         : "System proxy is off. Apps must opt in to the local SOCKS endpoint manually.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
