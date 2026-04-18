import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var uptime: String = "0s"
    @State private var timer: Timer?
    @State private var lanIPv4: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Headline
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cloak")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(headline)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                // Primary control card (first)
                Card {
                    HStack {
                        StatusOrb(status: app.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.status.label)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)
                            Text(secondaryLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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

                Card {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "network")
                            .font(.system(size: 20))
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Local SOCKS proxy")
                                .font(.system(size: 12, weight: .semibold))
                            Text(verbatim: "\(app.settings.listenHost):\(app.settings.listenPort)")
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                            if bindsAllInterfaces, let lan = lanIPv4 {
                                Text(verbatim: "From another device on this network: \(lan):\(app.settings.listenPort)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.cyan)
                                    .textSelection(.enabled)
                            }
                            Text(proxyHint)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }

                TunModeCard()

                // Active profile (minimal — no technical fields)
                if let p = app.activeProfile {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Active profile", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.green)
                                Spacer()
                            }
                            Text(p.name)
                                .font(.system(size: 18, weight: .bold))
                                .lineLimit(1)

                            if app.status.isRunning {
                                LazyVGrid(columns: [.init(.flexible(), spacing: 12),
                                                    .init(.flexible(), spacing: 12),
                                                    .init(.flexible(), spacing: 12)], spacing: 12) {
                                    StatTile(icon: "clock", title: "Connected for", value: uptime, tint: .green)
                                    StatTile(icon: "arrow.down.circle", title: "Download", value: rate(app.downloadBytesPerSec), tint: .blue)
                                    StatTile(icon: "arrow.up.circle", title: "Upload", value: rate(app.uploadBytesPerSec), tint: .purple)
                                    StatTile(icon: "arrow.down.to.line", title: "Session ↓", value: formatBytes(app.sessionBytesDown), tint: .cyan)
                                    StatTile(icon: "arrow.up.to.line", title: "Session ↑", value: formatBytes(app.sessionBytesUp), tint: .orange)
                                    StatTile(icon: "sum", title: "Session total", value: formatBytes(app.sessionBytesDown + app.sessionBytesUp), tint: .mint)
                                }
                            }
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No active profile", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Open the Profiles tab and import a profile to get started.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Egress (shown only when connected)
                if app.status.isRunning {
                    Card {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "globe")
                                .font(.system(size: 22))
                                .foregroundStyle(.mint)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Your IP (through VPN)")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Button { app.refreshEgressNow() } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Refresh")
                                }
                                if let ip = app.egressIP {
                                    Text(ip)
                                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                    if let cc = app.egressCountry, !cc.isEmpty {
                                        Text(countryLine(code: cc))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                } else if let msg = app.egressLookupMessage {
                                    Text(msg).font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—").foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                } else {
                    Card {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "wifi")
                                .font(.system(size: 22))
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Your public IP")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Button { app.refreshDirectIP() } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Refresh")
                                }
                                if let ip = app.directIP {
                                    Text(verbatim: ip)
                                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                    if let cc = app.directCountry, !cc.isEmpty {
                                        Text(countryLine(code: cc))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                } else if let msg = app.directLookupMessage {
                                    Text(msg).font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(verbatim: "—").foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
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

    private var headline: String {
        app.status.isRunning
            ? "Your internet is protected."
            : "Click Start to connect."
    }

    private var proxyHint: String {
        app.status.isRunning
            ? "Apps using this proxy are routed through Cloak."
            : "Configure your browser or system proxy to this address before you connect."
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
        return "Country: \(trimmed.uppercased())"
    }

    private func rate(_ bytesPerSec: Double) -> String {
        let bits = bytesPerSec * 8
        if bits < 1_000 { return String(format: "%.0f bps", bits) }
        if bits < 1_000_000 { return String(format: "%.1f Kbps", bits / 1_000) }
        if bits < 1_000_000_000 { return String(format: "%.1f Mbps", bits / 1_000_000) }
        return String(format: "%.2f Gbps", bits / 1_000_000_000)
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
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

private struct StatTile: View {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06)))
        )
    }
}

struct StatusOrb: View {
    let status: AppState.Status
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 54, height: 54)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(status.isRunning ? 1 : 0.5)
                .animation(status.isRunning
                           ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                           : .default, value: pulse)
            Circle().fill(color).frame(width: 18, height: 18)
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
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
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
