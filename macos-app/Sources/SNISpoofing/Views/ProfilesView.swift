import SwiftUI
import UniformTypeIdentifiers

/// Profiles tab: a single-column list focused on picking and triaging profiles.
/// No editor — users import URIs and pick one. Technical details (TLS, transport)
/// are derived from the URI by the importer and aren't user-facing here.
struct ProfilesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var showImport = false
    @State private var pendingDelete: UUID?
    @State private var renaming: UUID?
    @State private var renameDraft: String = ""

    @State private var pingResults: [UUID: RealPingService.Result] = [:]
    @State private var pinging: Set<UUID> = []
    @State private var sortByPing = false

    @State private var dropActive = false
    @State private var dropError: String?

    private var orderedProfiles: [Profile] {
        guard sortByPing else { return app.profiles }
        return app.profiles.sorted { a, b in
            let ra = pingResults[a.id]?.millis ?? Int.max
            let rb = pingResults[b.id]?.millis ?? Int.max
            if ra == rb { return a.name.localizedCompare(b.name) == .orderedAscending }
            return ra < rb
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            toolbar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL, .plainText, .utf8PlainText], isTargeted: $dropActive) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay(alignment: .topTrailing) {
            if let msg = dropError {
                Text(msg)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .foregroundStyle(.white)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet { raw in
                let summary = app.importMany(from: raw)
                if summary.totalParsed == 0 && summary.failed.isEmpty {
                    return .error("No vless:// / trojan:// / vmess:// / ss:// links found in the input.")
                }
                return .summary(summary)
            }
        }
        .alert("Delete this profile?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { app.delete(profileID: id) }
                pendingDelete = nil
            }
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(app.profiles.isEmpty
                     ? "Paste links or drop a subscription file to add your first profile."
                     : "\(app.profiles.count) profile\(app.profiles.count == 1 ? "" : "s") · tap a profile to make it active.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showImport = true
            } label: {
                Label("Import", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if !app.profiles.isEmpty {
            HStack(spacing: 10) {
                Button {
                    Task { @MainActor in await pingAll() }
                } label: {
                    if !pinging.isEmpty && pinging.count == app.profiles.count {
                        Label("Pinging…", systemImage: "hourglass")
                    } else {
                        Label("Ping all", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!pinging.isEmpty)

                Toggle(isOn: $sortByPing) {
                    Text("Sort by ping").font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                Text("Drop a .txt file anywhere to bulk-import.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.profiles.isEmpty {
            EmptyState(showDropHint: dropActive, onImport: { showImport = true })
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(orderedProfiles) { p in
                        ProfileRow(
                            profile: p,
                            isActive: app.settings.activeProfileID == p.id,
                            isRenaming: renaming == p.id,
                            renameDraft: $renameDraft,
                            pingResult: pingResults[p.id],
                            isPinging: pinging.contains(p.id),
                            onActivate: { app.setActive(p.id) },
                            onPing: { Task { @MainActor in await pingOne(p) } },
                            onStartRename: {
                                renameDraft = p.name
                                renaming = p.id
                            },
                            onCommitRename: {
                                if let id = renaming {
                                    app.rename(profileID: id, to: renameDraft)
                                }
                                renaming = nil
                                renameDraft = ""
                            },
                            onCancelRename: {
                                renaming = nil
                                renameDraft = ""
                            }
                        )
                        .contextMenu {
                            Button("Make Active") { app.setActive(p.id) }
                            Button("Rename") {
                                renameDraft = p.name
                                renaming = p.id
                            }
                            Button("Ping") { Task { @MainActor in await pingOne(p) } }
                            Divider()
                            Button("Copy SNI") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(p.tls.serverName, forType: .string)
                            }
                            .disabled(p.tls.serverName.isEmpty)
                            Divider()
                            Button("Delete", role: .destructive) { pendingDelete = p.id }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dropActive ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) {
        // Prefer plain-text payload (a paste-from-file works that way too).
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    if let text = item as? String { Task { @MainActor in ingest(rawText: text) } }
                }
                return
            }
        }
        // Fall back to file URL: read first 2 MB as UTF-8.
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                let url: URL? = {
                    if let d = data as? Data {
                        return URL(dataRepresentation: d, relativeTo: nil)
                    } else if let u = data as? URL {
                        return u
                    }
                    return nil
                }()
                guard let url else { return }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    Task { @MainActor in ingest(rawText: text) }
                } else if let data = try? Data(contentsOf: url),
                          let text = String(data: data, encoding: .utf8) {
                    Task { @MainActor in ingest(rawText: text) }
                }
            }
            return
        }
    }

    @MainActor
    private func ingest(rawText: String) {
        let summary = app.importMany(from: rawText)
        if summary.totalParsed == 0 {
            flashDropError("No profile links in dropped file.")
        } else {
            flashDropError("Added \(summary.added) profile\(summary.added == 1 ? "" : "s")" +
                           (summary.duplicates > 0 ? " · \(summary.duplicates) duplicate\(summary.duplicates == 1 ? "" : "s") skipped" : ""))
        }
    }

    @MainActor
    private func flashDropError(_ msg: String) {
        withAnimation { dropError = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { dropError = nil }
        }
    }

    // MARK: - Ping helpers (unchanged from previous version)

    private static func directPing(for p: Profile) async -> RealPingService.Result {
        let host = p.server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return RealPingService.Result(millis: nil, error: "no server") }
        guard p.serverPort > 0, p.serverPort <= 65_535 else { return RealPingService.Result(millis: nil, error: "bad port") }
        return await RealPingService.ping(host: host, port: UInt16(clamping: p.serverPort))
    }

    @MainActor
    private func pingOne(_ p: Profile) async {
        _ = pinging.insert(p.id)
        pingResults[p.id] = await Self.directPing(for: p)
        pinging.remove(p.id)
    }

    @MainActor
    private func pingAll() async {
        let toPing = app.profiles
        guard !toPing.isEmpty else { return }
        pinging = Set(toPing.map(\.id))
        await withTaskGroup(of: (UUID, RealPingService.Result).self) { group in
            for p in toPing {
                group.addTask {
                    let r = await Self.directPing(for: p)
                    return (p.id, r)
                }
            }
            for await (id, r) in group {
                pingResults[id] = r
                pinging.remove(id)
            }
        }
    }
}

// MARK: - Row

private struct ProfileRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let profile: Profile
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    let pingResult: RealPingService.Result?
    let isPinging: Bool
    let onActivate: () -> Void
    let onPing: () -> Void
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @State private var hover = false
    @FocusState private var renameFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            kindBadge

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Profile name", text: $renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($renameFocus)
                        .onAppear { renameFocus = true }
                        .onSubmit { onCommitRename() }
                        .onExitCommand { onCancelRename() }
                } else {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            PingChip(result: pingResult, isLoading: isPinging, onTap: onPing)

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .font(.system(size: 16))
                    .help("Active profile")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive
                      ? Color.accentColor.opacity(0.14)
                      : (hover ? AppTheme.hoverFill(for: colorScheme) : AppTheme.subtleFill(for: colorScheme)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.accentColor.opacity(0.45) : AppTheme.faintStroke(for: colorScheme),
                                lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onStartRename() }
        .onTapGesture { if !isRenaming { onActivate() } }
        .onHover { hover = $0 }
    }

    private var kindBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.22))
                .frame(width: 30, height: 30)
            Text(profile.kind.display.prefix(2).uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
        }
    }

    private var subtitle: String {
        let sni = profile.tls.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sni.isEmpty { return sni }
        if !profile.transport.host.isEmpty { return profile.transport.host }
        return "\(profile.server):\(profile.serverPort)"
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

private struct PingChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let result: RealPingService.Result?
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if let ms = result?.millis {
                    Text("\(ms) ms")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color(for: ms))
                } else if result?.error != nil {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 40, minHeight: 16)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppTheme.subtleFill(for: colorScheme))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.faintStroke(for: colorScheme)))
            )
        }
        .buttonStyle(.plain)
        .help(result?.error ?? "TCP ping (works while disconnected)")
    }

    private func color(for ms: Int) -> Color {
        switch ms {
        case 0 ..< 120: return .green
        case 120 ..< 300: return .yellow
        default: return .orange
        }
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let showDropHint: Bool
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: showDropHint ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 38))
                .foregroundStyle(showDropHint ? Color.accentColor : .secondary)
            Text(showDropHint ? "Drop to import" : "No profiles yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Paste your trojan:// or vless:// links, or drop a subscription text file. Cloak will detect everything in one go.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Import…", action: onImport)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardFill(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: showDropHint ? 2 : 1,
                                                         dash: showDropHint ? [6, 5] : []))
                        .foregroundStyle(showDropHint ? Color.accentColor : AppTheme.stroke(for: colorScheme))
                )
        )
    }
}

