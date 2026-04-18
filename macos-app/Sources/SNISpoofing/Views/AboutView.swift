import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    CloakBrandImage(size: 72, cornerRadius: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cloak")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("A simple VPN client.")
                            .foregroundStyle(.secondary).font(.system(size: 13))
                    }
                    Spacer()
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Made by")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("g3ntrix")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Support the developer")
                            .font(.system(size: 13, weight: .semibold))
                        Text("If Cloak helps you, consider a small donation. Every bit is appreciated.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        DonationRow(
                            title: "TON",
                            address: "UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx"
                        )
                        DonationRow(
                            title: "USDT (BEP20)",
                            address: "0x71F41696c60C4693305e67eE3Baa650a4E3dA796"
                        )
                        DonationRow(
                            title: "TRX (TRON)",
                            address: "TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV"
                        )
                    }
                }

                Spacer(minLength: 12)
            }
        }
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
                .frame(width: 110, alignment: .leading)
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
                Label(copied ? "Copied" : "Copy",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
