import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var uptime: String = "–"
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Headline
                VStack(alignment: .leading, spacing: 6) {
                    Text("SNI spoof + Xray")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Layer 1: Python listener. Layer 2: Xray → local port → SOCKS. Import any VLESS/Trojan URL in Profiles; dial is rewritten to your listener.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                // Primary control card
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

                // Active profile
                if let p = app.activeProfile {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Active profile", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.green)
                                Spacer()
                                Text(p.kind.display)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(.purple.opacity(0.2)))
                                    .foregroundStyle(.purple)
                            }
                            Text(p.name)
                                .font(.system(size: 18, weight: .bold))
                                .lineLimit(1)
                            LazyVGrid(columns: [.init(.flexible(), spacing: 14),
                                                .init(.flexible(), spacing: 14)], spacing: 14) {
                                InfoCard(icon: "link.circle", title: "Xray → listener",
                                         value: "\(app.listenerProject.LISTEN_HOST):\(app.listenerProject.LISTEN_PORT)")
                                InfoCard(icon: "arrow.up.right.circle", title: "URI server (info)",
                                         value: "\(p.server):\(p.serverPort)")
                                InfoCard(icon: "network", title: "Transport",
                                         value: "\(p.transport.kind.display)\(p.transport.path.isEmpty ? "" : " \(p.transport.path)")")
                                InfoCard(icon: "lock.shield", title: "Real SNI",
                                         value: p.tls.serverName.isEmpty ? "(none)" : p.tls.serverName)
                                InfoCard(icon: "theatermasks",
                                         title: p.tls.enableSpoof ? "Spoof SNI" : "Spoof",
                                         value: p.tls.enableSpoof ? p.tls.fakeSNI : "off",
                                         accent: p.tls.enableSpoof ? .purple : .secondary)
                            }
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No active profile", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Open the Profiles tab and import your vless:// URL, then click the power button on the profile to make it active.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Egress (via local proxy)
                if app.status.isRunning {
                    Card {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "globe")
                                .font(.system(size: 22))
                                .foregroundStyle(.mint)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Connection egress")
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Button {
                                        app.refreshEgressNow()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Refresh IP / country")
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
                                    Text(msg)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("—")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                // Current public IP card — shows the user's raw egress (bypassing Cloak).
                Card {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "wifi")
                            .font(.system(size: 22))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Current public IP")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button { app.refreshDirectIP() } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Refresh current IP")
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

                // Listener card — where to point the browser/app (proxy mode only).
                Card {
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.down.forward.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Point your client at (Xray SOCKS)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(verbatim: "\(app.settings.listenHost):\(app.settings.listenPort)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        }
                        Spacer()
                        Text(verbatim: "SOCKS5")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                }
            }
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private var secondaryLabel: String {
        if case .running = app.status, let started = app.startedAt {
            return "Up \(format(interval: Date().timeIntervalSince(started)))"
        }
        if app.activeProfile == nil { return "Select a profile to start." }
        return "Needs sudo password in Settings (listener) and a VLESS/Trojan profile."
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
        let upper = trimmed.uppercased()
        return "Country: \(upper)"
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

struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    var accent: Color = .accentColor
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.03))
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
