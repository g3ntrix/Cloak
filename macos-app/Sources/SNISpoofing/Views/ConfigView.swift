import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var listenerDraft: String = ListenerProjectConfig.defaultJSONString()
    @State private var jsonError: String?
    @State private var saved = false
    @State private var privilegeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // Cloudflare config editor — the only thing end users should touch.
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cloudflare config")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Restore default") {
                                listenerDraft = ListenerProjectConfig.factoryRestoreJSONString()
                                jsonError = nil
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Text("Paste your Cloudflare settings here. Save when you're done.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $listenerDraft)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 180, maxHeight: 320)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.black.opacity(0.25))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.08), lineWidth: 1))
                            )
                        if let e = jsonError {
                            Text(e).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Local SOCKS proxy")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Xray listens here — set your browser or system proxy to this address and port.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        LabeledField(
                            title: "Host",
                            hint: "Usually 127.0.0.1",
                            text: proxyHostBinding
                        )
                        LabeledField(
                            title: "Port",
                            hint: "Default 2080",
                            text: proxyPortBinding
                        )
                    }
                }

                // Admin-permission helper.
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Admin permission")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if app.privilegesInstalled {
                                Label("Granted", systemImage: "checkmark.shield.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(app.privilegesInstalled
                             ? "Cloak has one-time admin permission. Connect without typing your password."
                             : "Cloak needs admin rights once so it can start the VPN without a password each time.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack {
                            if app.privilegesInstalled {
                                Button("Remove permission") {
                                    do {
                                        try SudoPrivilege.uninstall()
                                        app.privilegesInstalled = SudoPrivilege.isInstalled()
                                    } catch {
                                        privilegeError = error.localizedDescription
                                    }
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Grant permission…") {
                                    do {
                                        try SudoPrivilege.install()
                                        app.privilegesInstalled = true
                                        privilegeError = nil
                                    } catch {
                                        privilegeError = error.localizedDescription
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            if let e = privilegeError {
                                Text(e).font(.caption).foregroundStyle(.red)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                saveBar
            }
        }
        .onAppear {
            listenerDraft = (try? app.listenerProject.encodeJSONString()) ?? ListenerProjectConfig.defaultJSONString()
            app.privilegesInstalled = SudoPrivilege.isInstalled()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Paste your Cloudflare config and grant admin permission once.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var saveBar: some View {
        HStack {
            if saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("Revert") {
                listenerDraft = (try? app.listenerProject.encodeJSONString()) ?? ListenerProjectConfig.defaultJSONString()
                jsonError = nil
            }
            .buttonStyle(.bordered)
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
        }
    }
}

struct LabeledField: View {
    let title: String
    let hint: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .frame(width: 180, alignment: .leading)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
