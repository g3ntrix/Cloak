import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var draft: AppSettings = .default
    @State private var listenerDraft: String = ListenerProjectConfig.defaultJSONString()
    @State private var jsonError: String?
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Layer 1 — Python listener (`main.py`)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("On Start we write this JSON to `<project>/config.json` and run `sudo .venv/bin/python main.py`. Dial targets here are for the Python bypass, not for Xray.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        LabeledField(
                            title: "Project path",
                            hint: "Folder that contains main.py and .venv.",
                            text: Binding(
                                get: { draft.pythonProjectPath ?? "" },
                                set: { draft.pythonProjectPath = $0.isEmpty ? nil : $0 }
                            )
                        )

                        SecureField("macOS password (sudo)", text: $app.sudoPassword)
                            .textFieldStyle(.roundedBorder)

                        Text("config.json fields")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.top, 4)
                        TextEditor(text: $listenerDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 160, maxHeight: 280)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25)))
                        if let e = jsonError {
                            Text(e).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Layer 2 — Xray local SOCKS")
                            .font(.system(size: 13, weight: .semibold))
                        Text("VLESS/Trojan share links in Profiles are rewritten to dial LISTEN_HOST:LISTEN_PORT from the JSON above, then exposed here as SOCKS.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        LabeledField(title: "SOCKS host", hint: "Usually 127.0.0.1",
                                     text: $draft.listenHost)
                        LabeledField(title: "SOCKS port", hint: "What your apps connect to.",
                                     text: Binding(
                                        get: { String(draft.listenPort) },
                                        set: { draft.listenPort = Int($0.filter { $0.isNumber }) ?? draft.listenPort }
                                     ))
                    }
                }

            Card {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log level").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Verbosity for Xray + listener logs in the Logs tab.")
                            .font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.8))
                    }
                    Spacer()
                    Picker("", selection: $draft.logLevel) {
                        ForEach(AppSettings.LogLevel.allCases) { l in
                            Text(l.rawValue).tag(l)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

                saveBar
            }
        }
        .onAppear {
            draft = app.settings
            listenerDraft = (try? app.listenerProject.encodeJSONString()) ?? ListenerProjectConfig.defaultJSONString()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Layer 1 = SNI-Spoofing Python. Layer 2 = Xray outbound → local listener, SOCKS inbound.")
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
                draft = app.settings
                listenerDraft = (try? app.listenerProject.encodeJSONString()) ?? ListenerProjectConfig.defaultJSONString()
                jsonError = nil
            }
            .buttonStyle(.bordered)
            Button("Save") {
                jsonError = nil
                do {
                    let parsed = try ListenerProjectConfig.decode(from: listenerDraft)
                    app.settings = draft
                    app.listenerProject = parsed
                    app.saveSettings()
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
            .disabled(false)
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
