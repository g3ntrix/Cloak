import SwiftUI
import AppKit

@main
struct SNISpoofingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    /// Constant ID so the menu-bar "Open" action can reopen the singleton
    /// window after the user closes it (rather than spawning a duplicate).
    static let mainWindowID = "cloak.main"

    var body: some Scene {
        Window("Cloak", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 580)
                .onAppear { appDelegate.appState = appState }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(status: appState.status)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Live-updating menu-bar icon: filled shield when connected, outline otherwise.
private struct MenuBarLabel: View {
    let status: AppState.Status

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
    }

    private var symbolName: String {
        switch status {
        case .running: return "shield.lefthalf.filled"
        case .starting, .stopping: return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .error: return "shield.slash"
        case .stopped: return "shield"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wired up from `SNISpoofingApp.body` so termination handlers can reach state.
    var appState: AppState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu-bar icon keeps the session alive after the window closes — user
        // explicitly quits via Cmd-Q or the Quit button in the menu-bar popover.
        false
    }

    /// Re-open the main window when the user clicks the Dock icon while no
    /// window is on-screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.terminateSync()
    }
}
