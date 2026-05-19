import SwiftUI

struct LogsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Logs")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Toggle("Enable", isOn: Binding(
                    get: { app.settings.logsEnabled },
                    set: {
                        app.settings.logsEnabled = $0
                        app.saveSettings()
                        if !$0 { app.clearLogs() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Button("Clear") { app.clearLogs() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(app.logs.isEmpty)
            }

            if app.settings.logsEnabled {
                Text("Python listener, Xray, and connection messages. Use this tab when something fails.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextEditor(text: .constant(joinedLogs))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.controlFill(for: colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.stroke(for: colorScheme)))
                    )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Logs are off")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Cloak doesn't capture anything when logs are off — keeps memory low and avoids noise. Flip the switch above when you need to diagnose a problem.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var joinedLogs: String {
        app.logs.map(\.text).joined(separator: "")
    }
}
