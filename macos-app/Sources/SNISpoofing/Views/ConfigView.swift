import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var listenerDraft: String = ListenerProjectConfig.defaultJSONString()
    @State private var jsonError: String?
    @State private var saved = false
    @State private var privilegeError: String?
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                appearanceCard
                HStack(alignment: .top, spacing: 14) {
                    cloudflareCard
                    proxyCard
                }
                .fixedSize(horizontal: false, vertical: true)

                if showAdvanced {
                    advancedSection
                }

                HStack {
                    Button(showAdvanced ? "Hide advanced" : "Show advanced") {
                        withAnimation { showAdvanced.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    Spacer()
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            listenerDraft = (try? app.listenerProject.encodeJSONString()) ?? ListenerProjectConfig.defaultJSONString()
            app.privilegesInstalled = SudoPrivilege.isInstalled()
        }
    }

    // MARK: - Sections

    private var appearanceCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance")
                        .font(.system(size: 13, weight: .semibold))
                    AppearancePicker(mode: Binding(
                        get: { app.settings.appearanceMode },
                        set: {
                            app.settings.appearanceMode = $0
                            app.saveSettings()
                        }
                    ))
                    Text("Choose light or dark, or follow your Mac's system setting.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Tune Cloak's appearance, local proxy, and connection config.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var cloudflareCard: some View {
        Card(maxHeight: .infinity) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Cloudflare config", systemImage: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Restore default") {
                        listenerDraft = ListenerProjectConfig.factoryRestoreJSONString()
                        jsonError = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    Button("Save") {
                        jsonError = nil
                        do {
                            let parsed = try ListenerProjectConfig.decode(from: listenerDraft)
                            app.listenerProject = parsed
                            app.saveListenerProject()
                            withAnimation { saved = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { saved = false }
                            }
                        } catch {
                            jsonError = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    if saved {
                        Label("Saved", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
                TextEditor(text: $listenerDraft)
                    .font(.system(size: 11.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 160)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.controlFill(for: colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.stroke(for: colorScheme)))
                    )
                if let e = jsonError {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.red)
                }
            }
        }
    }

    private var proxyCard: some View {
        Card(maxHeight: .infinity) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Local proxy listeners")
                        .font(.system(size: 13, weight: .semibold))
                    ListenScopeToggle(exposesToLAN: Binding(
                        get: { app.settings.exposesToLAN },
                        set: { enabled in
                            var s = app.settings
                            s.setExposesToLAN(enabled)
                            app.settings = s
                            app.saveSettings()
                            Task { await app.reconnectIfRunning() }
                        }
                    ))
                    HStack(alignment: .center, spacing: 8) {
                        Text("SOCKS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("", text: proxyPortBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(width: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AppTheme.controlFill(for: colorScheme))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.stroke(for: colorScheme)))
                            )
                        Text("HTTP")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("", text: httpPortBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(width: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AppTheme.controlFill(for: colorScheme))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.stroke(for: colorScheme)))
                            )
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var permissionsCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: app.privilegesInstalled ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 17))
                    .foregroundStyle(app.privilegesInstalled ? .green : .orange)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Helper permission")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if app.privilegesInstalled {
                            Button("Revoke") {
                                do {
                                    try SudoPrivilege.uninstall()
                                    app.privilegesInstalled = SudoPrivilege.isInstalled()
                                    privilegeError = nil
                                } catch {
                                    privilegeError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Grant…") {
                                do {
                                    try SudoPrivilege.install()
                                    app.privilegesInstalled = true
                                    privilegeError = nil
                                } catch {
                                    privilegeError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    Text(app.privilegesInstalled
                         ? "Granted. Connect and toggle the system proxy without a password prompt."
                         : "Cloak needs one-time admin permission to run the SNI listener and toggle the macOS SOCKS proxy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let e = privilegeError {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            advancedCard
            permissionsCard
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var advancedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Advanced", systemImage: "gearshape.2")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                HStack {
                    Text("xray log level")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { app.settings.logLevel },
                        set: {
                            app.settings.logLevel = $0
                            app.saveSettings()
                        }
                    )) {
                        ForEach(AppSettings.LogLevel.allCases) { lvl in
                            Text(lvl.rawValue.capitalized).tag(lvl)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)
                    Spacer()
                }
                Text("Only takes effect on the next Connect. Use \"debug\" to surface every xray dispatch line.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Compact field helper

    private func compactField(label: String, text: Binding<String>, monospaced: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(width: width)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.stroke(for: colorScheme)))
                )
        }
    }

    private var proxyPortBinding: Binding<String> {
        Binding(
            get: { String(app.settings.listenPort) },
            set: {
                let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Int(t), v > 0, v <= 65_535 {
                    app.settings.listenPort = v
                    app.saveSettings()
                }
            }
        )
    }

    private var httpPortBinding: Binding<String> {
        Binding(
            get: { String(app.settings.httpPort) },
            set: {
                let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Int(t), v > 0, v <= 65_535 {
                    app.settings.httpPort = v
                    app.saveSettings()
                }
            }
        )
    }
}

// LabeledField was kept by older callers — keep the type around so any other
// view that still references it compiles. New code uses the inline compact
// field above instead.
struct LabeledField: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let hint: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 120, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1)
                        )
                )
        }
    }
}
