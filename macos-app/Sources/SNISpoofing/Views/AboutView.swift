import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                authorCard
                donateCard
                linksRow
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
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
                        Text("build \(appBuild)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
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

    private var linksRow: some View {
        HStack(spacing: 12) {
            linkChip("Telegram", systemImage: "paperplane.fill", url: "https://t.me/g3ntrix")
            linkChip("Source", systemImage: "chevron.left.forwardslash.chevron.right", url: "https://github.com")
            linkChip("Report issue", systemImage: "ant.fill", url: "https://github.com")
            Spacer(minLength: 0)
        }
    }

    private func linkChip(_ label: String, systemImage: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            Label(label, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
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
