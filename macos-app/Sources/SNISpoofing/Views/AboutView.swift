import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    CloakBrandImage(size: 72, cornerRadius: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cloak")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("SNI-Spoofing Python listener + Xray client — bridge profiles to your local listener.")
                            .foregroundStyle(.secondary).font(.system(size: 13))
                    }
                    Spacer()
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Core", "Xray + Python SNI-Spoofing")
                        row("Modes", "Local SOCKS (Xray) → bridge → listener")
                        row("Admin", "sudo for Python listener (packet injection)")
                    }
                }

                Spacer(minLength: 12)
            }
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.system(size: 13))
            Spacer()
        }
    }
}
