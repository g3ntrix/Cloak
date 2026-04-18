import SwiftUI

struct LogsView: View {
    @EnvironmentObject var app: AppState
    @State private var autoscroll = true
    @State private var filter: String = ""

    var filtered: [LogLine] {
        guard !filter.isEmpty else { return app.logs }
        return app.logs.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Logs")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                TextField("Filter…", text: $filter)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08), lineWidth: 1))
                    )
                Toggle("Auto-scroll", isOn: $autoscroll)
                    .toggleStyle(.switch).controlSize(.small)
                Button("Copy all") { copyAll() }
                    .buttonStyle(.bordered)
                Button("Clear") { app.clearLogs() }
                    .buttonStyle(.bordered)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { line in
                            LogRow(line: line).id(line.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
                )
                .onChange(of: filtered.count) { _ in
                    guard autoscroll, let last = filtered.last else { return }
                    withAnimation(.linear(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func copyAll() {
        let s = app.logs.map(format).joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func format(_ l: LogLine) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        return "[\(df.string(from: l.timestamp))] \(l.text)"
    }
}

private struct LogRow: View {
    let line: LogLine
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
    private var timestamp: String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        return df.string(from: line.timestamp)
    }
    private var color: Color {
        switch line.stream {
        case .stdout: return .primary.opacity(0.9)
        case .stderr: return .orange
        case .system: return .cyan
        }
    }
}
