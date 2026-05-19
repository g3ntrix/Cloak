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
                Button("Clear") {
                    app.clearLogs()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
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
        }
    }

    private var joinedLogs: String {
        app.logs.map(\.text).joined(separator: "")
    }
}
