import SwiftUI

/// System-wide TUN toggle (same behavior as previously in Settings).
struct TunModeCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 10) {
                    Text("System tunnel (TUN)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Send this Mac’s IPv4 traffic through Cloak when you’re connected. First time may ask for your password; toggling reconnects if you’re already online.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Tunnel this Mac", isOn: tunModeBinding)
                        .toggleStyle(.switch)
                    if app.settings.useTunMode {
                        HStack(spacing: 8) {
                            Label(app.settings.tunInterfaceName, systemImage: "cable.connector")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("MTU \(app.settings.tunMTU)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var tunModeBinding: Binding<Bool> {
        Binding(
            get: { app.settings.useTunMode },
            set: { newValue in
                let previous = app.settings.useTunMode
                app.settings.useTunMode = newValue
                app.saveSettings()
                Task { @MainActor in
                    if newValue {
                        if !SudoPrivilege.tunRoutesHelperReady() || !SudoPrivilege.xrayWrapperReady() {
                            do {
                                try SudoPrivilege.install()
                                app.privilegesInstalled = SudoPrivilege.isInstalled()
                            } catch {
                                app.settings.useTunMode = previous
                                app.saveSettings()
                                return
                            }
                        }
                    }
                    await app.reconnectIfRunningAfterTunChange()
                }
            }
        )
    }
}
