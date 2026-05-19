import SwiftUI
import AppKit

@main
struct SNISpoofingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wired up from `SNISpoofingApp.body` so termination handlers can reach state.
    var appState: AppState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Match Shade: closing the window quits the app, so cleanup runs.
        // Once a menubar item is added (Phase 4) this should return false.
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.terminateSync()
    }
}
