import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var app: AppState
    @State private var selection: UUID?
    @State private var showImport = false
    @State private var pendingDelete: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: list
            VStack(spacing: 10) {
                HStack {
                    Text("Profiles")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        showImport = true
                    } label: {
                        Label("Import URL", systemImage: "link")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }

                if app.profiles.isEmpty {
                    EmptyState(onImport: { showImport = true })
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(app.profiles) { p in
                                ProfileRow(
                                    profile: p,
                                    isActive: app.settings.activeProfileID == p.id,
                                    isSelected: selection == p.id,
                                    onTap: { selection = p.id },
                                    onActivate: { app.setActive(p.id) }
                                )
                                .contextMenu {
                                    Button("Make Active") { app.setActive(p.id) }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        pendingDelete = p.id
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 320)

            // Right: editor
            Group {
                if let id = selection ?? app.profiles.first?.id,
                   let binding = bindingFor(id: id) {
                    ProfileEditor(
                        profile: binding,
                        isActive: app.settings.activeProfileID == id,
                        onActivate: { app.setActive(id) },
                        onDelete: { pendingDelete = id }
                    )
                } else {
                    EmptyEditor(onImport: { showImport = true })
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selection == nil {
                selection = app.settings.activeProfileID ?? app.profiles.first?.id
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet { raw in
                do {
                    let p = try app.importFromURL(raw)
                    selection = p.id
                } catch {
                    return error.localizedDescription
                }
                return nil
            }
        }
        .alert("Delete this profile?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDelete {
                    app.delete(profileID: id)
                    if selection == id { selection = app.profiles.first?.id }
                }
                pendingDelete = nil
            }
        }
    }

    private func bindingFor(id: UUID) -> Binding<Profile>? {
        guard let idx = app.profiles.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { app.profiles[idx] },
            set: {
                app.profiles[idx] = $0
                app.saveProfiles()
            }
        )
    }
}

// MARK: - List row

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onActivate: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.22))
                        .frame(width: 32, height: 32)
                    Text(profile.kind.display.prefix(1))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(profile.kind.display) · \(profile.server):\(profile.serverPort)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                } else {
                    Button(action: onActivate) {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Make active")
                    .foregroundStyle(.secondary)
                    .opacity(hover ? 1 : 0.6)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.18)
                          : (hover ? Color.white.opacity(0.05) : Color.white.opacity(0.03)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : .white.opacity(0.08),
                                    lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var accent: Color {
        switch profile.kind {
        case .vless: return .purple
        case .vmess: return .blue
        case .trojan: return .orange
        case .shadowsocks: return .pink
        }
    }
}

// MARK: - Empty states

private struct EmptyState: View {
    let onImport: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("No profiles yet")
                .font(.system(size: 13, weight: .medium))
            Text("Paste a vless:// or trojan:// share URL to import.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Import URL") { onImport() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
        )
    }
}

private struct EmptyEditor: View {
    let onImport: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Select or import a profile")
                .font(.system(size: 15, weight: .semibold))
            Text("Configs for VLESS, VMess, Trojan, or Shadowsocks.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Import URL") { onImport() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
        )
    }
}

// MARK: - Import sheet

