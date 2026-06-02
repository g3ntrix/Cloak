import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject var app: AppState

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                updateCard
                projectCard
                authorCard
                donateCard
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var updateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Updates", systemImage: "arrow.down.app.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    updateAction
                }

                updateContent
            }
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch app.updateState {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .downloading:
            Button("Cancel") {
                app.cancelUpdateDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .available:
            Button("Download") {
                Task { await app.downloadAvailableUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .downloaded(let url):
            Button("Open DMG") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            Button("Check") {
                Task { await app.checkForUpdates() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var updateContent: some View {
        switch app.updateState {
        case .idle:
            Text("Current version \(appVersion).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .checking:
            Text("Looking for updates...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .upToDate(let version):
            Text("You're up to date on \(version).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .available(let release):
            VStack(alignment: .leading, spacing: 5) {
                Text("Version \(release.version) is available")
                    .font(.system(size: 12, weight: .semibold))
                Text("Installed \(appVersion) · Download \(formatMegabytes(release.assetSize))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Link("View release notes", destination: release.htmlURL)
                    .font(.system(size: 11, weight: .medium))
            }
        case .downloading(let release, let progress):
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Downloading \(release.assetName)")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        case .downloaded(let url):
            Text("Downloaded to \(url.lastPathComponent). Open the DMG and replace Cloak.app to finish updating.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        Card {
            HStack(spacing: 18) {
                CloakBrandImage(size: 64, cornerRadius: 14)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Cloak")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("v\(appVersion)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("A macOS proxy app that routes traffic through a local SNI-spoofing bridge and Xray to stay connected on restrictive networks.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var projectCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.yellow)
                    Text("Open source")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text("Cloak lives on GitHub. If it helps you, I'd love a star on the repo.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("github.com/g3ntrix/Cloak", destination: URL(string: "https://github.com/g3ntrix/Cloak")!)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var authorCard: some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Made by g3ntrix")
                        .font(.system(size: 14, weight: .semibold))
                    Link("t.me/g3ntrix", destination: URL(string: "https://t.me/g3ntrix")!)
                        .font(.system(size: 12, weight: .medium))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var donateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Support development", systemImage: "heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.pink)
                    Spacer()
                }
                Text("If Cloak helps you, a small donation keeps it going.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                DonationRow(title: "TON",          address: "UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx")
                DonationRow(title: "USDT (BEP20)", address: "0x71F41696c60C4693305e67eE3Baa650a4E3dA796")
                DonationRow(title: "TRX (TRON)",   address: "TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV")
            }
        }
    }
}

private func formatMegabytes(_ bytes: Int) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_000_000)
}

private struct DonationRow: View {
    let title: String
    let address: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(address)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(address, forType: .string)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(copied ? "Copied" : "Copy address")
        }
    }
}
