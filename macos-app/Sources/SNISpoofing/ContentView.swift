import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: Tab = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard, profiles, settings, logs, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .profiles: return "Profiles"
            case .settings: return "Settings"
            case .logs: return "Logs"
            case .about: return "About"
            }
        }
        var symbol: String {
            switch self {
            case .dashboard: return "bolt.shield"
            case .profiles: return "person.crop.rectangle.stack"
            case .settings: return "slider.horizontal.3"
            case .logs: return "doc.text"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(tab: $tab)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 245)
        } detail: {
            ZStack {
                BackgroundGradient()
                Group {
                    switch tab {
                    case .dashboard: DashboardView()
                    case .profiles: ProfilesView()
                    case .settings: SettingsView()
                    case .logs: LogsView()
                    case .about: AboutView()
                    }
                }
                .padding(20)
            }
            .navigationTitle(tab.title)
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowAccessor())
    }
}

struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppTheme.background(for: colorScheme)
        .ignoresSafeArea()
    }
}

/// Configures the window for a standard-height hidden-title bar (traffic lights
/// float over the content, no extra drag strip). The same settings are reapplied
/// on fullscreen transitions, where AppKit otherwise restores an opaque titlebar
/// strip / separator line over the content.
struct WindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            context.coordinator.configure(w)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private weak var window: NSWindow?

        func configure(_ w: NSWindow) {
            window = w
            apply()
            let nc = NotificationCenter.default
            for name in [NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification] {
                nc.addObserver(self, selector: #selector(reapply),
                               name: name, object: w)
            }
        }

        @objc private func reapply() { apply() }

        private func apply() {
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.titlebarSeparatorStyle = .none
            w.isMovableByWindowBackground = true
            w.styleMask.insert(.fullSizeContentView)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