private struct ImportSheet: View {
    /// returns error message or nil on success
    let onSubmit: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import profile")
                .font(.system(size: 15, weight: .semibold))
            Text("Paste a vless:// or trojan:// line. Optional: add a JSON block with the same keys as main.py config (CONNECT_IP, CONNECT_PORT, FAKE_SNI) to tune the Python layer. Xray always rewrites the outbound dial to LISTEN_HOST:LISTEN_PORT from Settings.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 180)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.3)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1))
                )
            if let e = error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") {
                    if let err = onSubmit(text) { error = err }
                    else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

// MARK: - Editor

private struct ProfileEditor: View {
    @Binding var profile: Profile
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 12) {
                    TextField("Profile name", text: $profile.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                    Spacer()
                    if isActive {
                        Label("Active", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(.green.opacity(0.15)))
                    } else {
                        Button("Make Active") { onActivate() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Server
                Card {
                    VStack(spacing: 14) {
                        if isLoopback(profile.server) {
                            Label("URI points at localhost — OK. Layer 2 (Xray) dials LISTEN_HOST:LISTEN_PORT from Settings → listener JSON.",
                                  systemImage: "info.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.cyan)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Text("Type").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Picker("", selection: $profile.kind) {
                                ForEach(Profile.Kind.allCases) { k in
                                    Text(k.display).tag(k)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        Field("Server", text: $profile.server, monospaced: true)
                        Field("Port", text: Binding(
                            get: { String(profile.serverPort) },
                            set: { profile.serverPort = Int($0.filter { $0.isNumber }) ?? profile.serverPort }
                        ), monospaced: true)
                        switch profile.kind {
                        case .vless:
                            Field("UUID", text: $profile.uuid, monospaced: true)
                            Field("Flow (optional)", text: $profile.flow)
                            Field("Packet encoding", text: Binding(
                                get: { profile.packetEncoding ?? "" },
                                set: {
                                    let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                    profile.packetEncoding = t.isEmpty ? nil : t
                                }
                            ), monospaced: true)
                        case .vmess:
                            Field("UUID", text: $profile.uuid, monospaced: true)
                            Field("Flow (optional)", text: $profile.flow)
                        case .trojan:
                            Field("Password", text: $profile.password, secure: true)
                        case .shadowsocks:
                            Field("Password", text: $profile.password, secure: true)
                            Field("Method", text: $profile.method)
                        }
                    }
                }

                // TLS
                Card {
                    VStack(spacing: 14) {
                        Toggle(isOn: $profile.tls.enabled) {
                            VStack(alignment: .leading) {
                                Text("TLS").font(.system(size: 13, weight: .semibold))
                                Text("Wrap the connection in TLS with the server name below.")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        if profile.tls.enabled {
                            Field("Real SNI (server_name)", text: $profile.tls.serverName, monospaced: true)
                            Field("Fingerprint (utls)", text: $profile.tls.fingerprint)
                            Field("ALPN (comma-separated)", text: Binding(
                                get: { profile.tls.alpn.joined(separator: ",") },
                                set: { profile.tls.alpn = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                            ), monospaced: true)
                            Toggle("Allow insecure", isOn: $profile.tls.allowInsecure)
                                .font(.system(size: 12))
                        }
                    }
                }

                // Spoof
                if profile.tls.enabled {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $profile.tls.enableSpoof) {
                                VStack(alignment: .leading) {
                                    Text("SNI Spoof").font(.system(size: 13, weight: .semibold))
                                    Text("Prepends a forged ClientHello with a fake SNI before the real TLS handshake. Requires admin on macOS.")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if profile.tls.enableSpoof {
                                Field("Fake SNI", text: $profile.tls.fakeSNI, monospaced: true)
                                HStack {
                                    Text("Spoof method")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 110, alignment: .leading)
                                    Picker("", selection: $profile.tls.spoofMethod) {
                                        ForEach(Profile.TLS.SpoofMethod.allCases) { m in
                                            Text(m.display).tag(m)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                }

                // Transport
                Card {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Transport").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Picker("", selection: $profile.transport.kind) {
                                ForEach(Profile.Transport.Kind.allCases) { k in
                                    Text(k.display).tag(k)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                        switch profile.transport.kind {
                        case .tcp: EmptyView()
                        case .ws:
                            Field("Path", text: $profile.transport.path, monospaced: true)
                            Field("Host header", text: $profile.transport.host, monospaced: true)
                        case .grpc:
                            Field("Service name", text: $profile.transport.serviceName, monospaced: true)
                        case .http:
                            Field("Path", text: $profile.transport.path, monospaced: true)
                            Field("Host header", text: $profile.transport.host, monospaced: true)
                        case .httpupgrade:
                            Field("Path", text: $profile.transport.path, monospaced: true)
                            Field("Host header", text: $profile.transport.host, monospaced: true)
                        }
                    }
                }
            }
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return h == "127.0.0.1" || h == "localhost" || h == "::1"
    }
}

// MARK: - Field helper

private struct Field: View {
    let title: String
    @Binding var text: String
    var monospaced: Bool = false
    var secure: Bool = false

    init(_ title: String, text: Binding<String>, monospaced: Bool = false, secure: Bool = false) {
        self.title = title
        self._text = text
        self.monospaced = monospaced
        self.secure = secure
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}
