import SwiftUI
import UniformTypeIdentifiers
import AppKit

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

    @AppStorage("profiles.sortByPing") private var sortByPing = false
    @State private var checkedIDs: Set<UUID> = []
    @State private var selectionMode = false

    @State private var dropActive = false
    @State private var notice: ProfileNotice?
    @State private var showBulkDelete = false
    @State private var showRemoveUnpingedConfirm = false

    private var profilesWithoutSuccessfulPingCount: Int {
        app.profilesWithoutSuccessfulPing.count
    }

    private var orderedProfiles: [Profile] {
        guard sortByPing else { return app.profiles }
        return app.profiles.sorted { a, b in
            let ra = app.profilePingResults[a.id]?.millis ?? Int.max
            let rb = app.profilePingResults[b.id]?.millis ?? Int.max
            if ra == rb { return a.name.localizedCompare(b.name) == .orderedAscending }
            return ra < rb
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            dropHintBanner
            toolbar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.fileURL, .plainText, .utf8PlainText], isTargeted: $dropActive) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay(alignment: .bottom) {
            noticeView
                .padding(.bottom, 12)
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
        .alert("Delete \(checkedIDs.count) profile\(checkedIDs.count == 1 ? "" : "s")?",
               isPresented: $showBulkDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteChecked() }
        }
        .alert(
            "Remove \(profilesWithoutSuccessfulPingCount) profile\(profilesWithoutSuccessfulPingCount == 1 ? "" : "s")?",
            isPresented: $showRemoveUnpingedConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { removeProfilesWithoutSuccessfulPing() }
        } message: {
            Text("Deletes every profile that has no successful ping (failed or not tested). This cannot be undone.")
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            HStack(spacing: 8) {
                Image(systemName: notice.kind.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(notice.message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(notice.kind.fill(for: colorScheme))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 12, y: 4)
            )
            .overlay(Capsule().stroke(notice.kind.stroke, lineWidth: 1))
            .foregroundStyle(notice.kind.foreground)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(app.profiles.isEmpty
                     ? "Paste links or drop a .txt file to add your first profile."
                     : "\(app.profiles.count) profile\(app.profiles.count == 1 ? "" : "s") · tap to activate · drop a file to import more.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showImport = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var dropHintBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: dropActive ? "arrow.down.doc.fill" : "doc.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(dropActive ? Color.accentColor : .secondary)
            Text(dropActive
                 ? "Release to import"
                 : "Drag and drop a text file with vless, trojan, vmess, or ss links")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dropActive ? Color.accentColor : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(dropActive
                      ? Color.accentColor.opacity(0.12)
                      : AppTheme.subtleFill(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: dropActive ? [] : [5, 4]),
                            antialiased: true
                        )
                        .foregroundStyle(dropActive ? Color.accentColor.opacity(0.6) : AppTheme.faintStroke(for: colorScheme))
                )
        )
    }

    @ViewBuilder
    private var toolbar: some View {
        if !app.profiles.isEmpty {
            HStack(spacing: 10) {
                if app.isPingBatchRunning {
                    Button("Cancel") { app.cancelPingBatch() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    let remaining = app.profilePingingIDs.count
                    let total = app.profiles.count
                    Text("\(total - remaining)/\(total)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        app.startPingAllProfiles()
                    } label: {
                        Label("Ping all", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!app.profilePingingIDs.isEmpty)
                }

                Toggle(isOn: $sortByPing) {
                    Text("Sort by ping").font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if !app.isPingBatchRunning,
                   !app.profilePingResults.isEmpty,
                   profilesWithoutSuccessfulPingCount > 0 {
                    Button("Remove no ping (\(profilesWithoutSuccessfulPingCount))", role: .destructive) {
                        showRemoveUnpingedConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                if selectionMode {
                    Button("All") { checkedIDs = Set(app.profiles.map(\.id)) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    if !checkedIDs.isEmpty {
                        Button("Export (\(checkedIDs.count))") {
                            exportProfiles(selectedProfiles)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Delete (\(checkedIDs.count))", role: .destructive) {
                            showBulkDelete = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button("Done") {
                        selectionMode = false
                        checkedIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Select") { selectionMode = true }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
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
                            isChecked: checkedIDs.contains(p.id),
                            selectionMode: selectionMode,
                            isRenaming: renaming == p.id,
                            renameDraft: $renameDraft,
                            pingResult: app.profilePingResults[p.id],
                            isPinging: app.profilePingingIDs.contains(p.id),
                            onActivate: {
                                guard renaming != p.id else { return }
                                if selectionMode {
                                    toggleChecked(p.id)
                                } else {
                                    app.setActive(p.id)
                                }
                            },
                            onToggleCheck: { toggleChecked(p.id) },
                            onPing: { Task { @MainActor in await app.pingSingleProfile(p) } },
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
                            Button("Ping") { Task { @MainActor in await app.pingSingleProfile(p) } }
                            Divider()
                            Button("Export Config") {
                                exportProfiles([p])
                            }
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
            showNotice("No profile links in dropped file.", kind: .error)
        } else {
            showNotice("Added \(summary.added) profile\(summary.added == 1 ? "" : "s")" +
                       (summary.duplicates > 0 ? " · \(summary.duplicates) duplicate\(summary.duplicates == 1 ? "" : "s") skipped" : ""),
                       kind: .success)
        }
    }

    @MainActor
    private func showNotice(_ message: String, kind: ProfileNotice.Kind) {
        let notice = ProfileNotice(message: message, kind: kind)
        withAnimation { self.notice = notice }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if self.notice?.id == notice.id {
                withAnimation { self.notice = nil }
            }
        }
    }

    // MARK: - Selection

    private var selectedProfiles: [Profile] {
        app.profiles.filter { checkedIDs.contains($0.id) }
    }

    @MainActor
    private func toggleChecked(_ id: UUID) {
        if checkedIDs.contains(id) {
            checkedIDs.remove(id)
        } else {
            checkedIDs.insert(id)
        }
    }

    @MainActor
    private func deleteChecked() {
        for id in checkedIDs {
            app.delete(profileID: id)
        }
        checkedIDs.removeAll()
        selectionMode = false
    }

    @MainActor
    private func removeProfilesWithoutSuccessfulPing() {
        let removed = app.deleteProfilesWithoutSuccessfulPing()
        checkedIDs.removeAll()
        selectionMode = false
        if removed > 0 {
            showNotice("Removed \(removed) profile\(removed == 1 ? "" : "s") with no ping.", kind: .success)
        }
    }

    @MainActor
    private func exportProfiles(_ profiles: [Profile]) {
        guard !profiles.isEmpty else { return }

        let text: String
        do {
            text = try ProfileExporter.exportText(profiles)
        } catch {
            showNotice(error.localizedDescription, kind: .error)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = profiles.count == 1
            ? "\(safeExportFilename(profiles[0].name)).txt"
            : "cloak-configs.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    showNotice("Exported \(profiles.count) config\(profiles.count == 1 ? "" : "s").", kind: .success)
                }
            } catch {
                DispatchQueue.main.async {
                    showNotice("Export failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func safeExportFilename(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "cloak-config" : cleaned
    }

}

private struct ProfileNotice: Identifiable, Equatable {
    enum Kind {
        case success
        case error

        var systemImage: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var foreground: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            }
        }

        var stroke: Color {
            switch self {
            case .success: return Color.green.opacity(0.28)
            case .error: return Color.red.opacity(0.35)
            }
        }

        func fill(for scheme: ColorScheme) -> Color {
            switch self {
            case .success:
                return scheme == .dark ? Color.green.opacity(0.18) : Color.green.opacity(0.12)
            case .error:
                return scheme == .dark ? Color.red.opacity(0.18) : Color.red.opacity(0.10)
            }
        }
    }

    let id = UUID()
    let message: String
    let kind: Kind
}

// MARK: - Row

private struct ProfileRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let profile: Profile
    let isActive: Bool
    let isChecked: Bool
    let selectionMode: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    let pingResult: RealPingService.Result?
    let isPinging: Bool
    let onActivate: () -> Void
    let onToggleCheck: () -> Void
    let onPing: () -> Void
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @State private var hover = false
    @FocusState private var renameFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggleCheck() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
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
                .fill(rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.accentColor.opacity(0.45) : AppTheme.faintStroke(for: colorScheme),
                                lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming { onActivate() } }
        .onHover { hover = $0 }
    }

    private var rowFill: Color {
        if isActive { return Color.accentColor.opacity(0.14) }
        if isChecked { return Color.accentColor.opacity(0.08) }
        if hover { return AppTheme.hoverFill(for: colorScheme) }
        return AppTheme.subtleFill(for: colorScheme)
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
        .help(result?.error ?? "Route through this profile and measure latency")
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
            Text("Paste your links, or drag and drop a text file with vless, trojan, vmess, or ss configs.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                onImport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add profiles")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
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
                Text("Add profiles")
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
            Text("Paste one or more trojan:// / vless:// / vmess:// / ss:// links. One per line or all on one line.")
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
                    Button("Add \(detectedCount > 0 ? "(\(detectedCount))" : "")") {
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