// MARK: - Import sheet

private enum ImportResult {
    case error(String)
    case summary(AppState.ImportSummary)
}

private struct ImportSheet: View {
    let onSubmit: (String) -> ImportResult
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var lastSummary: AppState.ImportSummary?

    private var detectedCount: Int {
        guard !text.isEmpty else { return 0 }
        return ProfileImporter.countCandidates(in: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Import profiles")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if detectedCount > 0 && lastSummary == nil {
                    Text("\(detectedCount) link\(detectedCount == 1 ? "" : "s") detected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                }
            }
            Text("Paste one or more trojan:// / vless:// / vmess:// / ss:// links — one per line, or all on one line, Cloak doesn't care.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200, maxHeight: 320)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.stroke(for: colorScheme)))
                )

            if let summary = lastSummary {
                summaryBlock(summary)
            } else if let e = error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(lastSummary == nil ? "Cancel" : "Done") { dismiss() }
                if lastSummary == nil {
                    Button("Import \(detectedCount > 0 ? "(\(detectedCount))" : "")") {
                        switch onSubmit(text) {
                        case .error(let msg):
                            error = msg
                            lastSummary = nil
                        case .summary(let s):
                            error = nil
                            lastSummary = s
                            if s.added > 0 && s.failed.isEmpty {
                                // No failures + at least one added — close the sheet.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(detectedCount == 0)
                }
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    @ViewBuilder
    private func summaryBlock(_ summary: AppState.ImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                statPill(label: "Added", value: summary.added, color: .green)
                if summary.duplicates > 0 {
                    statPill(label: "Duplicates", value: summary.duplicates, color: .yellow)
                }
                if !summary.failed.isEmpty {
                    statPill(label: "Failed", value: summary.failed.count, color: .red)
                }
            }
            if !summary.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(summary.failed.enumerated()), id: \.offset) { _, err in
                            Text(err)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxHeight: 80)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.subtleFill(for: colorScheme))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.faintStroke(for: colorScheme)))
        )
    }

    private func statPill(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(String(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.18)))
        .foregroundStyle(color)
    }
}
