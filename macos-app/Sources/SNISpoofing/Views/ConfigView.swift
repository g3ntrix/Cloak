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

                cloudflareCard
                proxyCard
                permissionsCard
                diagnosticsCard

                if showAdvanced {
                    advancedCard
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Paste your Cloudflare config and grant the helper permission once.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var cloudflareCard: some View {
        Card {
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
                    .frame(minHeight: 150, maxHeight: 240)
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
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Local SOCKS endpoint")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        compactField(label: "Host", text: proxyHostBinding, monospaced: true, width: 160)
                        compactField(label: "Port", text: proxyPortBinding, monospaced: true, width: 90)
                        Spacer()
                    }
                    Text("Cloak's Xray listens here. Default 127.0.0.1:2080 keeps it on this Mac. Use 0.0.0.0 to share with other devices on your LAN.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                         ? "Granted — connect and toggle the system proxy without a password prompt."
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

    private var diagnosticsCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 17))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Diagnostics")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { app.settings.logsEnabled },
                            set: {
                                app.settings.logsEnabled = $0
                                app.saveSettings()
                                if !$0 { app.clearLogs() }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    Text(app.settings.logsEnabled
                         ? "Capturing xray + listener output in the Logs tab."
                         : "Logs are off — keeps memory low and silences chatter. Flip on when something fails.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
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
        .transition(.opacity.combined(with: .move(edge: .top)))
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

    private var proxyHostBinding: Binding<String> {
        Binding(
            get: { app.settings.listenHost },
            set: {
                app.settings.listenHost = $0
                app.saveSettings()
            }
        )
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
