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
/// float over the content, no extra drag strip). Native fullscreen is disabled so
/// the green button zooms (fills the screen in-place) instead of entering the
/// separate-Space fullscreen mode, which forced an opaque titlebar/menu strip to
/// slide over the content.
struct WindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            context.coordinator.attach(w)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private weak var window: NSWindow?

        func attach(_ w: NSWindow) {
            window = w
            apply()
            // SwiftUI re-adds `.fullScreenPrimary` after our initial setup, so the
            // green button reverts to native fullscreen. Reassert on every key
            // transition so the zoom ("+") behavior wins.
            NotificationCenter.default.addObserver(
                self, selector: #selector(reapply),
                name: NSWindow.didBecomeKeyNotification, object: w)
        }

        @objc private func reapply() { apply() }

        private func apply() {
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.titlebarSeparatorStyle = .none
            w.isMovableByWindowBackground = true
            w.styleMask.insert(.fullSizeContentView)
            w.collectionBehavior.remove(.fullScreenPrimary)
            w.collectionBehavior.insert(.fullScreenNone)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
